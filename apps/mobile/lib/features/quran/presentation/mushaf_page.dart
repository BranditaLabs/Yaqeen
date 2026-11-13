import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/annotations.dart';
import '../domain/passage.dart';
import '../domain/quran_data.dart';

/// Colours of a mushaf theme (spec §2.1: paper · white · night).
class MushafColors {
  MushafColors(this.page, this.ink, this.muted, this.highlight, this.frame, {required Color accent})
      : playing = accent.withValues(alpha: 0.08),
        playingRail = accent,
        passageRail = accent.withValues(alpha: 0.35),
        noteUnderline = muted;
  final Color page;
  final Color ink;
  final Color muted;
  final Color highlight;
  final Color frame;

  /// The ayah being recited: a lapis wash (≈ 8 %) with a 2-pt rail under it — never a dimmed page.
  final Color playing;
  final Color playingRail;

  /// The margin rail beside the lines of the passage a layer works on (memorise, recite, sessions).
  final Color passageRail;

  /// A recitation «تنبيه»: a muted dotted underline, never red, never «خطأ».
  final Color noteUnderline;

  static final _paper = MushafColors(
    YqColors.paperPage,
    YqColors.paperInk,
    YqColors.paperInk.withValues(alpha: 0.6),
    YqColors.goldLight.withValues(alpha: 0.3),
    YqColors.gold.withValues(alpha: 0.2),
    accent: YqColors.lapis,
  );
  static final _white = MushafColors(
    YqColors.white,
    YqColors.ink,
    YqColors.muted,
    YqColors.sky.withValues(alpha: 0.2),
    YqColors.line,
    accent: YqColors.lapis,
  );
  // Night: #E9E2D0 on #15161A ≈ 13:1 contrast (AA, spec §5.11); the wash uses the light sky hue.
  static final _night = MushafColors(
    YqColors.nightPage,
    YqColors.nightInk,
    YqColors.nightInk.withValues(alpha: 0.6),
    YqColors.goldText.withValues(alpha: 0.25),
    YqColors.nightInk.withValues(alpha: 0.2),
    accent: YqColors.sky,
  );

