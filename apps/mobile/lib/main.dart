import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/di/providers.dart';
import 'core/storage/kv_store.dart';
import 'core/theme/theme.dart';
import 'l10n/gen/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ),);

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    kvStoreProvider.overrideWithValue(PrefsKvStore(prefs)),
    // Phase 2: override localNotificationsProvider, pushServiceProvider and
    // adSinksProvider with plugin-backed implementations (see apps/mobile/README.md).
  ],);
  await container.read(consentRepositoryProvider).load();

  runApp(UncontrolledProviderScope(container: container, child: YaqeenApp(router: buildRouter(initialLocation: '/splash'))));
}

class YaqeenApp extends StatelessWidget {
  const YaqeenApp({super.key, this.locale = const Locale('ar'), this.router});

  /// Arabic by default; switches to English from settings.
  final Locale locale;

  /// Defaults to [appRouter] (starts on /home — used by tests); main() starts on /splash.
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: YqTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router ?? appRouter,
    );
  }
}
