import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/recitation_engine.dart';
import '../../listen/presentation/listen_controller.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../domain/recitation.dart';

/// The «تسميع» layer's state: whether a model is on the device, the microphone, what was heard
/// aligned against the passage. Recognition runs on the device; audio and raw results never leave
/// it (spec §5.12, §6.8).
@immutable
class ReciteState {
  const ReciteState({this.available, this.listening = false, this.heard = '', this.passage, this.results = const [], this.showAyat = true});

  /// null while the device is still being asked (the mic is a shimmering disc then).
  final bool? available;
  final bool listening;
  final String heard;
  final Passage? passage;
  final List<AyahResult> results;

  /// «إظهار الآيات»: off hides the passage until each ayah is recited (a memorisation test).
  final bool showAyat;

  bool get started => heard.isNotEmpty;
  int get recited => RecitationAligner.recitedCount(results);
  double get progress => results.isEmpty ? 0 : recited / results.length;

  /// Ayat recited so far.
  List<AyahRef> get recitedAyat => [for (final r in results.take(recited)) r.ayah];

  /// «تنبيه» words among what was recited.
  List<WordResult> get notes => [for (final r in results.take(recited)) ...r.words.where((w) => w.mark == WordMark.warn)];

  /// The marks the page draws: 1-based word positions per ayah.
  Map<AyahRef, Set<int>> get marks {
    final out = <AyahRef, Set<int>>{};
    for (final w in notes) {
      (out[w.ayah] ??= <int>{}).add(w.index + 1);
    }
    return out;
  }

  ReciteState copyWith({
    bool? Function()? available,
    bool? listening,
    String? heard,
    Passage? Function()? passage,
    List<AyahResult>? results,
    bool? showAyat,
  }) =>
      ReciteState(
        available: available == null ? this.available : available(),
        listening: listening ?? this.listening,
        heard: heard ?? this.heard,
        passage: passage == null ? this.passage : passage(),
        results: results ?? this.results,
        showAyat: showAyat ?? this.showAyat,
      );
}

/// The microphone and the recognition engine for the reader's «تسميع» layer (moved out of the old
/// recitation screen). Lives while the reader shows it; stopping the reader stops the microphone.
class ReciteController extends AutoDisposeNotifier<ReciteState> {
  StreamSubscription<String>? _sub;
  late RecitationEngine _engine;

  /// Shown once before the first recitation («نستمع لتلاوتك على جهازك فقط»).
  static const rationaleKey = 'recite.rationaleSeen';

  @override
  ReciteState build() {
    _engine = ref.watch(recitationEngineProvider);
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      _sub?.cancel();
      _engine.stop().ignore();
    });
    _engine.isAvailable().then((v) {
      if (!disposed) state = state.copyWith(available: () => v);
    }).ignore();
    return const ReciteState();
  }

  Future<bool> rationaleSeen() async => await ref.read(kvStoreProvider).read(rationaleKey) != null;
  Future<void> markRationaleSeen() => ref.read(kvStoreProvider).write(rationaleKey, '1');

  /// Sets the passage being recited (a new one starts clean).
  void prepare(Passage p, QuranData q) {
    if (state.passage == p && state.results.isNotEmpty) return;
    state = state.copyWith(passage: () => p, heard: '', results: RecitationAligner.align(p.expected(q), ''));
  }

  void setShowAyat(bool v) => state = state.copyWith(showAyat: v);

  /// Starts listening to [p]; recitation playing is paused first (the reader's own voice only).
  Future<void> start(Passage p, QuranData q) async {
    await ref.read(listenControllerProvider.notifier).pause();
    final expected = p.expected(q);
    await _sub?.cancel();
    state = state.copyWith(passage: () => p, listening: true, heard: '', results: RecitationAligner.align(expected, ''));
    _sub = _engine.start().listen(
      (transcript) => state = state.copyWith(heard: transcript, results: RecitationAligner.align(expected, transcript)),
      onError: (_) => state = state.copyWith(listening: false),
      onDone: () => state = state.copyWith(listening: false),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (state.listening) await _engine.stop();
    state = state.copyWith(listening: false);
  }

  /// Back to an untouched passage (a new attempt).
  Future<void> reset(QuranData q) async {
    await stop();
    final p = state.passage;
    state = state.copyWith(heard: '', results: p == null ? const [] : RecitationAligner.align(p.expected(q), ''));
  }

  /// A guided session restoring the last attempt (raw results stay on the device).
  void restore(Passage p, QuranData q, String heard) =>
      state = state.copyWith(passage: () => p, heard: heard, results: RecitationAligner.align(p.expected(q), heard));
}

final reciteControllerProvider = NotifierProvider.autoDispose<ReciteController, ReciteState>(ReciteController.new);
