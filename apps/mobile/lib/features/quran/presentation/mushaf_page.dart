import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/annotations.dart';
import '../domain/quran_data.dart';

/// Colours of a mushaf theme (spec §2.1: paper · white · night).
class MushafColors {
  const MushafColors(this.page, this.ink, this.muted, this.highlight, this.frame);
  final Color page;
  final Color ink;
  final Color muted;
  final Color highlight;
  final Color frame;

  static MushafColors of(MushafTheme t) => switch (t) {
        MushafTheme.paper =>
          const MushafColors(YqColors.paperPage, YqColors.paperInk, Color(0x991A1712), Color(0x4DE9D49E), Color(0x33C6A867)),
        MushafTheme.white => const MushafColors(YqColors.white, YqColors.ink, YqColors.muted, Color(0x338FB0E0), YqColors.line),
        // Night: #E9E2D0 on #15161A ≈ 13:1 contrast (AA, spec §5.11).
        MushafTheme.night =>
          const MushafColors(YqColors.nightPage, YqColors.nightInk, Color(0x99E9E2D0), Color(0x407C6127), Color(0x33E9E2D0)),
      };

  /// A saved highlight's tint, readable on every page colour (token hues at low alpha).
  Color mark(MarkColor c) => switch (c) {
        MarkColor.gold => YqColors.goldLight.withAlpha(110),
        MarkColor.lapis => YqColors.lapis.withAlpha(46),
        MarkColor.sky => YqColors.sky.withAlpha(90),
        MarkColor.green => YqColors.success.withAlpha(52),
      };
}

/// Memorise mode (spec §5.11): hide whole ayat, or every other word, and reveal by tapping.
enum MemoriseMode { off, ayat, words }

/// One mushaf page: surah headers, Basmala, ayat with end markers ﴿N﴾, juz / hizb-quarter markers
/// where they start and «سجدة» after a prostration ayah. Never reflows an ayah onto another page (the
/// page's verse range comes from the Madani metadata). Until a licensed per-page glyph font (KFGQPC)
/// is installed, verses are set in Amiri Quran. Hidden words keep their place (transparent ink over a
/// dotted line), so revealing never moves the text.
class MushafPage extends StatefulWidget {
  const MushafPage({
    super.key,
    required this.quran,
    required this.page,
    required this.theme,
    required this.fontSize,
    required this.comfortable,
    required this.locale,
    this.selected,
    this.playing,
    this.annotations = Annotations.empty,
    this.memorise = MemoriseMode.off,
    this.revealed = const {},
    this.onAyahLongPress,
    this.onAyahTap,
    this.onNoteTap,
  });

  final QuranData quran;
  final int page;
  final MushafTheme theme;
  final double fontSize;
  final bool comfortable;
  final String locale;
  final AyahRef? selected;
  final AyahRef? playing;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;
  final ValueChanged<AyahRef>? onAyahLongPress;

