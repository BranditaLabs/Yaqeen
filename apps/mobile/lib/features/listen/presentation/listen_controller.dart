import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/audio_engine.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../quran/domain/quran_data.dart';
import '../data/audio_downloads.dart';
import '../data/listen_store.dart';
import '../data/reciter_repository.dart';
import '../domain/audio_models.dart';

enum ListenStatus { idle, loading, ready, unavailable, noReciter }

@immutable
class ListenState {
  const ListenState({
    this.status = ListenStatus.idle,
    this.reciter,
    this.surah = 1,
    this.ayah = 1,
    this.position = Duration.zero,
    this.duration,
    this.playing = false,
    this.speed = 1.0,
    this.repeat = ListenRepeat.off,
    this.synced = false,
    this.sleepAt,
    this.sleepEndOfSurah = false,
    this.sampleOf,
  });

  final ListenStatus status;
  final Reciter? reciter;
  final int surah;
  final int ayah;
  final Duration position;
  final Duration? duration;
  final bool playing;
  final double speed;
  final ListenRepeat repeat;

  /// Per-ayah timings are loaded (highlight + ayah skip work).
  final bool synced;
  final DateTime? sleepAt;
  final bool sleepEndOfSurah;

  /// Reciter id whose sample is playing (spec §5.14), or null.
  final String? sampleOf;

  AyahRef get ref => AyahRef(surah, ayah);
  bool get sleepOn => sleepAt != null || sleepEndOfSurah;

  ListenState copyWith({
    ListenStatus? status,
    Reciter? reciter,
    int? surah,
    int? ayah,
    Duration? position,
    Duration? duration,
    bool? playing,
    double? speed,
    ListenRepeat? repeat,
    bool? synced,
    DateTime? Function()? sleepAt,
    bool? sleepEndOfSurah,
    String? Function()? sampleOf,
  }) =>
      ListenState(
        status: status ?? this.status,
        reciter: reciter ?? this.reciter,
        surah: surah ?? this.surah,
        ayah: ayah ?? this.ayah,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        speed: speed ?? this.speed,
        repeat: repeat ?? this.repeat,
        synced: synced ?? this.synced,
        sleepAt: sleepAt == null ? this.sleepAt : sleepAt(),
        sleepEndOfSurah: sleepEndOfSurah ?? this.sleepEndOfSurah,
        sampleOf: sampleOf == null ? this.sampleOf : sampleOf(),
      );
}

/// Recitation playback for the whole app (spec §5.13, §6.7). Lives as long as the app so audio keeps
/// going while the user reads; the reader highlights [ListenState.ref] while playing.
class ListenController extends Notifier<ListenState> {
  final _subs = <StreamSubscription<Object?>>[];
  AyahTimings? _timings;
  Timer? _sleep;
  Timer? _tick;
  DateTime? _since;
  int _lastSavedSecond = -1;
  bool _disposed = false;

  AudioEngine get _engine => ref.read(audioEngineProvider);
  ReciterRepository get _reciters => ref.read(reciterRepositoryProvider);
  AudioDownloads get _downloads => ref.read(audioDownloadsProvider);
  ListenStore get _store => ref.read(listenStoreProvider);

  @override
  ListenState build() {
    final e = ref.watch(audioEngineProvider);
    _subs
      ..add(e.position.listen(_onPosition))
      ..add(e.playing.listen(_onPlaying))
      ..add(e.completed.listen((_) => _onCompleted()));
    ref.onDispose(() {
      _disposed = true;
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      _sleep?.cancel();
      _tick?.cancel();
    });
    return const ListenState();
  }

