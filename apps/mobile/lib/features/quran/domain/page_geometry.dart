import 'dart:math' as math;
import 'dart:ui';

import 'mushaf_layout.dart';
import 'quran_data.dart';

/// Where every word of a printed page sits in a box of a given size — the pure math behind the
/// Madani renderer (fit, justification, hit-testing), unit-tested without fonts.
///
/// Fit: the 15 line slots always share the box height (no scroll, ever). The glyph size is the
/// largest that lets the widest line fill the width *and* keeps a line's ink inside its slot; on a
/// very tall screen the line pitch is capped and the block centred, like the printed page.
/// Justification: a line at least [fullLine] of the widest is stretched to the block width by
/// widening its word gaps (glyphs carry their own spacing, so this is a few pixels); shorter lines
/// (a surah's last line, pages 1–2) are centred.
class PageGeometry {
  PageGeometry._(this.size, this.fontSize, this.pitch, this.block, this.lines);

  /// [unitWidth] is a word's advance width at font size 1 (measured once from the page font).
  factory PageGeometry.compute({
    required List<MushafLine> lines,
    required Size size,
    required double Function(MushafWord w) unitWidth,
    bool opening = false,
  }) {
    assert(lines.length == MushafLayout.linesPerPage);
    final natural = <int, double>{};
    var widest = 0.0;
    for (final (i, l) in lines.indexed) {
      if (l is! TextLine) continue;
      final w = l.words.fold<double>(0, (s, x) => s + unitWidth(x));
      natural[i] = w;
      widest = math.max(widest, w);
    }
    if (widest <= 0) widest = referenceLineUnits;
    // The opening pages keep the glyph size of a full page, set narrower and centred (as printed).
    final fitWidth = opening ? math.min(size.width / referenceLineUnits, size.width * openingWidth / widest) : size.width / widest;
    final slots = opening ? lines.where((l) => l is! EmptyLine).length : MushafLayout.linesPerPage;
    final fitHeight = size.height / MushafLayout.linesPerPage / minPitch;
    final font = math.max(1.0, math.min(fitWidth, fitHeight));
    final pitch = math.min(size.height / MushafLayout.linesPerPage, font * maxPitch);
    final blockWidth = math.min(size.width, widest * font);
    final blockHeight = pitch * slots;
    final block = Rect.fromLTWH((size.width - blockWidth) / 2, (size.height - blockHeight) / 2, blockWidth, blockHeight);

    final out = <LineBox>[];
    var row = 0;
    for (final (i, l) in lines.indexed) {
      if (opening && l is EmptyLine) continue;
      final rect = Rect.fromLTWH(block.left, block.top + row * pitch, block.width, pitch);
      row++;
      if (l is! TextLine) {
        out.add(LineBox(i, l, rect, const []));
        continue;
      }
      final widths = [for (final w in l.words) unitWidth(w) * font];
      final total = widths.fold<double>(0, (s, x) => s + x);
      final justify = !l.centred && !opening && natural[i]! >= widest * fullLine && l.words.length > 1;
      final gap = justify ? math.max(0.0, (rect.width - total) / (l.words.length - 1)) : 0.0;
      final used = justify ? rect.width : total;
      // Right to left: the first word is at the right edge of the line.
      var right = rect.left + (rect.width + used) / 2;
      final boxes = <WordBox>[];
      for (final (k, w) in l.words.indexed) {
        boxes.add(WordBox(w, Rect.fromLTRB(right - widths[k], rect.top, right, rect.bottom), gap));
        right -= widths[k] + gap;
      }
      out.add(LineBox(i, l, rect, boxes));
    }
    return PageGeometry._(size, font, pitch, block, out);
  }

  /// A full printed line is ≈ 15.5 font sizes wide in the QCF V2 fonts (measured on all pages).
  static const referenceLineUnits = 15.5;

  /// Line pitch bounds in font sizes: below [minPitch] the marks of two lines would touch; above
  /// [maxPitch] the page loosens into a list of lines, so the block is centred instead.
  static const minPitch = 1.72;
  static const maxPitch = 2.25;

  /// Lines at least this share of the widest are justified to the block edge.
  static const fullLine = 0.8;

  /// The opening pages' text width (share of the page width).
  static const openingWidth = 0.78;

  final Size size;
  final double fontSize;
  final double pitch;

  /// Where the lines are drawn (centred in [size]).
  final Rect block;
  final List<LineBox> lines;

  /// The word under [p] (gaps belong to the nearer word), or null outside the text.
  MushafWord? wordAt(Offset p) {
    for (final l in lines) {
      if (p.dy < l.rect.top || p.dy >= l.rect.bottom || l.words.isEmpty) continue;
      WordBox? best;
      var bestDist = double.infinity;
      for (final w in l.words) {
        final r = w.rect.inflate(w.gap / 2 + 0.5);
        if (p.dx >= r.left && p.dx <= r.right) {
          final d = (p.dx - w.rect.center.dx).abs();
          if (d < bestDist) {
            bestDist = d;
            best = w;
          }
        }
      }
      return best?.word;
    }
    return null;
  }

  AyahRef? ayahAt(Offset p) => wordAt(p)?.ref;

  /// One rectangle per line the ayah touches (its words merged with the gaps between them).
  List<Rect> rectsOf(AyahRef ref) => [
        for (final l in lines)
          if (l.words.any((w) => w.word.ref == ref))
            l.words.where((w) => w.word.ref == ref).map((w) => w.rect).reduce((a, b) => a.expandToInclude(b)),
      ];

  /// The ayah's end marker box (for the note badge), if it is on this page.
  Rect? endMarkerOf(AyahRef ref) {
    for (final l in lines) {
      for (final w in l.words) {
        if (w.word.ref == ref && w.word.isEnd) return w.rect;
      }
    }
    return null;
  }

  /// The line box an ayah starts on (margin marks for juz/hizb/sajdah).
  LineBox? lineOf(AyahRef ref, {bool last = false}) {
    final hits = lines.where((l) => l.words.any((w) => w.word.ref == ref));
    if (hits.isEmpty) return null;
    return last ? hits.last : hits.first;
  }

  /// Whether every drawn line fits inside the box (the invariant the tests check).
  bool get fits =>
      lines.every((l) => l.rect.top >= -0.01 && l.rect.bottom <= size.height + 0.01) &&
      lines.every((l) => l.words.every((w) => w.rect.left >= -0.5 && w.rect.right <= size.width + 0.5));
}

class LineBox {
  const LineBox(this.slot, this.line, this.rect, this.words);

  /// 0-based printed line slot.
  final int slot;
  final MushafLine line;
  final Rect rect;
  final List<WordBox> words;
}

class WordBox {
  const WordBox(this.word, this.rect, this.gap);
  final MushafWord word;
  final Rect rect;

  /// The justification gap after this word (part of the hit area).
  final double gap;
}
