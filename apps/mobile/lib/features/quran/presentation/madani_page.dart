import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/mushaf_fonts.dart';
import '../domain/annotations.dart';
import '../domain/mushaf_layout.dart';
import '../domain/page_geometry.dart';
import '../domain/quran_data.dart';
import 'mushaf_page.dart';

/// Measures a word's advance width at font size 1 in its page font (a fake in tests).
typedef GlyphMeasure = double Function(MushafWord word, String family);

/// The printed Madani page, glyph for glyph: 15 lines drawn with the page's KFGQPC QCF V2 font, always
/// fitted to the box (no scroll), justified like print (spec §5.11). Highlights, the focused / playing
/// ayah, memorise mode and note badges are painted over the fixed layout, so nothing ever moves. A tap
/// or long-press is mapped to the word under the finger, then to its ayah.
class MadaniPage extends StatefulWidget {
  const MadaniPage({
    super.key,
    required this.layout,
    required this.quran,
    required this.page,
    required this.theme,
    this.selected,
    this.playing,
    this.annotations = Annotations.empty,
    this.memorise = MemoriseMode.off,
    this.revealed = const {},
    this.onAyahLongPress,
    this.onAyahTap,
    this.onNoteTap,
    this.onBackgroundTap,
    this.measure,
  });

  final MushafLayout layout;
  final QuranData quran;
  final int page;
  final MushafTheme theme;
  final AyahRef? selected;
  final AyahRef? playing;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;
  final ValueChanged<AyahRef>? onAyahLongPress;

  /// Memorise mode: a tap on an ayah reveals (or hides) it.
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;

  /// A tap that is not for the page itself (chrome toggle, turn zones), in global coordinates.
  final ValueChanged<Offset>? onBackgroundTap;

  /// Width measurement override (tests); defaults to the real font through TextPainter.
  final GlyphMeasure? measure;

  @override
  State<MadaniPage> createState() => MadaniPageState();
}

class MadaniPageState extends State<MadaniPage> {
  /// Where every word is drawn (tests: memorise must not move anything).
  @visibleForTesting
  PageGeometry? get geometry => _geometry;

  PageGeometry? _geometry;
  Size? _geometryFor;
  final Map<String, double> _units = {};

