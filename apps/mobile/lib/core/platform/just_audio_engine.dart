import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'audio_engine.dart';

/// `just_audio` + `just_audio_background` (audio_service): background playback, lock-screen and
/// Bluetooth controls; `audio_session` pauses on calls and resumes after (spec §6.7).
class JustAudioEngine implements AudioEngine {
  AudioPlayer? _p;

  /// The player is created only after [init]: just_audio_background must be set up first.
  Future<AudioPlayer> get _player async {
    await init();
    return _p ??= AudioPlayer(handleInterruptions: true);
  }

  static Future<void>? _ready;

  /// Idempotent. Started after the first frame (lib/app/bootstrap.dart) and awaited by the first
  /// playback call, so it never delays start-up. A failure is retried on the next call.
  static Future<void> init() => _ready ??= _setUp().catchError((Object e) {
        _ready = null;
        throw e;
      });

  static Future<void> _setUp() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yaqinbrand.yaqeen.audio',
      androidNotificationChannelName: 'Recitation',
      androidNotificationOngoing: true,
    );
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (_) {
      // Without a configured session playback still works; only call interruptions are coarser.
    }
  }

  Stream<T> _from<T>(Stream<T> Function(AudioPlayer p) pick) => Stream.fromFuture(_player).asyncExpand(pick);

  @override
  Future<Duration?> open(Uri source, {required AudioMeta meta, Duration start = Duration.zero}) async => (await _player).setAudioSource(
        AudioSource.uri(source, tag: MediaItem(id: meta.id, title: meta.title, artist: meta.artist, album: meta.album)),
        initialPosition: start,
      );

  @override
  Future<void> play() async {
    // `play()` completes when playback stops; don't hold the caller.
    (await _player).play().ignore();
  }

  @override
  Future<void> pause() async => (await _player).pause();
  @override
  Future<void> seek(Duration position) async => (await _player).seek(position);
  @override
  Future<void> setSpeed(double speed) async => (await _player).setSpeed(speed);
  @override
  Future<void> stop() async => (await _player).stop();

  @override
  Stream<Duration> get position => _from((p) => p.positionStream);
  @override
  Stream<bool> get playing => _from((p) => p.playingStream);
  @override
  Stream<void> get completed => _from((p) => p.processingStateStream.where((s) => s == ProcessingState.completed));
}
