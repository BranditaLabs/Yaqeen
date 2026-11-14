import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/recitation_engine.dart';
import '../../listen/presentation/listen_controller.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../domain/recitation.dart';
import '../domain/recite_progress.dart';
import 'asr_model_controller.dart';

/// Where a «تسميع» attempt is.
enum RecitePhase {
  /// Ready, not listening (before the first word, or after «إنهاء»'s card).
  idle,
  listening,

  /// Stopped mid-way (a tap, the app going to the background); «متابعة» goes on.
  paused,

  /// «سمّع ثم تحقّق»: the recording is being checked (slow phones).
  checking,

  /// «إنهاء» or the passage recited to its end: the end card.
  done,
}

/// The «تسميع» layer's state (spec §5.12, §6.8). Recognition runs on the device; audio and results
/// never leave it — the only thing that ever goes further is a hifz grade the user confirms.
@immutable
class ReciteState {
  const ReciteState({
    this.available,
    this.phase = RecitePhase.idle,
    this.passage,
    this.progress,
    this.version = 0,
    this.showText = false,
    this.live = true,
    this.heard = '',
    this.denied = false,
    this.retrying = false,
  });

  /// null while the device is being asked (the mic is a shimmering disc then).
  final bool? available;
  final RecitePhase phase;
  final Passage? passage;

  /// The attempt (marks, help, summary). Mutable on purpose; [version] moves with every change.
  final ReciteProgress? progress;
  final int version;

  /// «إظهار النص»: the hidden words show faintly (beginners). Off: only the voice reveals them.
  final bool showText;

  /// Live follow on this phone; false → «سمّع ثم تحقّق» (record, then check at once).
  final bool live;

  /// What was heard (committed) across the attempt — kept on the device to restore a guided test.
  final String heard;

  /// The microphone was refused.
  final bool denied;

  /// «سمّع الملاحظات فقط»: this attempt covers only the ayat that had notes.
  final bool retrying;

  bool get listening => phase == RecitePhase.listening;
  bool get started => (progress?.started ?? false) || heard.isNotEmpty;
  int get recited => progress?.recitedAyat ?? 0;
  int get ayatCount => progress?.ayat.length ?? 0;
  double get progressValue => ayatCount == 0 ? 0 : recited / ayatCount;
  List<AyahRef> get recitedAyat => progress?.recitedRefs ?? const [];
  List<WordResult> get notes => progress?.flagged ?? const [];
  int get helps => progress?.helps ?? 0;
  Map<AyahRef, Set<int>> get marks => progress?.marks ?? const {};
  List<AyahResult> get results => progress?.results ?? const [];
  Duration get elapsed => progress?.elapsed ?? Duration.zero;

  /// Compat with the first layer: «إظهار الآيات».
  bool get showAyat => showText;

  ReciteState copyWith({
    bool? Function()? available,
    RecitePhase? phase,
    Passage? Function()? passage,
    ReciteProgress? Function()? progress,
    bool? showText,
    bool? live,
    String? heard,
    bool? denied,
    bool? retrying,
  }) =>
      ReciteState(
        available: available == null ? this.available : available(),
        phase: phase ?? this.phase,
        passage: passage == null ? this.passage : passage(),
        progress: progress == null ? this.progress : progress(),
        version: version + 1,
        showText: showText ?? this.showText,
        live: live ?? this.live,
        heard: heard ?? this.heard,
        denied: denied ?? this.denied,
        retrying: retrying ?? this.retrying,
      );
}

/// The microphone, the engine and the attempt for the reader's «تسميع» layer. Lives while the
/// reader shows it; leaving the layer (or the app going to the background) stops the microphone.
class ReciteController extends AutoDisposeNotifier<ReciteState> {
  StreamSubscription<RecognitionUpdate>? _sub;
  Timer? _ticker;
  Duration _clock = Duration.zero;
  late RecitationEngine _engine;
  String _heardBefore = '';
  LiveSupport? _support;
  _Lifecycle? _lifecycle;

  /// Help escalates on this beat (and only while listening live).
  static const tick = Duration(milliseconds: 250);

  /// Shown once before the first recitation («نستمع لتلاوتك على جهازك فقط»).
  static const rationaleKey = 'recite.rationaleSeen';

