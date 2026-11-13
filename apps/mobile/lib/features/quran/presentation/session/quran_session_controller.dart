import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/passage.dart';
import '../../domain/quran_data.dart';
import '../mushaf_page.dart' show MemoriseMode;

/// What the reader draws over the printed page (spec §5.11 «صفحة واحدة»): the active layer, the
/// passage it works on, memorise reveals, the recitation's «تنبيه» marks. Device-only and never
/// sent anywhere; switching layers never pushes a route.
@immutable
class ReaderLayers {
  const ReaderLayers({
    this.mode = QuranMode.read,
    this.passage,
    this.memorise = MemoriseMode.ayat,
    this.revealed = const {},
    this.marks = const {},
    this.repeats = 0,
  });

  final QuranMode mode;

  /// The passage chosen for a layer («احفظ من هنا … إلى هنا», a session); null → the page's own.
  final Passage? passage;

  /// How the memorise layer hides: whole ayat or every other word.
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;

  /// Recitation «تنبيه» marks: word positions per ayah (raw results never leave the device).
  final Map<AyahRef, Set<int>> marks;

  /// «كرّرت» presses for the passage being memorised.
  final int repeats;

  /// What the page hides right now.
  MemoriseMode get hiding => mode == QuranMode.memorise ? memorise : MemoriseMode.off;

  ReaderLayers copyWith({
    QuranMode? mode,
    Passage? Function()? passage,
    MemoriseMode? memorise,
    Set<AyahRef>? revealed,
    Map<AyahRef, Set<int>>? marks,
    int? repeats,
  }) =>
      ReaderLayers(
        mode: mode ?? this.mode,
        passage: passage == null ? this.passage : passage(),
        memorise: memorise ?? this.memorise,
        revealed: revealed ?? this.revealed,
        marks: marks ?? this.marks,
        repeats: repeats ?? this.repeats,
      );
}

/// The reader's layers. One reader is open at a time; [init] resets them when one opens.
class QuranSessionController extends Notifier<ReaderLayers> {
  @override
  ReaderLayers build() => const ReaderLayers();

  /// Opens the reader on [mode] (and [passage]) from the route.
  void init({QuranMode mode = QuranMode.read, Passage? passage}) => state = ReaderLayers(mode: mode, passage: passage);

  void setMode(QuranMode mode) {
    if (mode == state.mode) return;
    // Reveals belong to one memorising pass; the recitation's marks stay until the passage changes.
    state = state.copyWith(mode: mode, revealed: mode == QuranMode.memorise ? state.revealed : const {});
  }

  void setPassage(Passage? p) {
    if (p == state.passage) return;
    state = state.copyWith(passage: () => p, revealed: const {}, marks: const {}, repeats: 0);
  }

  void setMemorise(MemoriseMode m) => state = state.copyWith(memorise: m == MemoriseMode.off ? MemoriseMode.ayat : m, revealed: const {});

  void toggleReveal(AyahRef r) {
    final next = {...state.revealed};
    if (!next.remove(r)) next.add(r);
    state = state.copyWith(revealed: next);
  }

  void revealAll(Iterable<AyahRef> refs) => state = state.copyWith(revealed: {...state.revealed, ...refs});
  void hideAll() => state = state.copyWith(revealed: const {});

  void countRepeat() => state = state.copyWith(repeats: state.repeats + 1);
  void resetRepeats() => state = state.copyWith(repeats: 0);
  void setRepeats(int n) => state = state.copyWith(repeats: n < 0 ? 0 : n);

  void setMarks(Map<AyahRef, Set<int>> marks) => state = state.copyWith(marks: marks);

  /// The page turned: page-scoped reveals go (a chosen passage keeps its own).
  void pageChanged() {
    if (state.passage == null && state.revealed.isNotEmpty) state = state.copyWith(revealed: const {});
  }
}

final quranSessionControllerProvider = NotifierProvider<QuranSessionController, ReaderLayers>(QuranSessionController.new);
