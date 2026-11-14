import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/recitation_engine.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import '../../recite/domain/recitation_follower.dart';
import '../../recite/presentation/recite_controller.dart' show leftForeground;

/// What the voice is doing in «تحفيظ».
enum RehearsalMode { off, repeats, echo }

@immutable
class RehearsalState {
  const RehearsalState({this.mode = RehearsalMode.off, this.frontier = 0, this.total = 0, this.denied = false});
  final RehearsalMode mode;

  /// Words of the current repetition (or echoed ayah) recited so far, of [total].
  final int frontier;
  final int total;
  final bool denied;

  bool get listening => mode != RehearsalMode.off;
  double get progress => total == 0 ? 0 : (frontier / total).clamp(0.0, 1.0);
}

/// One repetition of a passage counts when the voice reaches its last word with at most
/// [maxNotes] notes (spec §5.25 «تكرار ×10»).
bool repetitionCounts(RecitationFollower f, {int maxNotes = VoiceRehearsal.maxNotes}) =>
    f.done && f.marks.where((m) => m != null && m != WordMark.ok).length <= maxNotes;

/// Voice-aware rehearsal for guided hifz (spec §5.25): in «تكرار ×10» each full recitation of the
/// passage counts by itself (the «كرّرت» counter stays as fallback and override); in echo mode
/// («ردّد بعد القارئ») each ayah the reciter plays is followed by the microphone until the user has
/// repeated it. On-device only — nothing heard is kept once a repetition is counted.
class VoiceRehearsal extends AutoDisposeNotifier<RehearsalState> {
  static const maxNotes = 1;

  RecitationFollower? _follower;
  StreamSubscription<RecognitionUpdate>? _sub;
  int _committed = 0;
  List<ExpectedWord> _words = const [];
  VoidCallback? _onRepeat;
  Completer<bool>? _echo;

  late RecitationEngine _engine;

  @override
  RehearsalState build() {
    _engine = ref.watch(recitationEngineProvider);
    // The microphone never stays open behind the screen (screen off, another app) — but not on
    // `inactive` (the permission dialog, a banner): see [leftForeground].
    final lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (leftForeground(s) && _sub != null) stop().ignore();
      },
    );
    ref.onDispose(() {
      lifecycle.dispose();
      final listening = _sub != null;
      _sub?.cancel();
      _sub = null;
      final e = _echo;
      if (e != null && !e.isCompleted) e.complete(false);
      if (listening) _engine.stop().ignore();
    });
    return const RehearsalState();
  }

  /// Listens through «تكرار ×10»: [onRepeat] fires once per full recitation of [p].
  Future<void> listenForRepeats(Passage p, QuranData q, {required VoidCallback onRepeat}) async {
    await stop();
    _words = ExpectedWord.of(p.expected(q));
    _onRepeat = onRepeat;
    _follower = RecitationFollower(_words);
    _committed = 0;
    state = RehearsalState(mode: RehearsalMode.repeats, total: _words.length);
    _sub = _engine.listen().listen(_onRepeatUpdate, onError: _onError, onDone: _onDone);
  }

  void _onRepeatUpdate(RecognitionUpdate u) {
    final f = _follower;
    if (f == null) return;
    _committed = u.committed.length;
    f.update([for (final w in u.committed) w.text], [for (final w in u.tentative) w.text]);
    if (f.done) {
      if (repetitionCounts(f)) _onRepeat?.call();
      // The next repetition starts after what has been heard so far.
      _follower = RecitationFollower(_words)..startAfter(_committed);
      state = RehearsalState(mode: RehearsalMode.repeats, total: _words.length);
      return;
    }
    state = RehearsalState(mode: RehearsalMode.repeats, frontier: f.frontier, total: _words.length);
  }

  /// Echo: listens until ayah [a] has been repeated, or [timeout]. True when it was recited.
  Future<bool> echoAyah(AyahRef a, QuranData q, {required Duration timeout}) async {
    await stop();
    _words = ExpectedWord.of([(a, q.text(a))]);
    _follower = RecitationFollower(_words);
    state = RehearsalState(mode: RehearsalMode.echo, total: _words.length);
    final done = _echo = Completer<bool>();
    _sub = _engine.listen().listen(
      (u) {
        final f = _follower;
        if (f == null) return;
        f.update([for (final w in u.committed) w.text], [for (final w in u.tentative) w.text]);
        state = RehearsalState(mode: RehearsalMode.echo, frontier: f.frontier, total: _words.length);
        // The last word heard (even tentatively) is enough to move on in echo practice.
        if (f.done || f.frontier >= _words.length) {
          if (!done.isCompleted) done.complete(true);
        }
      },
      onError: (Object e) {
        _onError(e);
        if (!done.isCompleted) done.complete(false);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(false);
      },
    );
    final heard = await done.future.timeout(timeout, onTimeout: () => false);
    await stop();
    return heard;
  }

  void _onError(Object e) => state = RehearsalState(denied: e is MicrophoneDenied);

  void _onDone() {
    if (state.mode == RehearsalMode.repeats) state = const RehearsalState();
  }

  /// Closes the microphone; an echo still waiting for the user ends at once (not heard).
  Future<void> stop() async {
    final e = _echo;
    _echo = null;
    if (e != null && !e.isCompleted) e.complete(false);
    final had = _sub != null;
    // Not awaited: a cancel from inside the stream's own delivery may complete only later.
    _sub?.cancel().ignore();
    _sub = null;
    _follower = null;
    if (had) await _engine.stop();
    if (state.listening) state = const RehearsalState();
  }
}

final voiceRehearsalProvider = NotifierProvider.autoDispose<VoiceRehearsal, RehearsalState>(VoiceRehearsal.new);
