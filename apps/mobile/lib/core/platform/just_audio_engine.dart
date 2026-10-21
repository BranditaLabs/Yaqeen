import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'audio_engine.dart';

/// `just_audio` + `just_audio_background` (audio_service): background playback, lock-screen and
/// Bluetooth controls; `audio_session` pauses on calls and resumes after (spec §6.7).
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() : _player = AudioPlayer(handleInterruptions: true);
  final AudioPlayer _player;

  /// Call once before `runApp`.
  static Future<void> init() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yaqinbrand.yaqeen.audio',
      androidNotificationChannelName: 'Recitation',
      androidNotificationOngoing: true,
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  @override
  Future<Duration?> open(Uri source, {required AudioMeta meta, Duration start = Duration.zero}) => _player.setAudioSource(
        AudioSource.uri(source, tag: MediaItem(id: meta.id, title: meta.title, artist: meta.artist, album: meta.album)),
        initialPosition: start,
      );

  @override
  Future<void> play() async {
    // `play()` completes when playback stops; don't hold the caller.
    _player.play().ignore();
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<Duration> get position => _player.positionStream;
  @override
  Stream<bool> get playing => _player.playingStream;
  @override
  Stream<void> get completed => _player.processingStateStream.where((s) => s == ProcessingState.completed);
}
