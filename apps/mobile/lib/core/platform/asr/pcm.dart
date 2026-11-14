import 'dart:math' as math;
import 'dart:typed_data';

/// The recogniser's audio: 16 kHz, mono, float samples in −1…1.
const asrSampleRate = 16000;

/// Little-endian signed 16-bit PCM (what the recorder streams) → floats. An odd trailing byte is
/// carried over by [Pcm16Decoder].
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final data = ByteData.sublistView(bytes, 0, n * 2);
  for (var i = 0; i < n; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Turns a byte stream into float chunks, keeping a split sample across chunk boundaries.
class Pcm16Decoder {
  int? _carry;

  Float32List convert(Uint8List chunk) {
    var bytes = chunk;
    if (_carry != null) {
      bytes = Uint8List(chunk.length + 1)
        ..[0] = _carry!
        ..setRange(1, chunk.length + 1, chunk);
      _carry = null;
    }
    if (bytes.length.isOdd) {
      _carry = bytes.last;
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }
    return pcm16ToFloat(bytes);
  }
}

/// A 0…1 level for the UI from a chunk's RMS, on a gentle log scale (−50 dB → 0, −10 dB → 1).
double levelOf(Float32List samples) {
  if (samples.isEmpty) return 0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  final rms = math.sqrt(sum / samples.length);
  if (rms <= 1e-6) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 40).clamp(0.0, 1.0);
}

/// A canonical 16-bit mono WAV of [samples] (the recordings feature writes clips this way).
Uint8List wavBytes(Float32List samples, {int sampleRate = asrSampleRate}) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Reads a 16-bit PCM WAV back to floats (mono, or the first channel). Throws [FormatException].
({Float32List samples, int sampleRate}) readWav(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') throw const FormatException('not a wav file');
  var at = 12;
  int? channels, rate, bits;
  while (at + 8 <= bytes.length) {
    final id = tag(at);
    final size = d.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ') {
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (channels == null || rate == null || bits != 16) throw const FormatException('16-bit PCM only');
      final frames = math.min(size, bytes.length - body) ~/ (2 * channels);
      final out = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        out[i] = d.getInt16(body + i * 2 * channels, Endian.little) / 32768.0;
      }
      return (samples: out, sampleRate: rate);
    }
    at = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}
