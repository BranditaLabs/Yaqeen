import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'asr/pcm.dart';
import 'audio_recorder.dart';

/// The real microphone for «تلاواتي»: `record` streams 16-bit PCM at 16 kHz mono (one session for
/// the clip and the live follow); at stop the PCM is encoded once to AAC-LC .m4a, mono, 16 kHz,
/// 32 kbps (contracts `RECORDING_FORMAT`) by the platform's own encoder through the
/// `com.yaqinbrand.yaqeen/aac` channel — Android `AacEncoder.kt` (MediaCodec + MediaMuxer), iOS
/// `AacEncoder.swift` (AVAudioFile). Nothing is written before the take ends; the PCM never leaves
/// memory except as that one clip.
class PluginVoiceRecorder extends VoiceRecorder {
  PluginVoiceRecorder();

  static const _aac = MethodChannel('com.yaqinbrand.yaqeen/aac');
  static const _device = MethodChannel('com.yaqinbrand.yaqeen/device');

  /// The most PCM that is encoded (the rest of a take is dropped before the encoder). The server
  /// checks the longest of the file's `mdhd`, `stts` and frames × 1024 ÷ 16 kHz against contracts
  /// `RECORDING_MAX_MS` + `RECORDING_DURATION_TOLERANCE_MS` (30 250 ms), and all three include the
  /// encoder's priming (iOS AVAudioFile 2112 samples, Android MediaCodec ≈ 1024) and the padding of
  /// the last frame. 29 900 ms of PCM with 2112 priming samples and two padding frames is 472
  /// frames = 30 208 ms — inside the limit — so a full 30-second take (which runs a little past 30 s
  /// before the stop lands) is never refused as `recording_too_long`.
  static const hardCap = Duration(milliseconds: 29900);

  /// The encoders' priming (the larger, iOS) and the frames of padding allowed for, in [hardCap].
  static const primingSamples = 2112;
  static const paddingFrames = 2;

  AudioRecorder? _recorder;

  @override
  Future<MicPermission> permission({bool request = true}) async {
    final r = _recorder ??= AudioRecorder();
    return await r.hasPermission(request: request) ? MicPermission.granted : MicPermission.denied;
  }

  @override
  Future<VoiceTake> start() async {
    final r = _recorder ??= AudioRecorder();
    if (!await r.hasPermission()) throw const MicDeniedException();
    final bytes = await r.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: asrSampleRate,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
        // `mic` keeps the voice as it sounds (the recording is heard by people); the recogniser
        // copes with it as well as with `voiceRecognition`.
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
      ),
    );
    return _PluginTake(r, bytes);
  }

  @override
  Future<void> openSettings() async {
    if (Platform.isAndroid) {
      try {
        await _device.invokeMethod<void>('openAppSettings');
      } on PlatformException {
        // No settings activity: nothing else to open.
      } on MissingPluginException {
        // A background engine.
      }
      return;
    }
    await launchUrl(Uri.parse('app-settings:'));
  }

  /// Encodes little-endian 16-bit mono PCM at [sampleRate] to an AAC-LC .m4a at [path].
  static Future<void> encode(Uint8List pcm16, String path, {int sampleRate = asrSampleRate, int bitRate = 32000}) async {
    try {
      await _aac.invokeMethod<void>('encodePcm16', {'pcm': pcm16, 'sampleRate': sampleRate, 'bitRate': bitRate, 'path': path});
    } on PlatformException catch (e) {
      throw RecordingFailedException(e.code);
    } on MissingPluginException {
      throw const RecordingFailedException('no_encoder');
    }
    if (!File(path).existsSync()) throw const RecordingFailedException('no_output');
  }
}

class _PluginTake implements VoiceTake {
  _PluginTake(this._recorder, Stream<Uint8List> bytes) {
    _sub = bytes.listen(
      (chunk) {
        // The take's clock counts everything heard (the UI's 30-second stop follows it); only the
        // first [PluginVoiceRecorder.hardCap] is kept, followed live and encoded.
        _receivedBytes += chunk.length;
        final room = _maxBytes - _raw.length;
        if (room <= 0) {
          if (!_level.isClosed) _level.add(levelOf(pcm16ToFloat(chunk)));
          return;
        }
        final kept = chunk.length > room ? Uint8List.sublistView(chunk, 0, room) : chunk;
        _raw.add(kept);
        final s = _decoder.convert(kept);
        if (!_pcm.isClosed) _pcm.add(s);
        if (!_level.isClosed) _level.add(levelOf(s));
      },
      onDone: _close,
      onError: (Object e, StackTrace st) {
        if (!_pcm.isClosed) _pcm.addError(e, st);
      },
    );
  }

  final AudioRecorder _recorder;
  late final StreamSubscription<Uint8List> _sub;
  final _raw = BytesBuilder(copy: false);
  final _decoder = Pcm16Decoder();
  final _pcm = StreamController<Float32List>();
  final _level = StreamController<double>.broadcast();
  int _receivedBytes = 0;

  static final _maxBytes = PluginVoiceRecorder.hardCap.inMilliseconds * asrSampleRate ~/ 1000 * 2;

  void _close() {
    if (!_pcm.isClosed) _pcm.close().ignore();
    if (!_level.isClosed) _level.close().ignore();
  }

  @override
  Stream<Float32List> get pcm => _pcm.stream;
  @override
  Stream<double> get level => _level.stream;
  @override
  Duration get elapsed => Duration(microseconds: (_receivedBytes ~/ 2) * 1000000 ~/ asrSampleRate);

  Future<void> _end() async {
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } on Object {
      // Already stopped by the platform (an interruption).
    }
    await _sub.cancel();
    _close();
  }

  @override
  Future<RecordedClip> stop(String path) async {
    await _end();
    final bytes = _raw.takeBytes();
    final even = bytes.length.isOdd ? Uint8List.sublistView(bytes, 0, bytes.length - 1) : bytes;
    await PluginVoiceRecorder.encode(even, path);
    final samples = pcm16ToFloat(even);
    return RecordedClip(path: path, duration: Duration(microseconds: samples.length * 1000000 ~/ asrSampleRate), samples: samples);
  }

  @override
  Future<void> cancel() async {
    await _end();
    _raw.clear();
  }
}
