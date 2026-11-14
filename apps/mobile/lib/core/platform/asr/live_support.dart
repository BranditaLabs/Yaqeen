import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../storage/kv_store.dart';
import '../recitation_engine.dart';
import 'live_transcriber.dart';
import 'pcm.dart';

/// Measures, once per model and phone, whether live follow keeps up (spec §6.8): a 3 s clip is
/// decoded (after one warm-up run) and the real-time factor kept in the device store. Above
/// [maxRtf] the phone checks a recitation after it ends («سمّع ثم تحقّق») instead of live.
abstract final class LiveSupportProbe {
  static const key = 'asr.liveSupport';
  static const maxRtf = 0.8;
  static const clip = Duration(seconds: 3);

  /// A quiet, speech-band noise clip (generated — nothing bundled, nothing recorded).
  static Float32List probeClip({int seed = 7}) {
    final r = math.Random(seed);
    final n = clip.inMilliseconds * asrSampleRate ~/ 1000;
    final out = Float32List(n);
    var prev = 0.0;
    for (var i = 0; i < n; i++) {
      prev = 0.85 * prev + 0.15 * (r.nextDouble() * 2 - 1);
      out[i] = prev * 0.08;
    }
    return out;
  }

  static Future<LiveSupport?> remembered(KvStore kv, String modelId) async {
    final raw = await kv.read(key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['model'] != modelId) return null;
      return LiveSupport(live: m['live'] == true, rtf: (m['rtf'] as num?)?.toDouble());
    } on Object {
      return null;
    }
  }

  static Future<LiveSupport> measure(SpeechDecoder decoder, {Stopwatch Function() stopwatch = Stopwatch.new}) async {
    final samples = probeClip();
    await decoder.decode(samples); // warm-up: the first run pays for loading
    final sw = stopwatch()..start();
    await decoder.decode(samples);
    sw.stop();
    final rtf = sw.elapsedMicroseconds / clip.inMicroseconds;
    return LiveSupport(live: rtf <= maxRtf, rtf: rtf);
  }

  static Future<void> remember(KvStore kv, String modelId, LiveSupport s) =>
      kv.write(key, jsonEncode({'model': modelId, 'live': s.live, 'rtf': s.rtf}));

  /// The remembered answer, else a measurement (remembered for next time).
  static Future<LiveSupport> resolve(KvStore kv, String modelId, Future<SpeechDecoder> Function() decoder) async {
    final known = await remembered(kv, modelId);
    if (known != null) return known;
    final s = await measure(await decoder());
    await remember(kv, modelId, s);
    return s;
  }
}
