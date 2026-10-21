import '../../../core/text/arabic.dart';
import '../../quran/domain/quran_data.dart';

/// `ok` matched · `warn` a different word was heard («تنبيه») · `skipped` not heard.
/// The app never claims a tajweed judgment or says «خطأ» (spec §5.12).
enum WordMark { ok, warn, skipped }

class WordResult {
  const WordResult({required this.ayah, required this.index, required this.word, required this.mark});
  final AyahRef ayah;
  final int index;

  /// The expected word as written in the mushaf (with tashkeel) — shown underlined on `warn`.
  final String word;
  final WordMark mark;
}

class AyahResult {
  const AyahResult(this.ayah, this.words);
  final AyahRef ayah;
  final List<WordResult> words;
  bool get ok => words.every((w) => w.mark == WordMark.ok);
  Iterable<WordResult> get flagged => words.where((w) => w.mark != WordMark.ok);
}

/// Word alignment (spec §6.8): normalise both sides (strip tashkeel), Levenshtein over words,
/// tolerant of one-letter recogniser slips inside a word.
abstract final class RecitationAligner {
  static List<String> words(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_isMark(w)).toList();

  // Ayah-end ornaments and pause/sajda signs are not words.
  static bool _isMark(String w) => RegExp(r'^[ۖ-ۭ۝۞٠-٩﴾﴿0-9]+$').hasMatch(w);

  // Dagger alef (ٰ) is read as a full alef — recognisers write «العالمين» for «ٱلْعَٰلَمِينَ».
  static String _norm(String w) => ArabicText.normalize(w.replaceAll('\u0670', 'ا')).replaceAll(RegExp(r'[^ء-ي]'), '');

  /// Same word for matching: equal after normalisation, or one edit apart for words of 4+ letters.
  static bool same(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (x == y) return true;
    if (x.length < 4 || y.length < 4) return false;
    return _editDistance(x, y) <= 1;
  }

  /// Aligns what was heard against [expected] ayat (in order) and marks every expected word.
  static List<AyahResult> align(List<(AyahRef, String)> expected, String heard) {
    final exp = <(AyahRef, int, String)>[
      for (final (ref, text) in expected)
        for (final (i, w) in words(text).indexed) (ref, i, w),
    ];
    final got = words(heard);
    final n = exp.length, m = got.length;
    // dp[i][j] = cost of aligning exp[0..i) with got[0..j)
    final dp = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final sub = dp[i - 1][j - 1] + (same(exp[i - 1].$3, got[j - 1]) ? 0 : 1);
        final del = dp[i - 1][j] + 1; // expected word not heard
        final ins = dp[i][j - 1] + 1; // extra word heard (repetition, isti'adha…)
        dp[i][j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
      }
    }
    final marks = List<WordMark>.filled(n, WordMark.skipped);
    var i = n, j = m;
    while (i > 0 && j > 0) {
      final match = same(exp[i - 1].$3, got[j - 1]);
      // Ties prefer «not heard yet» over «heard differently», so stopping early never shows a warning.
      if (match && dp[i][j] == dp[i - 1][j - 1]) {
        marks[i - 1] = WordMark.ok;
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
    final out = <AyahResult>[];
    for (final (ref, _) in expected) {
      out.add(
        AyahResult(ref, [
          for (var k = 0; k < n; k++)
            if (exp[k].$1 == ref) WordResult(ayah: ref, index: exp[k].$2, word: exp[k].$3, mark: marks[k]),
        ]),
      );
    }
    return out;
  }

  /// Ayat recited so far: the prefix of [expected] whose last word has been heard (progressive reveal).
  static int recitedCount(List<AyahResult> results) {
    var count = 0;
    for (final r in results) {
      if (r.words.isEmpty || r.words.last.mark == WordMark.skipped) break;
      count++;
    }
    return count;
  }

  static int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final c = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