  static MushafColors of(MushafTheme t) => switch (t) {
        MushafTheme.paper => _paper,
        MushafTheme.white => _white,
        MushafTheme.night => _night,
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
/// page's verse range comes from the printed layout). This is the text page set in Amiri Quran — the
/// reader's fallback while a page's KFGQPC font is not on the device (see [FittedMushafPage] and
/// `madani_page.dart`). Hidden words keep their place (transparent ink over a dotted line), so
/// revealing never moves the text.
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
    this.marks = const {},
    this.passage,
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

  /// The ayah being recited: its own wash and rail ([MushafColors.playing]), apart from [selected].
  final AyahRef? playing;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;

  /// Recitation «تنبيه» marks: 1-based word positions per ayah, drawn as a muted dotted underline.
  final Map<AyahRef, Set<int>> marks;

  /// The passage a layer works on (the printed page draws its margin rail; the text page has none).
  final Passage? passage;
  final ValueChanged<AyahRef>? onAyahLongPress;

  /// A tap on an ayah (memorise: reveal; listen: play from it; recite: hear a noted ayah). In
  /// memorise mode, or without [onAyahLongPress], the text page answers taps; otherwise it keeps
  /// long-press for the ayah options (a text span carries one recognizer).
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final Map<AyahRef, GestureRecognizer> _recognizers = {};
  bool? _builtForTap;

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

  bool get _tapMode => widget.onAyahTap != null && (widget.memorise != MemoriseMode.off || widget.onAyahLongPress == null);

  /// Long-press for the ayah options; a tap where a layer listens for one ([MushafPage.onAyahTap]).
  GestureRecognizer _recognizer(AyahRef ref) {
    final tap = _tapMode;
    if (_builtForTap != tap) {
      _clearRecognizers();
      _builtForTap = tap;
    }
    return _recognizers.putIfAbsent(
      ref,
      () => tap
          ? (TapGestureRecognizer()..onTap = () => widget.onAyahTap?.call(ref))
          : (LongPressGestureRecognizer()..onLongPress = () => widget.onAyahLongPress?.call(ref)),
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
      color: c.ink.withValues(alpha: 0),
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: c.muted,
      decorationThickness: 1.6,
    );
    final noted = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: c.noteUnderline,
      decorationThickness: 1.6,
    );

    TextStyle look(AyahRef r) {
      if (r == widget.selected) return TextStyle(backgroundColor: c.highlight);
      if (r == widget.playing) {
        return TextStyle(backgroundColor: c.playing, decoration: TextDecoration.underline, decorationColor: c.playingRail, decorationThickness: 2);
      }
      final mark = widget.annotations.highlights[r];
      return TextStyle(backgroundColor: mark == null ? null : c.mark(mark));
    }

    List<InlineSpan> ayahSpans(PageSegment seg, PageAyah a) {
      final rec = _recognizer(a.ref);
      final base = look(a.ref);
      final label = t.ayahA11y(seg.surah.nameAr, a.ref.ayah);
      final isHidden = widget.memorise != MemoriseMode.off &&
          !widget.revealed.contains(a.ref) &&
          (widget.passage == null || widget.passage!.contains(a.ref));
      final notes = widget.marks[a.ref] ?? const <int>{};
      final spans = <InlineSpan>[];
      final quarter = q.quarterStartingAt(a.ref);
      if (quarter != null && !(a.ref.surah == 1 && a.ref.ayah == 1)) spans.add(_marker(_quarterLabel(t, quarter), c, widget.fontSize));
      if (!isHidden && notes.isEmpty) {
        spans.add(TextSpan(text: '${a.text} ', recognizer: rec, semanticsLabel: label, style: base));
      } else if (isHidden && widget.memorise == MemoriseMode.ayat) {
        spans.add(TextSpan(text: '${a.text} ', recognizer: rec, semanticsLabel: t.quranHiddenAyahA11y, style: hidden));
      } else {
        // Word by word: every other word hidden (the first stays as a cue), or noted words underlined.
        final words = a.text.split(' ');
        for (final (i, w) in words.indexed) {
          spans.add(
            TextSpan(
              text: '$w ',
              recognizer: rec,
              semanticsLabel: i == 0 ? (isHidden ? t.quranHiddenAyahA11y : label) : '',
              style: isHidden && i.isOdd ? hidden : (notes.contains(i + 1) ? base.merge(noted) : base),
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
                _SurahHeader(name: t.quranSurahName(seg.surah.nameAr), colors: c, fontSize: widget.fontSize),
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

/// The text page fitted to its box — the offline fallback of the printed page (no font yet, no network).
/// The font size is the largest whose measured page height fits (binary search); a final scale-down
/// guards the last pixels, so the page never scrolls or overflows.
class FittedMushafPage extends StatelessWidget {
  const FittedMushafPage({super.key, required this.page, this.minSize = 10, this.maxSize = 40});

  /// The page to draw; its [MushafPage.fontSize] is replaced by the fitted size.
  final MushafPage page;
  final double minSize;
  final double maxSize;

  static final Map<String, double> _fitted = {};

  /// The page height at [fontSize] in [width] (mirrors [MushafPage]'s layout; markers as text).
  static double measureHeight({
    required QuranData quran,
    required int page,
    required double width,
    required double fontSize,
    required bool comfortable,
    required AppLocalizations t,
  }) {
    final style = YqText.quran(size: fontSize, height: comfortable ? 2.6 : 2.15);
    var h = 0.0;
    double measure(InlineSpan span, TextStyle s) {
      final tp = TextPainter(text: span, textDirection: TextDirection.rtl, textAlign: TextAlign.justify)..layout(maxWidth: width);
      final out = tp.height;
      tp.dispose();
      return out;
    }

    for (final seg in quran.page(page)) {
      if (seg.startsSurah) {
        h += _SurahHeader.margin(fontSize) * 2 + _SurahHeader.padding(fontSize) * 2 + 2.4;
        h += measure(TextSpan(text: t.quranSurahName(seg.surah.nameAr), style: _SurahHeader.style(fontSize)), style);
        if (seg.surah.number != 1 && seg.surah.number != 9) {
          h += 4 + measure(TextSpan(text: quran.basmala, style: style.copyWith(fontSize: fontSize * 0.92)), style);
        }
      }
      final parts = <InlineSpan>[];
      for (final a in seg.ayat) {
        if (quran.quarterStartingAt(a.ref) != null) {
          parts.add(TextSpan(text: ' ${t.quranMarkHizb('00')} ', style: TextStyle(fontSize: fontSize * 0.5)));
        }
        parts.add(TextSpan(text: '${a.text} '));
        parts.add(TextSpan(text: '﴿${YqFormat.toArabicIndic(a.ref.ayah)}﴾ ', style: TextStyle(fontSize: fontSize * 0.8)));
        if (quran.sajdas.contains(a.ref)) parts.add(TextSpan(text: ' ${t.quranMarkSajdah} ', style: TextStyle(fontSize: fontSize * 0.5)));
      }
      h += measure(TextSpan(children: parts, style: style), style);
    }
    return h;
  }

  /// The largest size in [lo, hi] whose page fits [box].
  static double fit({
    required QuranData quran,
    required int page,
    required Size box,
    required bool comfortable,
    required AppLocalizations t,
    double lo = 10,
    double hi = 40,
  }) {
    if (measureHeight(quran: quran, page: page, width: box.width, fontSize: lo, comfortable: comfortable, t: t) > box.height) return lo;
    for (var i = 0; i < 9; i++) {
      final mid = (lo + hi) / 2;
      if (measureHeight(quran: quran, page: page, width: box.width, fontSize: mid, comfortable: comfortable, t: t) <= box.height) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final p = page;
        // A small reserve for the hairline pills drawn as widgets (measured as text). Fitting measures
        // the page ~10 times, so results are kept per page and box.
        final key = '${p.page}|${size.width.round()}x${size.height.round()}|${p.comfortable}|${t.localeName}';
        final font = _fitted[key] ??= fit(
          quran: p.quran,
          page: p.page,
          box: Size(size.width, size.height * 0.97),
          comfortable: p.comfortable,
          t: t,
          lo: minSize,
          hi: maxSize,
        );
        if (_fitted.length > 64) _fitted.remove(_fitted.keys.first);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: size.width,
            child: MushafPage(
              key: p.key,
              quran: p.quran,
              page: p.page,
              theme: p.theme,
              fontSize: font,
              comfortable: p.comfortable,
              locale: p.locale,
              selected: p.selected,
              playing: p.playing,
              annotations: p.annotations,
              memorise: p.memorise,
              revealed: p.revealed,
              marks: p.marks,
              passage: p.passage,
              onAyahLongPress: p.onAyahLongPress,
              onAyahTap: p.onAyahTap,
              onNoteTap: p.onNoteTap,
            ),
          ),
        );
      },
    );
  }
}

/// Hairline frame with the surah name — deliberately plain (no geometric ornament, brand rule 8).
class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.name, required this.colors, required this.fontSize});
  final String name;
  final MushafColors colors;
  final double fontSize;

  /// Sizes follow the page's text size, so a fitted page with three surahs still fits.
  static double margin(double fontSize) => (fontSize * 0.42).clamp(4.0, YqSpace.m);
  static double padding(double fontSize) => (fontSize * 0.28).clamp(3.0, YqSpace.s);
  static TextStyle style(double fontSize) =>
      TextStyle(fontFamily: YqFonts.naskh, fontWeight: FontWeight.w700, fontSize: (fontSize * 0.78).clamp(12.0, 20.0));

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: margin(fontSize)),
          padding: EdgeInsets.symmetric(vertical: padding(fontSize)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YqRadii.chip),
            border: Border.all(color: colors.frame, width: 1.2),
          ),
          child: Text(name, textAlign: TextAlign.center, style: style(fontSize).copyWith(color: colors.ink)),
        ),
      );
}