  /// Opens [surah] at [ayah] (or the saved position for that surah) and starts playing.
  Future<void> open(int surah, {int? ayah, bool autoplay = true, Reciter? reciter}) async {
    state = state.copyWith(status: ListenStatus.loading, surah: surah, ayah: ayah ?? 1, position: Duration.zero, synced: false);
    final r = reciter ?? await _currentReciter();
    if (r == null) {
      state = state.copyWith(status: ListenStatus.noReciter);
      return;
    }
    final snap = await _store.snapshot();
    final resume = ayah == null && snap != null && snap.surah == surah && snap.reciterId == r.id;
    _timings = await _reciters.timings(r, surah);
    final quran = await ref.read(quranDataProvider.future);
    final s = quran.surah(surah);
    final start = resume ? snap.position : (ayah != null && _timings != null ? _timings!.startOf(ayah) : Duration.zero);
    try {
      final duration = await _engine.open(
        await _downloads.sourceFor(r, surah),
        meta: AudioMeta(id: '${r.id}/$surah', title: s.nameAr, artist: r.nameAr, album: 'يقين'),
        start: start,
      );
      await _engine.setSpeed(resume ? snap.speed : state.speed);
      state = state.copyWith(
        status: ListenStatus.ready,
        reciter: r,
        ayah: _timings?.ayahAt(start) ?? (resume ? snap.ayah : (ayah ?? 1)),
        position: start,
        duration: duration,
        synced: _timings != null,
        speed: resume ? snap.speed : state.speed,
        repeat: resume ? snap.repeat : state.repeat,
      );
      if (autoplay) await _engine.play();
    } on Exception {
      state = state.copyWith(status: ListenStatus.unavailable, reciter: r, playing: false);
    }
  }

  Future<Reciter?> _currentReciter() async {
    if (state.reciter != null) return state.reciter;
    final all = await _reciters.list();
    if (all.isEmpty) return null;
    final id = await _store.reciterId();
    return all.firstWhere((r) => r.id == id, orElse: () => all.first);
  }

  Future<void> selectReciter(Reciter r) async {
    await _store.setReciter(r.id);
    if (state.status == ListenStatus.idle) {
      state = state.copyWith(reciter: r);
      return;
    }
    await open(state.surah, ayah: state.ayah, reciter: r, autoplay: state.playing);
  }

  /// Plays [r]'s sample through the single player; [stopSample] restores the surah, paused.
  /// Quran Foundation reciters have no separate sample: Al-Fatiha plays through the same resolver.
  Future<void> playSample(Reciter r) async {
    if (!r.hasSample) return;
    if (state.sampleOf != null) await stopSample();
    _save();
    state = state.copyWith(sampleOf: () => r.id);
    try {
      final explicit = r.sampleUrl;
      final source = explicit != null ? Uri.parse(explicit) : await _downloads.sourceFor(r, 1);
      await _engine.open(source, meta: AudioMeta(id: 'sample/${r.id}', title: r.nameAr, artist: r.nameEn));
      await _engine.play();
    } on Exception {
      state = state.copyWith(sampleOf: () => null);
    }
  }

  Future<void> stopSample() async {
    if (state.sampleOf == null) return;
    await _engine.pause();
    state = state.copyWith(sampleOf: () => null);
    if (state.status == ListenStatus.ready) await open(state.surah, autoplay: false, reciter: state.reciter);
  }

  Future<void> toggle() async {
    if (state.status != ListenStatus.ready) return;
    state.playing ? await _engine.pause() : await _engine.play();
  }

  Future<void> pause() => _engine.pause();

  Future<void> seek(Duration to) async {
    await _engine.seek(to);
    _onPosition(to);
  }

  Future<void> next() => _skip(1);
  Future<void> previous() => _skip(-1);

  Future<void> _skip(int delta) async {
    final t = _timings;
    if (t == null) return;
    final target = state.ayah + delta;
    if (target < 1) return seek(Duration.zero);
    if (target > t.ayahCount) {
      if (state.surah < QuranData.surahCount) await open(state.surah + 1, ayah: 1, autoplay: state.playing);
      return;
    }
    await seek(t.startOf(target));
  }

  Future<void> cycleSpeed() async {
    final i = listenSpeeds.indexOf(state.speed);
    final next = listenSpeeds[(i + 1) % listenSpeeds.length];
    await _engine.setSpeed(next);
    state = state.copyWith(speed: next);
    _save();
  }

  void toggleRepeatAyah() {
    state = state.copyWith(repeat: state.repeat == ListenRepeat.ayah ? ListenRepeat.off : ListenRepeat.ayah);
    _save();
  }

