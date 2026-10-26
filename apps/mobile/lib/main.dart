import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_gate.dart';
import 'app/bootstrap.dart';
import 'app/router.dart';
import 'core/analytics/product_analytics.dart';
import 'core/di/providers.dart';
import 'core/notifications/local_notifier.dart';
import 'core/notifications/notification_planner.dart';
import 'features/notifications/data/reminder_service.dart';
import 'core/settings/app_settings.dart';
import 'core/network/connectivity.dart';
import 'core/platform/device_services.dart';
import 'core/platform/just_audio_engine.dart';
import 'core/platform/location_service.dart';
import 'core/platform/sentry_error_reporter.dart';
import 'core/platform/social_auth.dart';
import 'core/settings/settings_controller.dart';
import 'core/settings/settings_repository.dart';
import 'core/config/remote_config.dart';
import 'core/offline/outbox.dart';
import 'core/network/api_client.dart';
import 'core/config/env.dart';
import 'core/storage/kv_store.dart';
import 'core/storage/local_store.dart';
import 'core/theme/scroll.dart';
import 'core/theme/theme.dart';
import 'core/time/zoned.dart';
import 'features/onboarding/data/auth_repository.dart';
import 'l10n/gen/app_localizations.dart';

void main() {
  Boot.reporter = SentryErrorReporter();
  Boot.guard(_start);
}

Future<void> _start() async {
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

  // Everything the first frame needs is read from the device — no network, no plugin set-up on the
  // critical path, and every step time-boxed with a safe fallback (lib/app/bootstrap.dart).
  final KvStore kv = await Boot.step<KvStore>('prefs', () async => PrefsKvStore(await SharedPreferences.getInstance()), MemoryKvStore());
  final secure = SecureKvStore();
  final tokens = TokenStore(secure);
  final api = ApiClient(baseUrl: Env.apiBaseUrl, tokens: tokens);
  await Boot.step('migrate', () => LocalStore(kv).migrate(), null);
  final (settings, config, session) = await (
    Boot.step('settings', () => SettingsRepository(store: kv, outbox: Outbox(kv)).load(), const AppSettings()),
    Boot.step('config', () => RemoteConfigRepository(api: api, cache: kv).cached(), const RemoteConfig()),
    Boot.step('session', () => AuthRepository(api: api, tokens: tokens, store: kv).load(), Session.none),
  ).wait;

  // Local notifications read the *current* settings and locale each time they are scheduled.
  late final ProviderContainer container;
  AppSettings current() => container.read(settingsProvider);
  final notifier = PluginLocalNotifier(
    copy: () {
      final t = lookupAppLocalizations(Locale(current().locale));
      final copy = NotificationCopy(t, current());
      return copy.of;
    },
    channelNames: () {
      final t = lookupAppLocalizations(Locale(current().locale));
      return {
        NotificationChannel.adhan: t.channelAdhan,
        NotificationChannel.reminders: t.channelReminders,
        NotificationChannel.challenge: t.channelChallenge,
        NotificationChannel.offers: t.channelOffers,
      };
    },
    timezone: () => current().placeOrDefault.timezone,
    adhanVoice: () => current().adhanVoice.name,
  );

  container = ProviderContainer(
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
      localNotificationsProvider.overrideWithValue(notifier),
      notificationTapsProvider.overrideWith((_) => notifier.taps),
      audioEngineProvider.overrideWithValue(JustAudioEngine()),
      filesDirProvider.overrideWithValue(getApplicationSupportDirectory),
      // Phase 2: pushServiceProvider (Firebase) and adSinksProvider (ad SDKs) — see README.
    ],
  );
  await Boot.step('consents', container.read(consentRepositoryProvider).load, null);
  container.read(apiClientProvider).onSessionExpired = () => container.read(authRepositoryProvider).signOut();

  // Plugin set-up the first frame doesn't need, in parallel. Both are idempotent and awaited again
  // by their first real use (scheduling a reminder, playing audio).
  final router = buildRouter(initialLocation: '/splash');
  final product = container.read(productAnalyticsProvider);
  final routes = RouteTracker(product);
  router.routerDelegate.addListener(() => routes.onLocation(router.routerDelegate.currentConfiguration.uri.path));
  AppLifecycleListener(onPause: () => unawaited(product.flush()));
  Boot.afterFirstFrame({
    'notifications': notifier.init,
    'audio': JustAudioEngine.init,
    'analytics': () async {
      product.start();
      await product.track(ProductEvent.appOpen);
    },
  });
  runApp(UncontrolledProviderScope(container: container, child: YaqeenApp(router: router)));
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
      scrollBehavior: const YqScrollBehavior(),
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
