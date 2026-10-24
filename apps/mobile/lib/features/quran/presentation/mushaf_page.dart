import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../l10n/gen/app_localizations.dart';
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
          const MushafColors(YqColors.paperPage, YqColors.paperInk, Color(0xFF7A6E58), Color(0x4DE9D49E), Color(0x33C6A867)),
        MushafTheme.white => const MushafColors(YqColors.white, YqColors.ink, YqColors.muted, Color(0x338FB0E0), YqColors.line),
        // Night: #E9E2D0 on #15161A ≈ 13:1 contrast (AA, spec §5.11).
        MushafTheme.night =>
          const MushafColors(YqColors.nightPage, YqColors.nightInk, Color(0xFF9C9584), Color(0x407C6127), Color(0x33E9E2D0)),
      };
}

/// One mushaf page: surah headers, Basmala, ayat with end markers ﴿N﴾. Never reflows an ayah onto
/// another page (the page's verse range comes from the Madani metadata). Until a licensed per-page
/// glyph font (KFGQPC) is installed, verses are set in Amiri Quran.
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
    this.onAyahLongPress,
  });

  final QuranData quran;
  final int page;
  final MushafTheme theme;
  final double fontSize;
  final bool comfortable;
  final String locale;
  final AyahRef? selected;
  final AyahRef? playing;
  final ValueChanged<AyahRef>? onAyahLongPress;

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  final Map<AyahRef, LongPressGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    super.dispose();
  }

  LongPressGestureRecognizer _recognizer(AyahRef ref) => _recognizers.putIfAbsent(
        ref,
        () => LongPressGestureRecognizer()..onLongPress = () => widget.onAyahLongPress?.call(ref),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = MushafColors.of(widget.theme);
    final q = widget.quran;
    // Mushaf size is the reader's own control — not scaled by system text size (spec §5.11 a11y).
    final style = YqText.quran(size: widget.fontSize, height: widget.comfortable ? 2.6 : 2.15, color: c.ink);
    final segments = q.page(widget.page);

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
                TextSpan(
                  children: [
                    for (final a in seg.ayat) ...[
                      TextSpan(
                        text: '${a.text} ',
                        recognizer: _recognizer(a.ref),
                        semanticsLabel: t.ayahA11y(seg.surah.nameAr, a.ref.ayah),
                        style: TextStyle(
                          backgroundColor: a.ref == widget.selected || a.ref == widget.playing ? c.highlight : null,
                        ),
                      ),
                      TextSpan(
                        text: '﴿${YqFormat.toArabicIndic(a.ref.ayah)}﴾ ',
                        style: TextStyle(color: c.muted, fontSize: widget.fontSize * 0.8),
                        semanticsLabel: '',
                      ),
                    ],
                  ],
                ),
                textAlign: TextAlign.justify,
                style: style,
              ),
            ],
          ],
        ),
      ),
    );
  }
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