  /// Memorise mode: a tap on an ayah reveals (or hides) it.
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final Map<AyahRef, GestureRecognizer> _recognizers = {};
  MemoriseMode? _builtFor;

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  /// Long-press for the ayah options; in memorise mode a tap reveals instead.
  GestureRecognizer _recognizer(AyahRef ref) {
    if (_builtFor != widget.memorise) {
      _clearRecognizers();
      _builtFor = widget.memorise;
    }
    return _recognizers.putIfAbsent(
      ref,
      () => widget.memorise == MemoriseMode.off
          ? (LongPressGestureRecognizer()..onLongPress = () => widget.onAyahLongPress?.call(ref))
          : (TapGestureRecognizer()..onTap = () => widget.onAyahTap?.call(ref)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = MushafColors.of(widget.theme);
    final q = widget.quran;
    // Mushaf size is the reader's own control — not scaled by system text size (spec §5.11 a11y).
    final style = YqText.quran(size: widget.fontSize, height: widget.comfortable ? 2.6 : 2.15, color: c.ink);
    final segments = q.page(widget.page);
    final hidden = TextStyle(
      color: const Color(0x00000000),
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: c.muted,
      decorationThickness: 1.6,
    );

    Color? background(AyahRef r) {
      if (r == widget.selected || r == widget.playing) return c.highlight;
      final mark = widget.annotations.highlights[r];
      return mark == null ? null : c.mark(mark);
    }

    List<InlineSpan> ayahSpans(PageSegment seg, PageAyah a) {
      final rec = _recognizer(a.ref);
      final bg = background(a.ref);
      final label = t.ayahA11y(seg.surah.nameAr, a.ref.ayah);
      final isHidden = widget.memorise != MemoriseMode.off && !widget.revealed.contains(a.ref);
      final spans = <InlineSpan>[];
      final quarter = q.quarterStartingAt(a.ref);
      if (quarter != null && !(a.ref.surah == 1 && a.ref.ayah == 1)) spans.add(_marker(_quarterLabel(t, quarter), c, widget.fontSize));
      if (!isHidden) {
        spans.add(TextSpan(text: '${a.text} ', recognizer: rec, semanticsLabel: label, style: TextStyle(backgroundColor: bg)));
      } else if (widget.memorise == MemoriseMode.ayat) {
        spans.add(TextSpan(text: '${a.text} ', recognizer: rec, semanticsLabel: t.quranHiddenAyahA11y, style: hidden));
      } else {
        // Every other word hidden; the first stays as a cue.
        final words = a.text.split(' ');
        for (final (i, w) in words.indexed) {
          spans.add(
            TextSpan(
              text: '$w ',
              recognizer: rec,
              semanticsLabel: i == 0 ? t.quranHiddenAyahA11y : '',
              style: i.isOdd ? hidden : TextStyle(backgroundColor: bg),
            ),
          );
        }
      }
      spans.add(
        TextSpan(
          text: '﴿${YqFormat.toArabicIndic(a.ref.ayah)}﴾ ',
          style: TextStyle(color: c.muted, fontSize: widget.fontSize * 0.8),
          semanticsLabel: '',
        ),
      );
      if (q.sajdas.contains(a.ref)) spans.add(_marker(t.quranMarkSajdah, c, widget.fontSize, gold: true));
      final note = widget.annotations.notes[a.ref];
      if (note != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              button: true,
              label: t.quranNoteA11y,
              child: GestureDetector(
                onTap: () => widget.onNoteTap?.call(a.ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.sticky_note_2_outlined, size: widget.fontSize * 0.62, color: YqColors.gold),
                ),
              ),
            ),
          ),
        );
      }
      return spans;
    }

    return MediaQuery.withNoTextScaling(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final seg in segments) ...[
              if (seg.startsSurah) ...[
                _SurahHeader(name: t.quranSurahName(seg.surah.nameAr), colors: c),
                if (seg.surah.number != 1 && seg.surah.number != 9)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(q.basmala, textAlign: TextAlign.center, style: style.copyWith(fontSize: widget.fontSize * 0.92)),
                  ),
              ],
              Text.rich(
                TextSpan(children: [for (final a in seg.ayat) ...ayahSpans(seg, a)]),
                textAlign: TextAlign.justify,
                style: style,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// «الجزء 2» at a juz start, «الحزب 5» at a hizb start, «¼ / ½ / ¾ الحزب 5» at the quarters.
  static String _quarterLabel(AppLocalizations t, int quarter) {
    final hizb = (quarter - 1) ~/ 4 + 1;
    final part = (quarter - 1) % 4;
    if ((quarter - 1) % 8 == 0) return t.quranMarkJuz(YqFormat.number((quarter - 1) ~/ 8 + 1));
    if (part == 0) return t.quranMarkHizb(YqFormat.number(hizb));
    return t.quranMarkQuarter(const ['', '¼', '½', '¾'][part], YqFormat.number(hizb));
  }

  /// A quiet margin-style chip inside the text flow (plain hairline pill — no ornament, brand rule 8).
  static InlineSpan _marker(String label, MushafColors c, double fontSize, {bool gold = false}) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YqRadii.pill),
            border: Border.all(color: gold ? YqColors.gold : c.frame),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: YqFonts.ui,
              fontSize: (fontSize * 0.42).clamp(10, 15),
              height: 1.3,
              color: gold ? YqColors.goldText : c.muted,
            ),
          ),
        ),
      );
}

/// Hairline frame with the surah name — deliberately plain (no geometric ornament, brand rule 8).
class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.name, required this.colors});
  final String name;
  final MushafColors colors;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: YqSpace.m),
          padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YqRadii.chip),
            border: Border.all(color: colors.frame, width: 1.2),
          ),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: YqFonts.naskh, fontWeight: FontWeight.w700, fontSize: 20, color: colors.ink),
          ),
        ),
      );
}
