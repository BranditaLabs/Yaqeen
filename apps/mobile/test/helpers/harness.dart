import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaqeen/core/design/living_sky.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

/// Tue 20 Oct 2026, 15:00 Cairo: the living sky's default instant in tests (deterministic goldens).
DateTime fixedSkyClock() => DateTime.utc(2026, 10, 20, 12);

/// Wraps a widget with theme, localisation and test providers. [skyClock] drives the living
/// background (pinned by default so screenshots never depend on when the tests run).
Widget harness(
  Widget child, {
  String locale = 'ar',
  List<Override> overrides = const [],
  MemoryKvStore? kv,
  DateTime Function() skyClock = fixedSkyClock,
}) =>
    ProviderScope(
      overrides: [
        kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
        skyClockProvider.overrideWithValue(skyClock),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: YqTheme.light(),
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );
