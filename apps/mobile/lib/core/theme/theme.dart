import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

abstract final class YqTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: YqColors.lapis,
      brightness: Brightness.light,
    ).copyWith(
      primary: YqColors.lapis,
      onPrimary: YqColors.white,
      secondary: YqColors.gold,
      onSecondary: YqColors.ink,
      surface: YqColors.porcelain,
      onSurface: YqColors.ink,
      error: YqColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: YqColors.porcelain,
      fontFamily: YqFonts.ui,
      textTheme: YqText.textTheme(),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: YqColors.ink,
          foregroundColor: YqColors.white,
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: YqFonts.ui, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: YqColors.lapis,
          minimumSize: const Size(YqSpace.touch, YqSpace.touch),
          textStyle: const TextStyle(fontFamily: YqFonts.ui, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
