import 'quran_data.dart';

/// The four layers of the «صفحة واحدة» reader (spec §5.11): the printed page is the only Quran
/// surface; listening, memorising and reciting are drawn over it. Switching never pushes a route.
enum QuranMode {
  read,
  listen,
  memorise,
  recite;

  /// `?mode=` in `/quran/read/:page` (unknown or missing → [read]).
  static QuranMode parse(String? raw) => values.asNameMap()[raw] ?? read;
}

/// First page of each surah in the printed Madani mushaf (604 pages). Bundled so a redirect into
/// the reader never waits for the mushaf text to load; a test checks it against `quran.json` and
/// the printed layout.
const kSurahStartPage = <int>[
  1, 2, 50, 77, 106, 128, 151, 177, 187, 208, 221, 235, 249, 255, 262, 267, 282, 293, 305, //
  312, 322, 332, 342, 350, 359, 367, 377, 385, 396, 404, 411, 415, 418, 428, 434, 440, 446, 453,
  458, 467, 477, 483, 489, 496, 499, 502, 507, 511, 515, 518, 520, 523, 526, 528, 531, 534, 537,
  542, 545, 549, 551, 553, 554, 556, 558, 560, 562, 564, 566, 568, 570, 572, 574, 575, 577, 578,
  580, 582, 583, 585, 586, 587, 587, 589, 590, 591, 591, 592, 593, 594, 595, 595, 596, 596, 597,
  597, 598, 598, 599, 599, 600, 600, 601, 601, 601, 602, 602, 602, 603, 603, 603, 604, 604, 604,
];

/// Start page of [surah] (clamped to 1–114), synchronously.
int surahStartPage(int surah) => kSurahStartPage[surah.clamp(1, QuranData.surahCount) - 1];

/// A run of ayat inside one surah — what the reader's layers work on: what plays, what is hidden
/// for memorising, what a recitation is checked against, what a guided session covers.
class Passage {
  const Passage(this.surah, this.from, this.to) : assert(from <= to);

  final int surah;
  final int from;
  final int to;

  /// The ayat of [page] that belong to one surah: the run holding [at] when given, else the longest
  /// run on the page (ties → the first, in reading order). Never crosses the page.
  factory Passage.ofPage(QuranData q, int page, {AyahRef? at}) {
    final segments = q.page(page.clamp(1, QuranData.pageCount));
    PageSegment? pick;
    if (at != null) pick = segments.where((s) => s.surah.number == at.surah && s.ayat.any((a) => a.ref == at)).firstOrNull;
    pick ??= segments.reduce((a, b) => b.ayat.length > a.ayat.length ? b : a);
    return Passage(pick.surah.number, pick.ayat.first.ref.ayah, pick.ayat.last.ref.ayah);
  }

  /// A hifz portion (or today's new ayat), clamped to the surah.
  factory Passage.ofHifz(QuranData q, int surah, int from, int to) {
    final n = q.surah(surah.clamp(1, QuranData.surahCount)).ayahCount;
    final a = from.clamp(1, n);
    return Passage(surah.clamp(1, QuranData.surahCount), a, to.clamp(a, n));
  }

  /// Where a khatma portion of pages [fromPage]–[toPage] starts: from its first ayah to the end of
  /// that surah inside the portion (listening carries on into the next surah by itself).
  factory Passage.ofKhatma(QuranData q, int fromPage, int toPage) {
    final first = q.firstOfPage(fromPage.clamp(1, QuranData.pageCount));
    final endPage = toPage.clamp(fromPage, QuranData.pageCount);
    final last = endPage < QuranData.pageCount ? _before(q, q.firstOfPage(endPage + 1)) : const AyahRef(114, 6);
    final to = last.surah == first.surah ? last.ayah : q.surah(first.surah).ayahCount;
    return Passage(first.surah, first.ayah, to);
  }

  static AyahRef _before(QuranData q, AyahRef r) => r.ayah > 1 ? AyahRef(r.surah, r.ayah - 1) : AyahRef(r.surah - 1, q.surah(r.surah - 1).ayahCount);

  int get length => to - from + 1;
  AyahRef get first => AyahRef(surah, from);
  AyahRef get last => AyahRef(surah, to);

  /// Every ayah, in order.
  List<AyahRef> get range => [for (var a = from; a <= to; a++) AyahRef(surah, a)];

  bool contains(AyahRef r) => r.surah == surah && r.ayah >= from && r.ayah <= to;

  /// The printed pages the passage spans, in order.
  List<int> pages(QuranData q) => [for (var p = q.pageOf(first); p <= q.pageOf(last); p++) p];

  /// Text pairs for the recitation aligner.
  List<(AyahRef, String)> expected(QuranData q) => [for (final r in range) (r, q.text(r))];

  Map<String, dynamic> toJson() => {'s': surah, 'f': from, 't': to};

  static Passage? tryParse(Object? j) {
    if (j is! Map || j['s'] is! int || j['f'] is! int || j['t'] is! int) return null;
    final s = j['s'] as int, f = j['f'] as int, t = j['t'] as int;
    if (s < 1 || s > QuranData.surahCount || f < 1 || t < f) return null;
    return Passage(s, f, t);
  }

  @override
  bool operator ==(Object other) => other is Passage && other.surah == surah && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(surah, from, to);
  @override
  String toString() => '$surah:$from-$to';
}
