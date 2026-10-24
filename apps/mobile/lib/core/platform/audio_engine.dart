import 'dart:async';

/// Lock-screen / notification metadata (spec §6.7).
class AudioMeta {
  const AudioMeta({required this.id, required this.title, required this.artist, this.album});
  final String id;
  final String title;
  final String artist;
  final String? album;
}

/// Player behind an interface so screens and controllers test without a platform channel.
/// The real implementation (`JustAudioEngine`) is overridden in `main.dart`.
abstract interface class AudioEngine {
  /// Loads [source] (file:// or https://) and returns its duration when known. Throws on failure.
  Future<Duration?> open(Uri source, {required AudioMeta meta, Duration start = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();

  Stream<Duration> get position;
  Stream<bool> get playing;

  /// Emits when the loaded file finishes.
  Stream<void> get completed;
}

/// Deterministic in-memory engine for tests and the debug gallery: position advances only
/// through [advance], never by wall-clock.
class FakeAudioEngine implements AudioEngine {
  final _pos = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _done = StreamController<void>.broadcast();
  final opened = <Uri>[];
  Duration duration = const Duration(minutes: 20);
  Duration current = Duration.zero;
  bool isPlaying = false;
  double speed = 1;
  Object? failWith;

  @override
  Future<Duration?> open(Uri source, {required AudioMeta meta, Duration start = Duration.zero}) async {
    if (failWith != null) throw failWith!;
    opened.add(source);
    current = start;
    _pos.add(current);
    return duration;
  }

  @override
  Future<void> play() async => _playing.add(isPlaying = true);
  @override
  Future<void> pause() async => _playing.add(isPlaying = false);
  @override
  Future<void> stop() async => _playing.add(isPlaying = false);
  @override
  Future<void> seek(Duration position) async => _pos.add(current = position);
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  void advance(Duration by) {
    current += by;
    if (current >= duration) {
      current = duration;
      _pos.add(current);
      _done.add(null);
      return;
    }
    _pos.add(current);
  }

  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<void> get completed => _done.stream;
}
