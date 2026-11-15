import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/platform/asr/pcm.dart';
import 'package:yaqeen/core/platform/plugin_voice_recorder.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';

/// The server's view of an encoded take (services/api `domain/m4a.ts` › `durations`): the longest of
/// `mdhd`, `stts` and frames × 1024 ÷ 16 kHz — every one of them counts the encoder's priming and the
/// padding of the last frame — checked against contracts `RECORDING_MAX_MS` +
/// `RECORDING_DURATION_TOLERANCE_MS` (250).
int serverLongestMs(int pcmSamples, {required int primingSamples, required int paddingFrames}) {
  final frames = ((pcmSamples + primingSamples) / 1024).ceil() + paddingFrames;
  return (frames * 1024 * 1000 / asrSampleRate).round();
}

void main() {
  const limitMs = kRecordingMaxMs + 250;

  test('a full 30-second take is encoded inside the server limit on both platforms', () {
    final samples = PluginVoiceRecorder.hardCap.inMilliseconds * asrSampleRate ~/ 1000;
    // iOS AVAudioFile primes 2112 samples, Android MediaCodec about 1024; one or two frames of padding.
    for (final priming in [1024, 2048, 2112]) {
      for (final padding in [0, 1, 2]) {
        expect(
          serverLongestMs(samples, primingSamples: priming, paddingFrames: padding),
          lessThanOrEqualTo(limitMs),
          reason: 'priming $priming, padding $padding',
        );
      }
    }
    expect(PluginVoiceRecorder.primingSamples, 2112);
    expect(PluginVoiceRecorder.paddingFrames, 2);
  });

  test('the cap keeps nearly the whole 30 seconds', () {
    expect(PluginVoiceRecorder.hardCap.inMilliseconds, greaterThanOrEqualTo(kRecordingMaxMs - 200));
  });
}