  void setRepeat(ListenRepeat mode) {
    state = state.copyWith(repeat: mode);
    _save();
  }

  /// [minutes] null turns the timer off; 0 means «نهاية السورة».
  void setSleep(int? minutes) {
    _sleep?.cancel();
    if (minutes == null) {
      state = state.copyWith(sleepAt: () => null, sleepEndOfSurah: false);
    } else if (minutes == 0) {
      state = state.copyWith(sleepAt: () => null, sleepEndOfSurah: true);
    } else {
      final d = Duration(minutes: minutes);
      state = state.copyWith(sleepAt: () => DateTime.now().add(d), sleepEndOfSurah: false);
      _sleep = Timer(d, () {
        _engine.pause();
        state = state.copyWith(sleepAt: () => null);
      });
    }
  }

  void _onPosition(Duration p) {
    if (state.sampleOf != null) return;
    final t = _timings;
    var ayah = t?.ayahAt(p) ?? state.ayah;
    if (t != null && state.repeat == ListenRepeat.ayah && state.playing && ayah > state.ayah) {
      // Loop the current ayah: jump back to its start as soon as playback crosses its end.
      _engine.seek(t.startOf(state.ayah));
      ayah = state.ayah;
      p = t.startOf(ayah);
    }
    state = state.copyWith(position: p, ayah: ayah);
    if (p.inSeconds ~/ 5 != _lastSavedSecond) {
      _lastSavedSecond = p.inSeconds ~/ 5;
      _save();
    }
  }

  void _onPlaying(bool playing) {
    if (playing == state.playing || state.sampleOf != null) return;
    state = state.copyWith(playing: playing);
    if (playing) {
      _since = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 30), (_) => _flushListened());
    } else {
      _tick?.cancel();
      _flushListened();
      _since = null;
      _save();
    }
  }

  Future<void> _onCompleted() async {
    if (state.sampleOf != null) {
      state = state.copyWith(sampleOf: () => null, playing: false);
      return;
    }
    if (state.repeat == ListenRepeat.surah) {
      await _engine.seek(Duration.zero);
      await _engine.play();
      return;
    }
    if (state.sleepEndOfSurah) {
      await _engine.pause();
      state = state.copyWith(sleepEndOfSurah: false);
      return;
    }
    if (state.surah < QuranData.surahCount) {
      await open(state.surah + 1, ayah: 1);
    } else {
      await _engine.pause();
    }
  }

  void _flushListened() {
    final since = _since;
    if (since == null) return;
    final now = DateTime.now();
    _since = now;
    addListened(now.difference(since));
  }

  /// Wall-clock listening; ≥ 5 min in a local day ticks the `listen` task once.
  @visibleForTesting
  Future<void> addListened(Duration played) async {
    if (played <= Duration.zero) return;
    // Read everything before the first await: playback can stop as the app (or a test) tears down.
    final s = ref.read(settingsProvider);
    final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)()));
    final store = _store;
    final canEarn = ref.read(sessionProvider).canEarnPoints;
    final challenge = ref.read(challengeRepositoryProvider);
    final r = ListenDay.add(await store.day(), today: today, played: played);
    await store.saveDay(r.day);
    if (r.tickNow && canEarn) {
      await challenge.complete(TaskKey.listen, today);
      if (!_disposed) ref.invalidate(challengeControllerProvider);
    }
  }

  void _save() {
    if (_disposed) return;
    final r = state.reciter;
    if (r == null || state.status != ListenStatus.ready) return;
    _store
        .saveSnapshot(
          PlaybackSnapshot(
            reciterId: r.id,
            surah: state.surah,
            ayah: state.ayah,
            position: state.position,
            speed: state.speed,
            repeat: state.repeat,
          ),
        )
        .ignore();
  }
}

final listenControllerProvider = NotifierProvider<ListenController, ListenState>(ListenController.new);
final recitersProvider = FutureProvider.autoDispose((ref) => ref.watch(reciterRepositoryProvider).list());