  @override
  ReciteState build() {
    _engine = ref.watch(recitationEngineProvider);
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      _ticker?.cancel();
      // Only this layer's own microphone: the engine may be serving voice «تحفيظ» meanwhile.
      final mine = _sub != null;
      _sub?.cancel();
      _lifecycle?.dispose();
      if (mine) _engine.stop().ignore();
    });
    // A download finishing while the layer is open makes it ready.
    ref.listen(asrModelControllerProvider.select((s) => s.ready), (_, ready) {
      if (ready && !disposed) _engine.isAvailable().then((v) => state = state.copyWith(available: () => v)).ignore();
    });
    _engine.isAvailable().then((v) {
      if (!disposed) state = state.copyWith(available: () => v);
    }).ignore();
    _lifecycle = _Lifecycle(
      onBackground: () {
        if (state.listening) pause().ignore();
      },
    );
    return const ReciteState();
  }

  Future<bool> rationaleSeen() async => await ref.read(kvStoreProvider).read(rationaleKey) != null;
  Future<void> markRationaleSeen() => ref.read(kvStoreProvider).write(rationaleKey, '1');

  List<(AyahRef, String)> _expected(List<AyahRef> ayat, QuranData q) => [for (final r in ayat) (r, q.text(r))];

  /// Sets the passage being recited (a new one starts clean).
  void prepare(Passage p, QuranData q) {
    if (state.passage == p && state.progress != null && !state.retrying) return;
    _fresh(p, p.range, q);
    state = state.copyWith(phase: RecitePhase.idle, retrying: false);
  }

  void _fresh(Passage p, List<AyahRef> ayat, QuranData q) {
    _clock = Duration.zero;
    _heardBefore = '';
    state = state.copyWith(passage: () => p, progress: () => ReciteProgress(_expected(ayat, q)), heard: '');
  }

  void setShowText(bool v) => state = state.copyWith(showText: v);

  /// Compat: «إظهار الآيات».
  void setShowAyat(bool v) => setShowText(v);

  /// Starts listening to [p] (or goes on with the attempt on it); recitation playing is paused
  /// first (the reader's own voice only).
  Future<void> start(Passage p, QuranData q) async {
    await ref.read(listenControllerProvider.notifier).pause();
    final stopping = _stopping;
    if (stopping != null) await stopping;
    final s = state;
    final fresh = s.passage != p || s.progress == null || s.progress!.complete || s.phase == RecitePhase.done;
    if (fresh && !(s.retrying && s.passage == p && !(s.progress?.complete ?? true))) {
      _fresh(p, p.range, q);
      state = state.copyWith(retrying: false);
    } else {
      state.progress!.resume(_clock);
    }
    await _listen();
  }

  Future<void> _listen() async {
    // A pause still closing (its last phrase being decoded) finishes first: what it heard is kept,
    // and the new session never races the old one for the microphone.
    final stopping = _stopping;
    if (stopping != null) await stopping;
    await _drop();
    _support ??= await _engine.liveSupport();
    final live = _support!.live;
    state = state.copyWith(phase: RecitePhase.listening, live: live, denied: false);
    final closed = _closed = Completer<void>();
    _sub = _engine.listen(live: live).listen(
      _onUpdate,
      onError: (Object e) {
        _ticker?.cancel();
        state = state.copyWith(phase: RecitePhase.idle, denied: e is MicrophoneDenied);
        if (!closed.isCompleted) closed.complete();
      },
      onDone: () {
        _onDone();
        if (!closed.isCompleted) closed.complete();
      },
    );
    _ticker?.cancel();
    // Live: help escalates on this beat. Recording («سمّع ثم تحقّق»): it only keeps the time.
    _ticker = Timer.periodic(tick, (_) => _tick(help: live));
  }

  void _tick({required bool help}) {
    final p = state.progress;
    if (p == null || !state.listening) return;
    _clock += tick;
    if (p.tick(_clock, help: help)) state = state.copyWith();
  }

  /// A stop in progress: the engine closing and the session's last updates delivered.
  Future<void>? _stopping;

  /// Completes when the current session's stream has delivered everything (or was dropped).
  Completer<void>? _closed;

  /// Closes the microphone and waits until the session's last phrase has been judged; [start],
  /// [resume] and [finish] build on that.
  Future<void> _stopEngine() {
    final closed = _closed;
    Future<void> run() async {
      await _engine.stop();
      if (closed != null && _sub != null) await closed.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    }

    final f = _stopping = run();
    return f.whenComplete(() {
      if (identical(_stopping, f)) _stopping = null;
    });
  }

  /// Drops the current session's stream without waiting for the rest of it.
  Future<void> _drop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
    final closed = _closed;
    if (closed != null && !closed.isCompleted) closed.complete();
  }

  void _onUpdate(RecognitionUpdate u) {
    final p = state.progress;
    if (p == null) return;
    p.update(u, _clock);
    final heard = [if (_heardBefore.isNotEmpty) _heardBefore, ...u.committed.map((w) => w.text)].join(' ');
    state = state.copyWith(heard: heard);
    if (u.isFinal) _heardBefore = heard;
    // The whole passage recited: the microphone closes by itself and the end card follows.
    if (p.complete && state.listening) finish().ignore();
  }

  void _onDone() {
    _ticker?.cancel();
    _sub = null;
    final phase = state.phase;
    if (phase == RecitePhase.checking) {
      state.progress?.finish();
      state = state.copyWith(phase: RecitePhase.done);
    } else if (phase == RecitePhase.listening) {
      state = state.copyWith(phase: RecitePhase.paused);
    }
  }

  /// Pause: the microphone closes (what was said is decoded and kept); «متابعة» goes on.
  Future<void> pause() async {
    if (!state.listening) return;
    _ticker?.cancel();
    final live = state.live;
    state = state.copyWith(phase: live ? RecitePhase.paused : RecitePhase.checking);
    await _stopEngine();
  }

  Future<void> resume() async {
    if (state.phase != RecitePhase.paused || state.progress == null) return;
    // The paused session's last phrase lands first (before the attempt counts a new session).
    final stopping = _stopping;
    if (stopping != null) await stopping;
    if (state.phase != RecitePhase.paused || state.progress == null) return;
    state.progress!.resume(_clock);
    await _listen();
  }

  /// «إنهاء»: the microphone closes, the attempt is judged and the end card follows.
  Future<void> finish() async {
    _ticker?.cancel();
    if (state.listening) {
      if (state.live) {
        state = state.copyWith(phase: RecitePhase.done);
        await _stopEngine();
        state.progress?.finish();
        state = state.copyWith();
      } else {
        // Checked at once when the recording ends; `done` follows the final update.
        state = state.copyWith(phase: RecitePhase.checking);
        await _stopEngine();
      }
    } else {
      state.progress?.finish();
      state = state.copyWith(phase: RecitePhase.done);
    }
  }

  /// Compat: stop listening (leaving the test, the layer).
  Future<void> stop() async {
    await _drop();
    _ticker?.cancel();
    if (state.listening || state.phase == RecitePhase.checking) await _stopEngine();
    if (state.listening) state = state.copyWith(phase: RecitePhase.paused);
  }

  /// The end card was closed: back to an idle page that keeps its marks.
  void acknowledge() {
    if (state.phase == RecitePhase.done) state = state.copyWith(phase: RecitePhase.idle);
  }

  /// «سمّع الملاحظات فقط»: a new attempt over the ayat that had notes, and listening at once.
  Future<void> retryFlagged(QuranData q) async {
    final p = state.progress;
    final passage = state.passage;
    if (p == null || passage == null) return;
    final ayat = p.flaggedAyat;
    if (ayat.isEmpty) return;
    await stop();
    _clock = Duration.zero;
    _heardBefore = '';
    state = state.copyWith(progress: () => ReciteProgress(_expected(ayat, q)), heard: '', retrying: true, phase: RecitePhase.idle);
    await ref.read(listenControllerProvider.notifier).pause();
    await _listen();
  }

  /// Back to an untouched passage (a new attempt).
  Future<void> reset(QuranData q) async {
    await stop();
    final p = state.passage;
    if (p != null) _fresh(p, p.range, q);
    state = state.copyWith(phase: RecitePhase.idle, retrying: false);
  }

  /// A guided session restoring the last attempt (raw results stay on the device).
  void restore(Passage p, QuranData q, String heard) {
    _fresh(p, p.range, q);
    final progress = state.progress!..update(RecognitionUpdate.text(heard), Duration.zero);
    _heardBefore = heard;
    state = state.copyWith(heard: heard, phase: progress.complete ? RecitePhase.done : RecitePhase.paused);
    if (progress.complete) state = state.copyWith(phase: RecitePhase.idle);
  }
}

/// Stops the microphone when the app leaves the foreground (screen off, another app). Not on
/// `inactive`: the OS microphone-permission dialog, a notification shade or an incoming-call banner
/// make the app inactive while it stays on screen — pausing there would stop the very first
/// recitation while its permission is being asked.
bool leftForeground(AppLifecycleState s) => s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached;

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle({required this.onBackground}) {
    WidgetsBinding.instance.addObserver(this);
  }
  final VoidCallback onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (leftForeground(state)) onBackground();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}

final reciteControllerProvider = NotifierProvider.autoDispose<ReciteController, ReciteState>(ReciteController.new);
