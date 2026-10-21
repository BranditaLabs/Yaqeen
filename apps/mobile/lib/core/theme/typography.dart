import 'package:flutter/material.dart';

import 'tokens.dart';

/// Font families. Tajawal / Jost / Amiri / Amiri Quran are bundled (SIL OFL).
/// The brand typefaces (ZEYADA Arabic 1, Canela Text) are commercial: once the licensed files are
/// added (packages/brand/fonts/README.md) they take over automatically; until then the fallbacks render.
abstract final class YqFonts {
  static const ui = 'Tajawal';
  static const numbers = 'Jost';
  static const brandArabic = 'ZeyadaArabic';
  static const brandLatin = 'CanelaText';
  static const naskh = 'Amiri';
  static const quran = 'AmiriQuran';

  /// Headlines: brand Arabic → brand Latin (for mixed text) → Amiri.
  static const display = brandArabic;
  static const displayFallback = [brandLatin, naskh, ui];
}

abstract final class YqText {
  /// Feature titles in the brand headline face. The logo itself is never typeset — use [YqLogo].
  static const display = TextStyle(
    fontFamily: YqFonts.display,
    fontFamilyFallback: YqFonts.displayFallback,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1.4,
    color: YqColors.midnight,
  );

  /// Big numerals: countdowns, points, degrees.
  static const numeral = TextStyle(
    fontFamily: YqFonts.numbers,
    fontWeight: FontWeight.w300,
    fontSize: 38,
    height: 1.1,
    color: YqColors.lapis,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const numberSmall = TextStyle(
    fontFamily: YqFonts.numbers,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: YqColors.muted,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Mushaf text. Size is user-controlled (22–34).
  static TextStyle quran({double size = 26, double height = 2.4, Color color = YqColors.paperInk}) =>
      TextStyle(fontFamily: YqFonts.quran, fontSize: size, height: height, color: color);

  /// Duas and azkar.
  static const dua = TextStyle(
    fontFamily: YqFonts.naskh,
    fontWeight: FontWeight.w700,
    fontSize: 21,
    height: 2,
    color: YqColors.ink,
  );

  static TextTheme textTheme() => const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.25, color: YqColors.ink),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.35, color: YqColors.ink),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: YqColors.ink),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: YqColors.ink),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: YqColors.ink),
        bodyLarge: TextStyle(fontSize: 15, height: 1.7, color: YqColors.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.6, color: YqColors.ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.6, color: YqColors.muted),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontSize: 11, color: YqColors.muted),
      );
}
