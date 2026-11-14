import '../../quran/domain/quran_data.dart';
import 'recitation.dart';

/// One word of the passage being recited, in order.
class ExpectedWord {
  const ExpectedWord(this.ayah, this.index, this.text);
  final AyahRef ayah;

  /// 0-based within the ayah ([RecitationAligner.words]); the printed page's word position is
  /// `index + 1`.
  final int index;
  final String text;
  int get position => index + 1;

  static List<ExpectedWord> of(List<(AyahRef, String)> expected) => [
        for (final (ref, text) in expected)
          for (final (i, w) in RecitationAligner.words(text).indexed) ExpectedWord(ref, i, w),
      ];
}

/// Incremental alignment with a moving cursor (spec §6.8) — what lets the page follow a voice.
///
/// Committed words (stable, from the engine) are aligned only against a window after the cursor,
/// and marks are frozen up to the last word that *matched*: words heard after it wait for the next
/// update, so a word being said is never judged half-way, and extra words (a repetition, a phrase
/// said again to correct it) simply fall away. Between two matches, an expected word heard as
/// something else is `warn` («تنبيه»), one not heard at all is `skipped` once the voice is past it.
/// Tentative words are aligned the same way but only *reveal* (provisional `ok`), never judge.
/// [RecitationAligner.align] remains the whole-transcript alignment (grading, restored attempts).
class RecitationFollower {
  RecitationFollower(this.words) : marks = List<WordMark?>.filled(words.length, null);

  /// The engine started a new listening session (resume after a pause): its committed words count
  /// from zero again; what is already judged stays.
  void newSession() {
    _consumed = 0;
    _pending = const [];
    _held = const [];
    _skip = 0;
    _openingChecked = cursor > 0;
    provisional = const {};
  }

  /// Starts judging after [count] words already committed in the engine's session (the next
  /// repetition of a passage while the microphone stays open).
  void startAfter(int count) => _consumed = count;

  final List<ExpectedWord> words;

  /// Frozen marks (null: not reached yet).
  final List<WordMark?> marks;

  /// Words revealed by tentative recognition, ahead of [cursor].
  Set<int> provisional = const {};

  /// The next word not decided yet (== words.length when the passage is done).
  int cursor = 0;

  int _consumed = 0;
  List<String> _pending = const [];
  List<String> _held = const [];
  int _skip = 0;
  bool _openingChecked = false;

  bool get done => cursor >= words.length;

  /// Where the voice is now: past the provisional reveals too.
  int get frontier {
    var f = cursor;
    while (provisional.contains(f)) {
      f++;
    }
    return f;
  }

  /// Too many committed words without a single match: the oldest are dropped as extra words.
  static const maxPending = 10;

  /// Feeds the engine's words: [committed] only ever grows (a restart resets via a new follower);
  /// [tentative] is replaced each time. Returns whether any mark, the cursor or a reveal changed.
  bool update(List<String> committed, List<String> tentative) {
    final beforeCursor = cursor;
    final beforeProvisional = provisional;
    if (committed.length > _consumed) _held = [..._held, ...committed.sublist(_consumed)];
    _consumed = committed.length;
    if (_skip > 0 && _held.isNotEmpty) {
      final d = _skip < _held.length ? _skip : _held.length;
      _held = _held.sublist(d);
      _skip -= d;
    }
    if (!_openingChecked) {
      // The isti'adha / Basmala before the passage: only at the very start, and judged once said.
      final head = [..._held, ...tentative];
      final o = RecitationAligner.opening(head, [for (final w in words.take(8)) w.text]);
      if (o.open) {
        provisional = const {};
        return !_sameSet(provisional, beforeProvisional);
      }
      final fromHeld = o.drop < _held.length ? o.drop : _held.length;
      _held = _held.sublist(fromHeld);
      _skip = o.drop - fromHeld; // the rest of the opening is still tentative
      tentative = tentative.length > _skip ? tentative.sublist(_skip) : const [];
      if (head.length > o.drop) _openingChecked = true;
    }
    final fresh = _skip > 0 ? const <String>[] : _held;
    if (_skip == 0) _held = const [];
    if (fresh.isNotEmpty) {
      _pending = [..._pending, ...fresh];
      _advance(_pending, freeze: true);
    }
    provisional = const {};
    if (tentative.isNotEmpty && !done) {
      final probe = _align([..._pending, ...tentative]);
      if (probe != null) {
        provisional = {for (final (i, m) in probe.$1.indexed) if (m == WordMark.ok) cursor + i};
      }
    }
    return cursor != beforeCursor || !_sameSet(provisional, beforeProvisional);
  }

