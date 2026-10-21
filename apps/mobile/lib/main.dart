import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_gate.dart';
import 'app/router.dart';
import 'core/di/providers.dart';
import 'core/network/connectivity.dart';
import 'core/platform/device_services.dart';
import 'core/platform/location_service.dart';
import 'core/platform/social_auth.dart';
import 'core/settings/settings_controller.dart';
import 'core/settings/settings_repository.dart';
import 'core/config/remote_config.dart';
import 'core/offline/outbox.dart';
import 'core/network/api_client.dart';
import 'core/config/env.dart';
import 'core/storage/kv_store.dart';
import 'core/storage/local_store.dart';
import 'core/theme/theme.dart';
import 'core/time/zoned.dart';
import 'features/onboarding/data/auth_repository.dart';
import 'l10n/gen/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  Zoned.ensureInitialized();

  // Everything the first frame needs is read from the device — no network on the critical path.
  final prefs = await SharedPreferences.getInstance();
  final kv = PrefsKvStore(prefs);
  final secure = SecureKvStore();
  await LocalStore(kv).migrate();
  final settings = await SettingsRepository(store: kv, outbox: Outbox(kv)).load();
  final config = await RemoteConfigRepository(api: ApiClient(baseUrl: Env.apiBaseUrl, tokens: TokenStore(secure)), cache: kv).cached();
  final session =
      await AuthRepository(api: ApiClient(baseUrl: Env.apiBaseUrl, tokens: TokenStore(secure)), tokens: TokenStore(secure), store: kv)
          .load();

  final container = ProviderContainer(
    overrides: [
      kvStoreProvider.overrideWithValue(kv),
      secureStoreProvider.overrideWithValue(secure),
      initialSettingsProvider.overrideWithValue(settings),
      initialConfigProvider.overrideWithValue(config),
      initialSessionProvider.overrideWithValue(session),
      deviceServicesProvider.overrideWithValue(PluginDeviceServices()),
      locationServiceProvider.overrideWithValue(PluginLocationService()),
      compassServiceProvider.overrideWithValue(PluginCompassService()),
      socialAuthProvider.overrideWithValue(PluginSocialAuth()),
      connectivityProvider.overrideWithValue(PluginConnectivityMonitor()),
      // Phase 2: pushServiceProvider (Firebase) and adSinksProvider (ad SDKs) — see README.
    ],
  );
  await container.read(consentRepositoryProvider).load();
  container.read(apiClientProvider).onSessionExpired = () => container.read(authRepositoryProvider).signOut();

  runApp(UncontrolledProviderScope(container: container, child: YaqeenApp(router: buildRouter(initialLocation: '/splash'))));
}

class YaqeenApp extends ConsumerWidget {
  const YaqeenApp({super.key, this.router});

  /// Defaults to [appRouter] (starts on /home — used by tests); main() starts on /splash.
  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Switching the language rebuilds every screen live, no restart (spec §5.3).
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: YqTheme.light(),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router ?? appRouter,
      builder: (context, child) => AppGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
