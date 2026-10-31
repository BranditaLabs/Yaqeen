import '../../../core/text/arabic.dart';

/// One surah's metadata.
class Surah {
  const Surah({
    required this.number,
    required this.nameAr,
    required this.nameEn,
    required this.meccan,
    required this.ayahCount,
    required this.startPage,
  });
  final int number;
  final String nameAr;
  final String nameEn;
  final bool meccan;
  final int ayahCount;
  final int startPage;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;
}

/// A verse reference.
class AyahRef implements Comparable<AyahRef> {
  const AyahRef(this.surah, this.ayah);
  final int surah;
  final int ayah;

  @override
  int compareTo(AyahRef o) => surah != o.surah ? surah - o.surah : ayah - o.ayah;
  bool operator <(AyahRef o) => compareTo(o) < 0;
  bool operator <=(AyahRef o) => compareTo(o) <= 0;

  @override
  bool operator ==(Object other) => other is AyahRef && other.surah == surah && other.ayah == ayah;
  @override
  int get hashCode => surah * 1000 + ayah;
  @override
  String toString() => '$surah:$ayah';
}

/// `"18:10"` → AyahRef(18, 10); null when malformed or out of range.
AyahRef? parseAyahRef(String? raw) {
  final m = RegExp(r'^(\d{1,3}):(\d{1,3})$').firstMatch(raw ?? '');
  if (m == null) return null;
  final s = int.parse(m.group(1)!);
  final a = int.parse(m.group(2)!);
  return s >= 1 && s <= 114 && a >= 1 && a <= 286 ? AyahRef(s, a) : null;
}

/// One verse on a page.
class PageAyah {
  const PageAyah(this.ref, this.text);
  final AyahRef ref;
  final String text;
}

/// A run of verses from one surah on a page; [startsSurah] → draw the surah header (+ Basmala).
class PageSegment {
  const PageSegment({required this.surah, required this.ayat, required this.startsSurah});
  final Surah surah;
  final List<PageAyah> ayat;
  final bool startsSurah;
}

/// What a search returns (spec §5.10).
sealed class QuranHit {
  const QuranHit();
}

class SurahHit extends QuranHit {
  const SurahHit(this.surah);
  final Surah surah;
}

class AyahHit extends QuranHit {
  const AyahHit(this.surah, this.ref, this.page);
  final Surah surah;
  final AyahRef ref;
  final int page;
}

/// The bundled Madani mushaf (assets/quran/quran.json, built by tools/quran/build_quran.py).
/// Read-only, fully offline from first launch. Text is never altered.
///
/// [pageStarts] replaces the bundled (Tanzil) page boundaries with those of the printed page layout
/// (`MushafLayout.starts`, KFGQPC 1421 print) so the drawn pages, page numbers, bookmarks and khatma
/// all agree. 25 pages start one or two ayat apart between the two editions.
class QuranData {
  QuranData.fromJson(Map<String, dynamic> j, {List<AyahRef>? pageStarts})
      : surahs = [
          for (final (i, r) in (j['surahs'] as List).cast<List<dynamic>>().indexed)
            Surah(
              number: i + 1,
              nameAr: r[0] as String,
              nameEn: r[1] as String,
              meccan: r[2] == 'm',
              ayahCount: r[3] as int,
              startPage: r[4] as int,
            ),
        ],
        _pageStarts = pageStarts != null && pageStarts.length == pageCount ? pageStarts : _refs(j['pages']),
        _juzStarts = _refs(j['juz']),
        _quarterStarts = _refs(j['quarters']),
        sajdas = _refs(j['sajdas']).toSet(),
        _ayat = [for (final s in j['ayat'] as List) (s as List).cast<String>()] {
    _searchIndex = [for (final s in surahs) (s, ArabicText.normalize(s.nameAr), s.nameEn.toLowerCase().replaceAll(RegExp("[^a-z]"), ''))];
  }

  static List<AyahRef> _refs(Object? list) => [for (final r in (list as List).cast<List<dynamic>>()) AyahRef(r[0] as int, r[1] as int)];

  static const pageCount = 604;
  static const surahCount = 114;
  static const totalAyat = 6236;

  final List<Surah> surahs;
  final List<AyahRef> _pageStarts;
  final List<AyahRef> _juzStarts;
  final List<AyahRef> _quarterStarts;
  final Set<AyahRef> sajdas;
  final List<List<String>> _ayat;
  late final List<(Surah, String, String)> _searchIndex;

