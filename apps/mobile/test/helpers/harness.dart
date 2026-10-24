import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

/// Wraps a widget with theme, localisation and test providers.
Widget harness(Widget child, {String locale = 'ar', List<Override> overrides = const [], MemoryKvStore? kv}) => ProviderScope(
      overrides: [
        kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
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
