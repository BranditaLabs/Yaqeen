import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/settings/settings_controller.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/presentation/onboarding_screens.dart';
import 'package:yaqeen/features/onboarding/presentation/splash_gate.dart';
import 'package:yaqeen/features/profile/presentation/profile_screen.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

final calls = <String>[];

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Offline server: every request fails like airplane mode.
http.Client offline() => MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      throw http.ClientException('offline');
    });

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() {
    YqGlassConfig.enableBlur = false;
    calls.clear();
  });

  group('splash routing', () {
    test('first launch → welcome; a killed onboarding resumes its step; then home or the deep link', () {
      expect(nextAfterSplash(const AppSettings()), '/onboarding/welcome');
      expect(nextAfterSplash(const AppSettings(onboardingStep: 3)), '/onboarding/consent');
      final done = AppSettings(onboardingCompletedAt: DateTime(2026));
      expect(nextAfterSplash(done), '/home');
      expect(nextAfterSplash(done, deepLink: '/challenge/calendar'), '/challenge/calendar');
    });

    test('a universal link path (as the OS hands it to the router) maps to its route', () {
      expect(routeForDeepLink(Uri(path: '/app/calendar')), '/challenge/calendar');
      expect(routeForDeepLink(Uri.parse('https://yaqin-brand.com/app/hifz')), '/quran/hifz');
      expect(routeForDeepLink(Uri(path: '/app/unknown')), '/home');
    });

    test('full choreography once a day, 1.2 s afterwards', () {
      expect(splashHold(const AppSettings(), '2026-10-20'), const Duration(milliseconds: 3800));
      expect(splashHold(const AppSettings(lastSplashDay: '2026-10-20'), '2026-10-20'), const Duration(milliseconds: 1200));
    });
  });

  /// Router over the onboarding steps so `context.go` works.
  Widget app(List<Override> overrides, {String initial = '/onboarding/welcome'}) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/onboarding/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(path: '/onboarding/language', builder: (_, __) => const LanguageStep()),
        GoRoute(path: '/onboarding/prayer', builder: (_, __) => const PrayerStep()),
        GoRoute(path: '/onboarding/consent', builder: (_, __) => const ConsentStep()),
        GoRoute(path: '/onboarding/goal', builder: (_, __) => const GoalStep()),
        GoRoute(path: '/onboarding/download', builder: (_, __) => const DownloadStep()),
        GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: YqTheme.light(),
          locale: Locale(ref.watch(settingsProvider.select((s) => s.locale))),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
  }

  testWidgets('guest with zero network walks every step to Home; defaults as the consent table', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final kv = MemoryKvStore();
    final notifier = NoopLocalNotificationScheduler();
    final device = FakeDeviceServices(isIOS: true);
    await tester.pumpWidget(
      app([
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
        quranDataProvider.overrideWith((_) async => q),
        localNotificationsProvider.overrideWithValue(notifier),
        deviceServicesProvider.overrideWithValue(device),
        apiClientProvider
            .overrideWith((ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: offline())),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('المتابعة كضيف'), findsOneWidget);
    await tester.tap(find.text('المتابعة كضيف'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // 03 — language: switch to English live, then back.
    expect(find.text('لغتك ومصحفك'), findsOneWidget);
    expect(find.text(q.basmala), findsOneWidget);
    expect(find.text('قريباً'), findsOneWidget);
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // 04 — prayer: no location yet, Egyptian method recommended by default.
    expect(find.text('مواقيت دقيقة لمكانك'), findsOneWidget);
    expect(find.text('الموصى بها لموقعك'), findsOneWidget);
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    // 04·ب — consent defaults: reminders + challenge ON, offers + ads OFF.
    expect(find.bySemanticsLabel('تذكيرات العبادة'), findsOneWidget);
    final switches = tester.widgetList<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.toggled != null)).toList();
    expect(switches.map((s) => s.properties.toggled), [true, true, false, false]);
    await tester.tap(find.text('متابعة'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(device.trackingRequests, 0); // ads stayed OFF → no ATT prompt
    expect(kv.data['consents.v1'], contains('"store_offers":false'));

    // 05 — goal: guest + join ON → sign-in sheet; «لاحقاً» keeps the guest and never calls enroll.
    expect(find.text('وِردك اليومي'), findsOneWidget);
    // The CTA spins while the sheet is up, so pump frames instead of settling.
    Future<void> frames() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await tester.tap(find.text('ابدأ رحلتي'));
    await frames();
    expect(find.text('سجّل الدخول لتحفظ نقاطك'), findsOneWidget);
    await tester.tap(find.text('لاحقاً'));
    await frames();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await frames();
    expect(calls.where((c) => c.contains('/challenge/enroll')), isEmpty);

    // 06 — reading works offline from the bundled text.
    expect(find.text('القرآن معك\nحتى دون اتصال'), findsOneWidget);
    await tester.tap(find.text('ابدأ الآن'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('HOME'), findsOneWidget);
    expect(kv.data['settings.v1'], contains('onboardingCompletedAt'));
  });

  testWidgets('profile: guest sees the sign-in CTA and no destructive rows', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        overrides: [initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.guest, pendingServer: true))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ضيف'), findsOneWidget);
    expect(find.text('سجّل الدخول لحفظ نقاطك'), findsOneWidget);
    expect(find.text('حذف الحساب'), findsNothing);
    expect(find.text('الخصوصية والموافقات'), findsOneWidget);
  });
}
