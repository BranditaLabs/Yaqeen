import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import 'recording_models.dart';

/// The verse swipe picker's pure logic (APP_SPEC §5.24 «تلاواتي»): a range inside one surah, chosen
/// by dragging from the first ayah to the last, adjusted by its two handles, and a live estimate of
/// how long it takes to recite.

/// A calm, everyday recitation pace: **≈ 2.2 words per second** (measured on murattal recitations
/// of short surahs by ordinary readers — slower than a professional hadr, faster than a teaching
/// tartil). Only an estimate to warn before the 30-second limit; the recorder stops at 30 s anyway.
const kRecitationWordsPerSecond = 2.2;

/// Above this share of the limit the estimate is shown as «قريب من 30 ثانية».
const kNearLimitShare = 0.8;

/// A range estimated past this share of the limit is clearly too long: it cannot be recorded.
const kBlockedShare = 1.2;

/// How a range sits against the 30-second limit.
enum RangeFit {
  /// Comfortably inside.
  ok,

  /// 80–100 % of the limit: a gentle heads-up.
  near,

  /// Over 30 s but maybe recitable at a quicker pace: a warning, still allowed.
  over,

  /// Clearly over (> 120 %): blocked until the range is shortened.
  blocked;

  bool get canRecord => this != blocked;
}

/// Words of an ayah as the recogniser and the karaoke count them ([RecitationAligner.words]).
int wordCount(String ayahText) => RecitationAligner.words(ayahText).length;

/// The estimated recitation time of [words] words.
Duration estimateFor(int words) => Duration(milliseconds: (words / kRecitationWordsPerSecond * 1000).round());

RangeFit fitOf(Duration estimate) {
  final share = estimate.inMilliseconds / kRecordingMaxMs;
  if (share > kBlockedShare) return RangeFit.blocked;
  if (share > 1) return RangeFit.over;
  if (share >= kNearLimitShare) return RangeFit.near;
  return RangeFit.ok;
}

/// A chosen range of ayat in one surah, and what it would take to recite it.
class VerseSelection {
  VerseSelection._(this.surah, this.anchor, this.edge, this._counts);

  /// A selection of the single ayah [ref].
  factory VerseSelection.single(QuranData q, AyahRef ref) =>
      VerseSelection._(ref.surah, ref.ayah, ref.ayah, [for (var a = 1; a <= q.surah(ref.surah).ayahCount; a++) wordCount(q.text(AyahRef(ref.surah, a)))]);

  /// A selection covering [p] (clamped to its surah).
  factory VerseSelection.ofPassage(QuranData q, Passage p) {
    final s = VerseSelection.single(q, AyahRef(p.surah, p.from));
    return s.dragTo(AyahRef(p.surah, p.to));
  }

  final int surah;

  /// Where the drag started (stays put while dragging).
  final int anchor;

  /// Where the finger is now.
  final int edge;

  /// Words per ayah of the surah (index 0 = ayah 1).
  final List<int> _counts;

  int get ayahCount => _counts.length;
  int get from => anchor <= edge ? anchor : edge;
  int get to => anchor <= edge ? edge : anchor;
  int get length => to - from + 1;
  Passage get passage => Passage(surah, from, to);
  bool contains(AyahRef r) => r.surah == surah && r.ayah >= from && r.ayah <= to;

  int get words {
    var n = 0;
    for (var a = from; a <= to; a++) {
      n += _counts[a - 1];
    }
    return n;
  }

  Duration get estimate => estimateFor(words);
  RangeFit get fit => fitOf(estimate);

  /// The finger moved over [ref]: the range now spans the anchor to it. Another surah is ignored
  /// (a recording is a range inside one surah).
  VerseSelection dragTo(AyahRef ref) {
    if (ref.surah != surah) return this;
    final a = ref.ayah.clamp(1, ayahCount);
    return a == edge ? this : VerseSelection._(surah, anchor, a, _counts);
  }

  /// The start handle moved by [delta] ayat (never past the end, never before ayah 1).
  VerseSelection moveStart(int delta) {
    final f = (from + delta).clamp(1, to);
    return VerseSelection._(surah, f, to, _counts);
  }

  /// The end handle moved by [delta] ayat (never before the start, never past the surah).
  VerseSelection moveEnd(int delta) {
    final t = (to + delta).clamp(from, ayahCount);
    return VerseSelection._(surah, from, t, _counts);
  }

  /// The longest range from [from] that still fits the limit (≥ the first ayah alone).
  VerseSelection trimmedToFit() {
    var t = to;
    while (t > from && fitOf(estimateFor(_sum(from, t))).index >= RangeFit.over.index) {
      t--;
    }
    return VerseSelection._(surah, from, t, _counts);
  }

  /// Blocked even when trimmed: the first ayah alone is estimated past the limit (2:282 ≈ 58 s), so
  /// «اقتصر على ما يتّسع» could change nothing — the panel says this ayah is too long instead.
  bool get unrecordable => fit == RangeFit.blocked && fitOf(estimateFor(_counts[from - 1])) == RangeFit.blocked;

  int _sum(int f, int t) {
    var n = 0;
    for (var a = f; a <= t; a++) {
      n += _counts[a - 1];
    }
    return n;
  }

  @override
  bool operator ==(Object other) => other is VerseSelection && other.surah == surah && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(surah, from, to);
  @override
  String toString() => 'VerseSelection($surah:$from-$to)';
}
