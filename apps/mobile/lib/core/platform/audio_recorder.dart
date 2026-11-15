import 'dart:async';
import 'dart:typed_data';

/// The microphone for «تلاواتي» (design doc §16, APP_SPEC §5.24): one session records the clip
/// that is uploaded **and** streams the same audio as 16 kHz mono PCM, so the on-device recogniser
/// (`RecitationEngine.startFromPcm`) follows the words live from the very same take.
///
/// The clip is exactly contracts `RECORDING_FORMAT`: AAC-LC in an MPEG-4 audio file (.m4a), mono,
/// 16 kHz, ≈ 32 kbps. The plugin implementation (`plugin_voice_recorder.dart`) keeps the PCM in
/// memory while recording and encodes it once at stop on the platform's own AAC encoder (Android
/// MediaCodec + MediaMuxer, iOS AVAudioFile); nothing is written before the take ends.
///
/// Tests and platforms without a microphone use [NoopVoiceRecorder] (the default provider) or
/// [FakeVoiceRecorder].
abstract class VoiceRecorder {
  const VoiceRecorder();

  /// Whether the app may use the microphone; [request] asks the OS the first time.
  Future<MicPermission> permission({bool request = true});

  /// Opens the microphone. Throws [MicDeniedException] when it is refused.
  Future<VoiceTake> start();

  /// This app's page in the OS settings (after the permission was refused for good).
  Future<void> openSettings();
}

enum MicPermission { granted, denied }

class MicDeniedException implements Exception {
  const MicDeniedException();
}

/// The recording could not be encoded or written (no encoder on the device, no space).
class RecordingFailedException implements Exception {
  const RecordingFailedException([this.reason]);
  final String? reason;
  @override
  String toString() => 'RecordingFailedException($reason)';
}

/// One open microphone.
abstract class VoiceTake {
  /// 16 kHz mono float samples (−1…1) as they arrive. Single subscription; closes at [stop]/[cancel].
  Stream<Float32List> get pcm;

  /// The input level 0…1 per chunk (`levelOf`), for `YqLiveLevel`. Broadcast; closes with [pcm].
  Stream<double> get level;

  /// How long the take has run (the samples received so far).
  Duration get elapsed;

  /// Closes the microphone and encodes the clip to [path] (.m4a). The [RecordedClip] also carries
  /// the PCM for the on-device check (kept in memory only).
  Future<RecordedClip> stop(String path);

  /// Closes the microphone and drops the audio.
  Future<void> cancel();
}

/// A finished take on the device.
class RecordedClip {
  const RecordedClip({required this.path, required this.duration, required this.samples});

  /// The .m4a file (contracts `RECORDING_FORMAT`).
  final String path;
  final Duration duration;

  /// 16 kHz mono floats of the same take (on-device check only; never stored or uploaded).
  final Float32List samples;
}

/// Default (tests, platforms without the plugin): the microphone is never available.
class NoopVoiceRecorder extends VoiceRecorder {
  const NoopVoiceRecorder();
  @override
  Future<MicPermission> permission({bool request = true}) async => MicPermission.denied;
  @override
  Future<VoiceTake> start() async => throw const MicDeniedException();
  @override
  Future<void> openSettings() async {}
}

/// A scripted microphone for tests: [FakeVoiceTake.emit] feeds samples and levels; [stop] writes
/// a few placeholder bytes at the path through [writeFile] (when given).
class FakeVoiceRecorder extends VoiceRecorder {
  FakeVoiceRecorder({this.allowed = true, this.writeFile});

  bool allowed;
  final Future<void> Function(String path, List<int> bytes)? writeFile;
  int settingsOpened = 0;
  int starts = 0;
  FakeVoiceTake? take;

  @override
  Future<MicPermission> permission({bool request = true}) async => allowed ? MicPermission.granted : MicPermission.denied;

  @override
  Future<VoiceTake> start() async {
    if (!allowed) throw const MicDeniedException();
    starts++;
    return take = FakeVoiceTake(writeFile: writeFile);
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeVoiceTake implements VoiceTake {
  FakeVoiceTake({this.writeFile});

  final Future<void> Function(String path, List<int> bytes)? writeFile;
  final _pcm = StreamController<Float32List>();
  final _level = StreamController<double>.broadcast();
  int _samples = 0;
  bool stopped = false;
  bool cancelled = false;
  String? stoppedAt;

  /// One chunk of [ms] milliseconds of a constant [value] signal, with its level.
  void emit({int ms = 100, double level = 0.5, double value = 0.1}) {
    final n = ms * 16;
    _samples += n;
    _pcm.add(Float32List(n)..fillRange(0, n, value));
    _level.add(level);
  }

  @override
  Stream<Float32List> get pcm => _pcm.stream;
  @override
  Stream<double> get level => _level.stream;
  @override
  Duration get elapsed => Duration(microseconds: _samples * 1000000 ~/ 16000);

  @override
  Future<RecordedClip> stop(String path) async {
    stopped = true;
    stoppedAt = path;
    await writeFile?.call(path, const [0, 0, 0, 24, 102, 116, 121, 112]);
    _pcm.close().ignore();
    _level.close().ignore();
    return RecordedClip(path: path, duration: elapsed, samples: Float32List(_samples));
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    _pcm.close().ignore();
    _level.close().ignore();
  }
}
