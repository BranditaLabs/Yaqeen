import 'quran_data.dart';

/// What a word slot on a printed line is.
enum MushafWordKind { word, end, other }

/// One word of the printed page: its glyph code in that page's QCF V2 font, and the ayah it belongs to.
class MushafWord {
  const MushafWord(this.code, this.ref, this.position, this.kind);
  final String code;
  final AyahRef ref;

  /// 1-based position within the ayah (the end marker is the last one).
  final int position;
  final MushafWordKind kind;

  bool get isEnd => kind == MushafWordKind.end;
}

/// One of the 15 printed line slots of a page.
sealed class MushafLine {
  const MushafLine();
}

/// The framed band with a surah's name.
class SurahBandLine extends MushafLine {
  const SurahBandLine(this.surah);
  final int surah;
}

/// «بسم الله الرحمن الرحيم» before a surah (not Al-Fatihah, where it is ayah 1, nor At-Tawbah).
class BasmalaLine extends MushafLine {
  const BasmalaLine();
}

/// An unused slot (only on the short opening pages 1–2).
class EmptyLine extends MushafLine {
  const EmptyLine();
}

/// A line of verse words, right to left in reading order.
class TextLine extends MushafLine {
  const TextLine(this.words, {this.centred = false});
  final List<MushafWord> words;

  /// Pages 1–2 set their short lines centred.
  final bool centred;
}

/// The printed Madani mushaf (King Fahd Complex, 15 lines, 604 pages), line by line, with the QCF V2
/// glyph code of every word (assets/quran/layout_v2.json, built by tools/quran/build_layout.py from the
/// Quran.com API). Text is drawn with the per-page KFGQPC font, so it is the print, glyph for glyph.
class MushafLayout {
  MushafLayout._(this.pages, this.starts, this.source);

  factory MushafLayout.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 1) throw const FormatException('layout format');
    final pages = <List<MushafLine>>[];
    for (final p in (j['pages'] as List).cast<List<dynamic>>()) {
      final lines = <MushafLine>[];
      for (final raw in p.cast<Map<String, dynamic>>()) {
        if (raw['s'] != null) {
          lines.add(SurahBandLine(raw['s'] as int));
        } else if (raw['b'] != null) {
          lines.add(const BasmalaLine());
        } else if (raw['w'] != null) {
          lines.add(
            TextLine(
              [
                for (final w in (raw['w'] as List).cast<List<dynamic>>())
                  MushafWord(
                    w[0] as String,
                    AyahRef(w[1] as int, w[2] as int),
                    w[3] as int,
                    MushafWordKind.values[(w[4] as int).clamp(0, 2)],
                  ),
              ],
              centred: raw['c'] == 1,
            ),
          );
        } else {
          lines.add(const EmptyLine());
        }
      }
      if (lines.length != linesPerPage) throw FormatException('page ${pages.length + 1}: ${lines.length} lines');
      pages.add(lines);
    }
    if (pages.length != QuranData.pageCount) throw FormatException('${pages.length} pages');
    return MushafLayout._(
      pages,
      [for (final r in (j['starts'] as List).cast<List<dynamic>>()) AyahRef(r[0] as int, r[1] as int)],
      (j['source'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  static const linesPerPage = 15;

  final List<List<MushafLine>> pages;

  /// The first ayah of every page in this print — the page boundaries the whole app uses.
  final List<AyahRef> starts;
  final Map<String, dynamic> source;

  List<MushafLine> page(int page) => pages[page - 1];

  /// The four words of ayah 1:1 (page 1 font): every Basmala line is drawn with these glyphs.
  late final List<MushafWord> basmalaWords = [
    for (final l in pages[0])
      if (l is TextLine)
        for (final w in l.words)
          if (w.ref == const AyahRef(1, 1) && !w.isEnd) w,
  ];

  /// Pages 1–2: a short page with its lines centred in the middle.
  static bool isOpening(int page) => page <= 2;

  /// Page fonts a page needs: its own, plus page 1's for the Basmala glyphs.
  List<int> fontsFor(int page) => [page, if (page != 1 && this.page(page).any((l) => l is BasmalaLine)) 1];
}