  @override
  void didUpdateWidget(MadaniPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page || oldWidget.layout != widget.layout) {
      _geometry = null;
      _units.clear();
    }
  }

  double _unit(MushafWord w, String family) {
    final m = widget.measure;
    if (m != null) return m(w, family);
    return _units.putIfAbsent('$family|${w.code}', () {
      final tp = TextPainter(
        text: TextSpan(text: w.code, style: TextStyle(fontFamily: family, fontSize: 100, height: 1)),
        textDirection: TextDirection.rtl,
      )..layout();
      final width = tp.width / 100;
      tp.dispose();
      return width;
    });
  }

  PageGeometry _geometryOf(Size size) {
    if (_geometry != null && _geometryFor == size) return _geometry!;
    final family = MushafFonts.family(widget.page);
    _geometryFor = size;
    return _geometry = PageGeometry.compute(
      lines: widget.layout.page(widget.page),
      size: size,
      unitWidth: (w) => _unit(w, family),
      opening: MushafLayout.isOpening(widget.page),
    );
  }

  bool _hidden(MushafWord w) {
    if (widget.memorise == MemoriseMode.off || widget.revealed.contains(w.ref) || w.isEnd) return false;
    // Every other word; the first stays as a cue.
    return widget.memorise == MemoriseMode.ayat || w.position.isEven;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = MushafColors.of(widget.theme);
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          final g = _geometryOf(size);
          final notes = [
            for (final ref in widget.annotations.notes.keys)
              if (g.endMarkerOf(ref) case final Rect r) (ref, r),
          ];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final ref = g.ayahAt(d.localPosition);
              if (widget.memorise != MemoriseMode.off && ref != null) {
                widget.onAyahTap?.call(ref);
              } else {
                widget.onBackgroundTap?.call(d.globalPosition);
              }
            },
            onLongPressStart: widget.memorise != MemoriseMode.off || widget.onAyahLongPress == null
                ? null
                : (d) {
                    final ref = g.ayahAt(d.localPosition);
                    if (ref != null) widget.onAyahLongPress!(ref);
                  },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MadaniPainter(
                      geometry: g,
                      page: widget.page,
                      layout: widget.layout,
                      quran: widget.quran,
                      colors: colors,
                      night: widget.theme == MushafTheme.night,
                      selected: widget.selected,
                      playing: widget.playing,
                      highlights: widget.annotations.highlights,
                      hidden: _hidden,
                      bandLabel: (s) => t.quranSurahName(widget.quran.surah(s).nameAr),
                      ayahLabel: (r) => widget.memorise != MemoriseMode.off && !widget.revealed.contains(r)
                          ? t.quranHiddenAyahA11y
                          : '${t.ayahA11y(widget.quran.surah(r.surah).nameAr, r.ayah)}\n${widget.quran.text(r)}',
                      memoriseKey: '${widget.memorise.name}:${widget.revealed.join(',')}',
                    ),
                  ),
                ),
                for (final (ref, r) in notes)
                  Positioned(
                    left: r.center.dx - 14,
                    top: r.top + g.pitch * 0.02 - 14,
                    width: 28,
                    height: 28,
                    child: Semantics(
                      button: true,
                      label: t.quranNoteA11y,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onNoteTap?.call(ref),
                        child: Center(
                          child: Icon(Icons.sticky_note_2_outlined, size: (g.fontSize * 0.5).clamp(10, 16), color: YqColors.gold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MadaniPainter extends CustomPainter {
  _MadaniPainter({
    required this.geometry,
    required this.page,
    required this.layout,
    required this.quran,
    required this.colors,
    required this.night,
    required this.selected,
    required this.playing,
    required this.highlights,
    required this.hidden,
    required this.bandLabel,
    required this.ayahLabel,
    required this.memoriseKey,
  });

  final PageGeometry geometry;
  final int page;
  final MushafLayout layout;
  final QuranData quran;
  final MushafColors colors;
  final bool night;
  final AyahRef? selected;
  final AyahRef? playing;
  final Map<AyahRef, MarkColor> highlights;
  final bool Function(MushafWord) hidden;
  final String Function(int surah) bandLabel;
  final String Function(AyahRef) ayahLabel;
  final String memoriseKey;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final font = g.fontSize;
    final family = MushafFonts.family(page);

    // 1 · ayah tints under the glyphs (saved highlights, then the selected / playing ayah on top).
    void tint(AyahRef ref, Color color) {
      final paint = Paint()..color = color;
      for (final r in g.rectsOf(ref)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(r.left - 2, r.top + g.pitch * 0.1, r.right + 2, r.bottom - g.pitch * 0.06),
            Radius.circular(g.pitch * 0.18),
          ),
          paint,
        );
      }
    }

    for (final e in highlights.entries) {
      tint(e.key, colors.mark(e.value));
    }
    for (final r in {selected, playing}.whereType<AyahRef>()) {
      tint(r, colors.highlight);
    }

    // 2 · lines.
    final dotted = Paint()
      ..color = colors.muted
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final l in g.lines) {
      switch (l.line) {
        case TextLine():
          for (final w in l.words) {
            if (hidden(w.word)) {
              // Memorise: the word keeps its place; a dotted rule marks it.
              final y = w.rect.top + g.pitch * 0.72;
              for (var x = w.rect.left + 2; x < w.rect.right - 2; x += 5) {
                canvas.drawLine(Offset(x, y), Offset(x + 1.5, y), dotted);
              }
              continue;
            }
            _glyph(canvas, w.word.code, family, font, colors.ink, w.rect, g.pitch);
          }
        case SurahBandLine(:final surah):
          _band(canvas, l.rect, bandLabel(surah), font);
        case BasmalaLine():
          _basmala(canvas, l.rect, font);
        case EmptyLine():
          break;
      }
    }
    // Hizb-quarter signs and prostration marks are part of the printed glyphs; the page header names
    // the quarter / sajdah in words.
  }

  void _glyph(Canvas canvas, String code, String family, double font, Color color, Rect rect, double pitch) {
    final tp = TextPainter(
      text: TextSpan(text: code, style: TextStyle(fontFamily: family, fontSize: font, height: 1, color: color)),
      textDirection: TextDirection.rtl,
    )..layout();
    // The em box sits a little below the slot centre: QCF marks rise above the letters.
    tp.paint(canvas, Offset(rect.right - tp.width, rect.top + (pitch - tp.height) / 2 + pitch * 0.08));
    tp.dispose();
  }

  /// A quiet framed band: double hairline, the surah name centred in the Quran face.
  void _band(Canvas canvas, Rect line, String label, double font) {
    final r = Rect.fromLTRB(
      line.left + line.width * 0.04,
      line.top + line.height * 0.14,
      line.right - line.width * 0.04,
      line.bottom - line.height * 0.14,
    );
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..color = colors.frame.withAlpha(0xFF)
      ..strokeWidth = 1;
    final radius = Radius.circular(r.height * 0.32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, radius),
      Paint()..color = (night ? YqColors.nightInk : YqColors.gold).withAlpha(night ? 10 : 18),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(r, radius), frame);
    canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(3), Radius.circular(r.height * 0.26)), frame..strokeWidth = 0.6);
    final tp = TextPainter(
      text: TextSpan(text: label, style: YqText.quran(size: font * 0.86, height: 1.2, color: colors.ink)),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout(maxWidth: r.width);
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
    tp.dispose();
  }

  /// Page 1's glyphs are drawn smaller than the rest of the mushaf; this brings the Basmala line to
  /// the printed size (about half the line width).
  static const basmalaScale = 1.3;

  /// The Basmala in page 1's glyphs (the same hand as the page), centred on its line.
  void _basmala(Canvas canvas, Rect line, double font) {
    final words = layout.basmalaWords;
    final family = MushafFonts.family(1);
    List<TextPainter> build(double size) => [
          for (final w in words)
            TextPainter(
              text: TextSpan(text: w.code, style: TextStyle(fontFamily: family, fontSize: size, height: 1, color: colors.ink)),
              textDirection: TextDirection.rtl,
            )..layout(),
        ];
    var painters = build(font * basmalaScale);
    var total = painters.fold<double>(0, (s, p) => s + p.width);
    if (total > line.width * 0.7) {
      // Narrow (opening-like) blocks: keep the Basmala inside the line.
      for (final p in painters) {
        p.dispose();
      }
      painters = build(font * basmalaScale * line.width * 0.7 / total);
      total = painters.fold<double>(0, (s, p) => s + p.width);
    }
    var right = line.center.dx + total / 2;
    for (final p in painters) {
      p.paint(canvas, Offset(right - p.width, line.top + (line.height - p.height) / 2 + line.height * 0.08));
      right -= p.width;
      p.dispose();
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final seen = <AyahRef>{};
        final nodes = <CustomPainterSemantics>[];
        for (final l in geometry.lines) {
          if (l.line case SurahBandLine(:final surah)) {
            nodes.add(
              CustomPainterSemantics(
                rect: l.rect,
                properties: SemanticsProperties(label: bandLabel(surah), header: true, textDirection: TextDirection.rtl),
              ),
            );
          }
          for (final w in l.words) {
            if (!seen.add(w.word.ref)) continue;
            final rects = geometry.rectsOf(w.word.ref);
            nodes.add(
              CustomPainterSemantics(
                key: ValueKey('ayah-${w.word.ref}'),
                rect: rects.reduce((a, b) => a.expandToInclude(b)),
                properties: SemanticsProperties(label: ayahLabel(w.word.ref), textDirection: TextDirection.rtl),
              ),
            );
          }
        }
        return nodes;
      };

  @override
  bool shouldRepaint(_MadaniPainter old) =>
      old.geometry != geometry ||
      old.colors != colors ||
      old.selected != selected ||
      old.playing != playing ||
      old.highlights != highlights ||
      old.memoriseKey != memoriseKey;

  @override
  bool shouldRebuildSemantics(_MadaniPainter old) => old.geometry != geometry || old.memoriseKey != memoriseKey;
}