  Surah surah(int n) => surahs[n - 1];
  String text(AyahRef r) => _ayat[r.surah - 1][r.ayah - 1];

  /// Basmala as printed in this edition (the first verse of Al-Fatihah).
  String get basmala => _ayat[0][0];

  AyahRef next(AyahRef r) => r.ayah < surah(r.surah).ayahCount ? AyahRef(r.surah, r.ayah + 1) : AyahRef(r.surah + 1, 1);

  static int _lastStartAtOrBefore(List<AyahRef> starts, AyahRef r) {
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= r) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int pageOf(AyahRef r) => _lastStartAtOrBefore(_pageStarts, r) + 1;
  int juzOf(AyahRef r) => _lastStartAtOrBefore(_juzStarts, r) + 1;

  /// 1–240.
  int quarterOf(AyahRef r) => _lastStartAtOrBefore(_quarterStarts, r) + 1;

  /// 1–60.
  int hizbOf(AyahRef r) => (quarterOf(r) - 1) ~/ 4 + 1;

  late final Map<AyahRef, int> _quarterIndex = {for (final (i, r) in _quarterStarts.indexed) r: i + 1};

  /// The hizb quarter (1–240) that starts at [r], or null.
  int? quarterStartingAt(AyahRef r) => _quarterIndex[r];

  AyahRef firstOfPage(int page) => _pageStarts[page - 1];
  AyahRef firstOfJuz(int juz) => _juzStarts[juz - 1];
  AyahRef firstOfQuarter(int q) => _quarterStarts[q - 1];
  int juzStartPage(int juz) => pageOf(firstOfJuz(juz));

  /// All verses on [page], grouped by surah.
  List<PageSegment> page(int page) {
    final start = _pageStarts[page - 1];
    final end = page < pageCount ? _pageStarts[page] : null;
    final segments = <PageSegment>[];
    var r = start;
    var current = <PageAyah>[];
    var currentSurah = start.surah;
    var startsSurah = start.ayah == 1;
    while (end == null ? r.surah <= 114 : r < end) {
      if (r.surah != currentSurah) {
        segments.add(PageSegment(surah: surah(currentSurah), ayat: current, startsSurah: startsSurah));
        current = [];
        currentSurah = r.surah;
        startsSurah = true;
      }
      current.add(PageAyah(r, text(r)));
      if (r.surah == 114 && r.ayah == surah(114).ayahCount) break;
      r = next(r);
    }
    segments.add(PageSegment(surah: surah(currentSurah), ayat: current, startsSurah: startsSurah));
    return segments;
  }

  /// Surah name or number, `surah:ayah` (e.g. «18:10»), or a juz-agnostic name match (spec §5.10).
  List<QuranHit> search(String query) {
    final q = ArabicText.normalize(query).toLowerCase().replaceAll('سوره ', '').trim();
    if (q.isEmpty) return const [];
    final ref = RegExp(r'^(\d{1,3})\s*[:.،,/-]\s*(\d{1,3})$').firstMatch(q);
    if (ref != null) {
      final s = int.parse(ref.group(1)!);
      final a = int.parse(ref.group(2)!);
      if (s < 1 || s > 114 || a < 1 || a > surah(s).ayahCount) return const [];
      final r = AyahRef(s, a);
      return [AyahHit(surah(s), r, pageOf(r))];
    }
    final n = int.tryParse(q);
    if (n != null) return n >= 1 && n <= 114 ? [SurahHit(surah(n))] : const [];
    final latin = q.replaceAll(RegExp('[^a-z]'), '');
    final bare = ArabicText.withoutArticle(q);
    final starts = <QuranHit>[];
    final contains = <QuranHit>[];
    for (final (s, ar, en) in _searchIndex) {
      final arBare = ArabicText.withoutArticle(ar);
      if (ar.startsWith(q) || arBare.startsWith(bare) || (latin.isNotEmpty && en.contains(latin) && en.startsWith(latin.substring(0, 1)))) {
        starts.add(SurahHit(s));
      } else if (ar.contains(bare) || (latin.length > 2 && en.contains(latin))) {
        contains.add(SurahHit(s));
      }
    }
    return [...starts, ...contains];
  }
}
