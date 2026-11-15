import '../../../core/platform/recitation_engine.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import '../../recite/domain/recitation_follower.dart';
import 'recording_models.dart';

/// The on-device pre-check of a finished take (design doc §16.1 «hybrid»): the whole transcript the
/// phone's Quran recogniser heard, aligned to the chosen ayat with the same rules as
/// [RecitationAligner] (normalisation, dagger alef, word Levenshtein, one edit for 4+ letters,
/// ties prefer «not heard»). It gives instant feedback before the upload («تخطّيت كلمة في الآية ٣»)
/// and the word timings for private karaoke playback.
///
/// **Advisory only.** The server never trusts it: private recordings are never verified, shared ones
/// are re-verified by our own AI check; [score] and [words] travel with a shared upload as
/// diagnostics for a reviewer (contracts `clientScore` / `clientWords`).
class ClientCheck {
  const ClientCheck({required this.marks, required this.words, required this.expected, required this.heardCount});

  /// One mark per expected word, in order.
  final List<WordMark> marks;

  /// Karaoke timings of every expected word paired with a heard one (`ok` and «تنبيه»), contracts
  /// `RecordingWord` — the same map as the server's.
  final List<RecordingWord> words;
  final List<ExpectedWord> expected;

  /// Words heard after the opening (isti'adha / Basmala) was dropped.
  final int heardCount;

  /// Expected words heard as written ÷ expected words (contracts `RECITATION_MATCH` coverage).
  double get score => expected.isEmpty ? 0 : marks.where((m) => m == WordMark.ok).length / expected.length;

  /// Ayat (in order) with a word not heard or heard differently.
  List<AyahRef> get flaggedAyat {
    final out = <AyahRef>[];
    for (final (i, m) in marks.indexed) {
      final ref = expected[i].ayah;
      if (m != WordMark.ok && (out.isEmpty || out.last != ref)) out.add(ref);
    }
    return out;
  }

  /// The quiet verdict shown before upload (never «خطأ»).
  ClientVerdict get verdict {
    if (heardCount == 0) return ClientVerdict.unclear;
    if (score < RecitationMatch.rejectCoverage) return ClientVerdict.notMatching;
    if (score >= RecitationMatch.approveCoverage) return flaggedAyat.isEmpty ? ClientVerdict.clean : ClientVerdict.mostly;
    return ClientVerdict.mostly;
  }

  /// Aligns [heard] (with times in seconds from the start of the take) against [expected] ayat.
  static ClientCheck of(List<(AyahRef, String)> expected, List<RecognizedWord> heard) {
    final exp = ExpectedWord.of(expected);
    // A recogniser segment holding several words shares its time span between them (as the
    // server's port does); pause marks are not words.
    final all = <RecognizedWord>[
      for (final h in heard)
        ...() {
          final parts = RecitationAligner.words(h.text);
          if (parts.length <= 1) return [for (final p in parts) RecognizedWord(p, start: h.start, end: h.end)];
          final span = (h.end - h.start).clamp(0, double.infinity) / parts.length;
          return [for (final (k, p) in parts.indexed) RecognizedWord(p, start: h.start + k * span, end: h.start + (k + 1) * span)];
        }(),
    ];
    final drop = RecitationAligner.opening([for (final w in all) w.text], [for (final w in exp) w.text]).drop;
    final got = all.sublist(drop);
    final n = exp.length, m = got.length;
    final same = List.generate(n, (i) => List.generate(m, (j) => RecitationAligner.same(exp[i].text, got[j].text)));
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
        dp[i][j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
      }
    }
    final marks = List<WordMark>.filled(n, WordMark.skipped);
    final pair = List<int?>.filled(n, null);
    var i = n, j = m;
    while (i > 0 && j > 0) {
      final match = same[i - 1][j - 1];
      // The same tie-breaks as RecitationAligner.align (ties prefer «not heard yet»).
      if (match && dp[i][j] == dp[i - 1][j - 1]) {
        marks[i - 1] = WordMark.ok;
        pair[i - 1] = j - 1;
        i--;
        j--;
      } else if (dp[i][j] == dp[i - 1][j] + 1) {
        marks[i - 1] = WordMark.skipped;
        i--;
      } else if (dp[i][j] == dp[i - 1][j - 1] + 1) {
        marks[i - 1] = WordMark.warn;
        pair[i - 1] = j - 1;
        i--;
        j--;
      } else {
        j--;
      }
    }
    final words = <RecordingWord>[];
    for (var k = 0; k < n; k++) {
      final p = pair[k];
      if (p == null) continue;
      final w = got[p];
      final start = (w.start * 1000).round();
      final end = (w.end * 1000).round();
      words.add(RecordingWord(ayah: exp[k].ayah.ayah, index: exp[k].index, startMs: start < 0 ? 0 : start, endMs: end < 0 ? 0 : end));
    }
    return ClientCheck(marks: marks, words: words, expected: exp, heardCount: m);
  }
}

enum ClientVerdict {
  /// Every word heard as written.
  clean,

  /// Most of it; some ayat flagged («تخطّيت كلمة في الآية ٣»).
  mostly,

  /// Too little of the chosen ayat was heard.
  notMatching,

  /// Nothing was recognised (silence, noise).
  unclear,
}