  static bool _sameSet(Set<int> a, Set<int> b) => a.length == b.length && a.containsAll(b);

  void _advance(List<String> heard, {required bool freeze}) {
    final r = _align(heard);
    if (r == null) {
      if (_pending.length > maxPending) _pending = _pending.sublist(_pending.length - maxPending);
      return;
    }
    final (segMarks, used) = r;
    for (final (i, m) in segMarks.indexed) {
      marks[cursor + i] = m;
    }
    cursor += segMarks.length;
    _pending = _pending.sublist(used);
    if (_pending.isNotEmpty && !done) _advance(_pending, freeze: freeze);
  }

  /// Semi-global alignment of [heard] against the words after the cursor. Returns the marks up to
  /// and including the last matched expected word, and how many heard words that consumed; null
  /// when nothing matched.
  (List<WordMark>, int)? _align(List<String> heard) {
    if (heard.isEmpty || done) return null;
    final w = (heard.length * 2 + 8).clamp(1, words.length - cursor);
    final exp = [for (var i = 0; i < w; i++) words[cursor + i].text];
    final n = exp.length, m = heard.length;
    final same = List.generate(n, (i) => List.generate(m, (j) => RecitationAligner.same(exp[i], heard[j])));
    // dp[i][j]: cost of exp[0..i) against heard[0..j).
    final dp = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final sub = dp[i - 1][j - 1] + (same[i - 1][j - 1] ? 0 : 1);
        final del = dp[i - 1][j] + 1;
        final ins = dp[i][j - 1] + 1;
        var best = sub;
        if (del < best) best = del;
        if (ins < best) best = ins;
        dp[i][j] = best;
      }
    }
    // Trace back from every end, keep the cheapest alignment that ends in a match (latest match on ties).
    (List<WordMark>, int, int)? best; // marks, used, cost
    for (var end = n; end >= 1; end--) {
      final path = _trace(dp, same, end, m);
      if (path == null) continue;
      final (pm, used) = path;
      final cost = dp[end][m];
      if (best == null || cost < best.$3) best = (pm, used, cost);
    }
    if (best == null) return null;
    return (best.$1, best.$2);
  }

  /// The alignment ending at exp[end-1] / heard[m-1]; keeps it up to its last match. Null without one.
  static (List<WordMark>, int)? _trace(List<List<int>> dp, List<List<bool>> same, int end, int m) {
    var i = end, j = m;
    final marks = List<WordMark?>.filled(end, null);
    int? lastMatchI;
    int? lastMatchJ;
    while (i > 0 && j > 0) {
      final match = same[i - 1][j - 1];
      if (match && dp[i][j] == dp[i - 1][j - 1]) {
        marks[i - 1] = WordMark.ok;
        lastMatchI ??= i;
        lastMatchJ ??= j;
        i--;
        j--;
      } else if (dp[i][j] == dp[i - 1][j] + 1) {
        marks[i - 1] = WordMark.skipped;
        i--;
      } else if (dp[i][j] == dp[i - 1][j - 1] + 1) {
        marks[i - 1] = WordMark.warn;
        i--;
        j--;
      } else {
        j--;
      }
    }
    while (i > 0) {
      marks[i - 1] = WordMark.skipped;
      i--;
    }
    if (lastMatchI == null) return null;
    return ([for (var k = 0; k < lastMatchI; k++) marks[k]!], lastMatchJ!);
  }

  /// The end of listening: words heard after the last match are judged as they stand (a different
  /// word at the passage's end is a «تنبيه»); words never reached stay unmarked.
  void finish() {
    provisional = const {};
    if (_held.isNotEmpty) {
      _pending = [..._pending, ..._held];
      _held = const [];
    }
    // Only right at the passage's end (a stop mid-way judges nothing it did not reach).
    if (_pending.isEmpty || done || words.length - cursor > _pending.length) return;
    final w = _pending.length.clamp(1, words.length - cursor);
    for (var i = 0; i < w; i++) {
      marks[cursor + i] = WordMark.warn;
    }
    cursor += w;
    _pending = const [];
  }
}
