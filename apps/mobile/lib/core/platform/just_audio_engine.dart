import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'audio_engine.dart';

/// `just_audio` + `just_audio_background` (audio_service): background playback, lock-screen and
/// Bluetooth controls; `audio_session` pauses on calls and resumes after (spec §6.7).
class JustAudioEngine implements AudioEngine {
  /// [channelName]: the Android notification channel's name in the app language. [filesDir]: where
  /// the brand mark is copied for the lock-screen artwork (`artUri` must be a file or URL).
  JustAudioEngine({String Function()? channelName, Future<Directory> Function()? filesDir})
      : _channelName = channelName ?? (() => 'Recitation'),
        _filesDir = filesDir;

  final String Function() _channelName;
  final Future<Directory> Function()? _filesDir;
  AudioPlayer? _p;
  Uri? _art;

  /// Brand mark shown as the lock-screen / notification artwork (spec §6.7).
  static const artworkAsset = 'assets/brand/mark-navy.png';

  /// The player is created only after [init]: just_audio_background must be set up first.
  Future<AudioPlayer> get _player async {
    await init();
    return _p ??= AudioPlayer(handleInterruptions: true);
  }

  static Future<void>? _ready;

  /// Idempotent. Started after the first frame (lib/app/bootstrap.dart) and awaited by the first
  /// playback call, so it never delays start-up. A failure is retried on the next call.
  Future<void> init() => _ready ??= _setUp().catchError((Object e) {
        _ready = null;
        throw e;
      });

  Future<void> _setUp() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yaqinbrand.yaqeen.audio',
      androidNotificationChannelName: _channelName(),
      androidNotificationOngoing: true,
    );
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (_) {
      // Without a configured session playback still works; only call interruptions are coarser.
    }
    _art = await _artwork();
  }

  /// Copies the mark out of the bundle once; null (no artwork) when that fails.
  Future<Uri?> _artwork() async {
    final dir = _filesDir;
    if (dir == null) return null;
    try {
      final file = File('${(await dir()).path}/media/yaqeen-mark.png');
      if (!await file.exists()) {
        final bytes = await rootBundle.load(artworkAsset);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      }
      return Uri.file(file.path);
    } catch (_) {
      return null;
    }
  }

  Stream<T> _from<T>(Stream<T> Function(AudioPlayer p) pick) => Stream.fromFuture(_player).asyncExpand(pick);

  @override
  Future<Duration?> open(Uri source, {required AudioMeta meta, Duration start = Duration.zero}) async {
    final p = await _player;
    return p.setAudioSource(
      AudioSource.uri(source, tag: MediaItem(id: meta.id, title: meta.title, artist: meta.artist, album: meta.album, artUri: _art)),
      initialPosition: start,
    );
  }

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

  /// The ayah highlight must follow within 150 ms (spec §5.13): the default stream slows to one tick
  /// per 200 ms on any file longer than ~2.7 minutes.
  static const positionMinPeriod = Duration(milliseconds: 50);
  static const positionMaxPeriod = Duration(milliseconds: 100);

  @override
  Stream<Duration> get position =>
      _from((p) => p.createPositionStream(minPeriod: positionMinPeriod, maxPeriod: positionMaxPeriod));
  @override
  Stream<bool> get playing => _from((p) => p.playingStream);
  @override
  Stream<void> get completed => _from((p) => p.processingStateStream.where((s) => s == ProcessingState.completed));
}
