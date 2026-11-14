import '../../../core/platform/recitation_engine.dart';
import '../../quran/domain/quran_data.dart';
import 'recitation.dart';
import 'recitation_follower.dart';

/// How much of the next word the page shows to help (spec §5.12 «مساعدة»).
enum HintLevel { none, letter, word }

/// One «تسميع» attempt, device-only (spec §6.8): the follower's marks, the gentle help timing and
/// the summary. Time is the session's own clock (listening time only — pauses don't count), so the
/// help rules are tested with a fake clock.
///
/// Help: after [letterAfter] without progress on a word its first letter appears; after
/// [wordAfter] the whole word appears muted and counts as one «مساعدة» (it is still the word
/// expected — recited, it is marked as heard).
class ReciteProgress {
  ReciteProgress(List<(AyahRef, String)> expected)
      : ayat = [for (final (r, _) in expected) r],
        follower = RecitationFollower(ExpectedWord.of(expected));

  static const letterAfter = Duration(seconds: 4);
  static const wordAfter = Duration(seconds: 8);

  final List<AyahRef> ayat;
  final RecitationFollower follower;

  List<ExpectedWord> get words => follower.words;

  /// Words shown in full as help (each counted once).
  final Set<int> helped = {};

  /// The word showing its first letter, if any.
  int? letterHint;

  Duration _lastMove = Duration.zero;
  Duration _now = Duration.zero;

  /// Listening time so far.
  Duration get elapsed => _now;

  int get helps => helped.length;
  bool get complete => follower.done;
  bool get started => follower.cursor > 0 || follower.provisional.isNotEmpty || helped.isNotEmpty;

  /// The word the voice is on now (glow cursor); null when the passage is done.
  int? get current => follower.frontier < words.length ? follower.frontier : null;

  WordMark? markOf(int i) => follower.marks[i];

  /// Shown on the page: heard (frozen or tentative) or given as help.
  bool revealed(int i) => follower.marks[i] != null || follower.provisional.contains(i) || helped.contains(i);

  HintLevel hintOf(int i) => helped.contains(i) && follower.marks[i] == null
      ? HintLevel.word
      : (letterHint == i ? HintLevel.letter : HintLevel.none);

  /// Feeds what the engine heard at session time [at]. Returns whether anything visible changed.
  bool update(RecognitionUpdate u, Duration at) {
    _now = at > _now ? at : _now;
    final before = follower.frontier;
    final changed = follower.update([for (final w in u.committed) w.text], [for (final w in u.tentative) w.text]);
    if (follower.frontier != before) {
      _lastMove = _now;
      letterHint = null;
    }
    if (u.isFinal) follower.finish();
    return changed || u.isFinal;
  }

  /// The session clock moved to [at] while listening; escalates help on the current word.
  /// Returns whether a hint appeared.
  bool tick(Duration at) {
    _now = at;
    final i = current;
    if (i == null || helped.contains(i)) return false;
    final idle = _now - _lastMove;
    if (idle >= wordAfter) {
      helped.add(i);
      letterHint = null;
      return true;
    }
    if (idle >= letterAfter && letterHint != i) {
      letterHint = i;
      return true;
    }
    return false;
  }

  /// Listening resumes after a pause at session time [at]: the help clock restarts, and the engine's
  /// new session counts its words from zero.
  void resume(Duration at) {
    _now = at;
    _lastMove = at;
    follower.newSession();
  }

  /// Listening ended: words heard right at the passage's end are judged.
  void finish() => follower.finish();

  /// Word index range of each ayah.
  late final Map<AyahRef, (int, int)> spans = () {
    final out = <AyahRef, (int, int)>{};
    for (final (i, w) in words.indexed) {
      final s = out[w.ayah];
      out[w.ayah] = s == null ? (i, i) : (s.$1, i);
    }
    return out;
  }();

  late final Map<(AyahRef, int), int> _byPosition = {for (final (i, w) in words.indexed) (w.ayah, w.position): i};

  /// The passage word printed at [position] of ayah [r] (null: not part of this attempt).
  int? indexAt(AyahRef r, int position) => _byPosition[(r, position)];

  /// How much of ayah [r] the voice has passed (0…1) — a ring per ayah on the strip.
  double ayahProgress(AyahRef r) {
    final s = spans[r];
    if (s == null) return 0;
    final f = follower.frontier;
    if (f <= s.$1) return 0;
    if (f > s.$2) return 1;
    return (f - s.$1) / (s.$2 - s.$1 + 1);
  }

  /// Ayat finished (the voice is past their last word), in order from the start.
  int get recitedAyat {
    var n = 0;
    for (final r in ayat) {
      final s = spans[r];
      if (s == null || follower.cursor <= s.$2) break;
      n++;
    }
    return n;
  }

  List<AyahRef> get recitedRefs => ayat.take(recitedAyat).toList();

  /// «تنبيه» and skipped words the voice has passed.
  List<WordResult> get flagged => [
        for (var i = 0; i < follower.cursor && i < words.length; i++)
          if (follower.marks[i] case final WordMark m when m != WordMark.ok)
            WordResult(ayah: words[i].ayah, index: words[i].index, word: words[i].text, mark: m),
      ];

  List<AyahRef> get flaggedAyat => {for (final w in flagged) w.ayah}.toList();

  /// Per-ayah results for grading and the hifz state (unreached words count as not heard).
  List<AyahResult> get results => [
        for (final r in ayat)
          AyahResult(r, [
            if (spans[r] case final (int, int) s)
              for (var i = s.$1; i <= s.$2; i++)
                WordResult(ayah: r, index: words[i].index, word: words[i].text, mark: follower.marks[i] ?? WordMark.skipped),
          ]),
      ];

  /// «تنبيه» marks for the page: 1-based word positions per ayah.
  Map<AyahRef, Set<int>> get marks {
    final out = <AyahRef, Set<int>>{};
    for (final w in flagged) {
      if (w.mark == WordMark.warn) (out[w.ayah] ??= <int>{}).add(w.index + 1);
    }
    return out;
  }
}
