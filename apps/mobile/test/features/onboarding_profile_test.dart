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
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/downloads_controller.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/onboarding/presentation/splash_gate.dart';
import 'package:yaqeen/features/onboarding/presentation/splash_screen.dart';
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
/// Records what the onboarding recitation switch asks for, without touching the network or disk.
class FakeDownloads extends DownloadsController {
  final started = <String>[];
  final cancelled = <String>[];

  @override
  Future<void> refresh(Iterable<Reciter> reciters) async {}

  @override
  Future<void> downloadAll(Reciter r) async {
    started.add(r.id);
    state = {...state, r.id: const ReciterDownload(surahs: 3, running: true)};
  }

  @override
  void cancel(String id) {
    cancelled.add(id);
    state = {...state, id: const ReciterDownload(surahs: 3)};
  }
}

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
      expect(routeForDeepLink(Uri.parse('https://yaqeenarabia.com/app/hifz')), '/quran/hifz');
      expect(routeForDeepLink(Uri.parse('https://yaqeenarabia.com/app/card')), '/profile/card');
      expect(routeForDeepLink(Uri(path: '/app/unknown')), '/home');
    });

    test('splash verse: the reviewed remote-config verse, else the bundled one with its caption', () {
      expect(splashVerseOf(const RemoteConfig()), (SplashScreen.bundledVerse, SplashScreen.bundledCaption));
      expect(splashVerseOf(const RemoteConfig(splashVerseAr: '  ', splashVerseRef: 'x')), (SplashScreen.bundledVerse, SplashScreen.bundledCaption));
      const other = 'فَٱصْبِرْ إِنَّ وَعْدَ ٱللَّهِ حَقٌّ';
      expect(splashVerseOf(const RemoteConfig(splashVerseAr: other, splashVerseRef: 'الروم: 60')), (other, 'الروم: 60'));
      // Gold only on «ٱلْيَقِينُ», and only when the verse has it.
      expect(SplashScreen.splitVerse(SplashScreen.bundledVerse), ('وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ', 'ٱلْيَقِينُ', ''));
      expect(SplashScreen.splitVerse(other), (other, '', ''));
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
        GoRoute(path: '/onboarding/routine', builder: (_, __) => const RoutineStep()),
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
    expect(switches.map((s) => s.properties.toggled), [true, true, false, false, false]);
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

    // 06 — routine: when each habit happens; choices stay on the device and drive the timeline.
    expect(find.text('متى يناسبك؟'), findsOneWidget);
    // Default: Quran 15 min after Fajr, previewed with today's real time («بعد الفجر · 5:48 ص»).
    expect(find.textContaining(RegExp(r'^بعد الفجر · \d{1,2}:\d{2} ص$')), findsOneWidget);
    await tester.tap(find.text('بعد المغرب').first); // Quran → after Maghrib
    await tester.pumpAndSettle();
    expect(find.textContaining('بعد المغرب ·'), findsOneWidget);
    await tester.tap(find.text('بعد العشاء').last); // dhikr → after Isha
    await tester.pumpAndSettle();
    expect(kv.data['settings.v1'], contains('"quranSlot":{"k":"after","p":"maghrib","m":15}'));
    expect(kv.data['settings.v1'], contains('"dhikrSlot":{"k":"after","p":"isha","m":15}'));
    expect(kv.data['settings.v1'], isNot(contains('quranSlot":{"k":"off')));
    await tester.tap(find.text('رتّب يومي'));
    await tester.pumpAndSettle();

    // 07 — reading works offline from the bundled text.
    expect(find.text('القرآن معك\nحتى دون اتصال'), findsOneWidget);
    await tester.tap(find.text('ابدأ الآن'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('HOME'), findsOneWidget);
    expect(kv.data['settings.v1'], contains('onboardingCompletedAt'));
  });

  group('welcome guest button', () {
    List<Override> server(MemoryKvStore kv, http.Response Function() signIn, {AppSettings settings = const AppSettings()}) => [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          initialSettingsProvider.overrideWithValue(settings),
          quranDataProvider.overrideWith((_) async => q),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              baseUrl: 'https://api.test',
              tokens: ref.watch(tokenStoreProvider),
              client: MockClient((req) async {
                calls.add('${req.method} ${req.url.path}');
                return signIn();
              }),
            ),
          ),
        ];

    Future<void> tapGuest(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('المتابعة كضيف'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3)); // toast in and out
      await tester.pumpAndSettle();
    }

    testWidgets('an API refusal shows the error toast and frees the buttons', (tester) async {
      final kv = MemoryKvStore();
      await tester.pumpWidget(app(server(kv, () => json({'error': {'code': 'bad_request'}}, 400))));
      await tapGuest(tester);
      expect(calls, contains('POST /v1/auth/sign-in'));
      expect(find.text('المتابعة كضيف'), findsOneWidget); // still on Welcome
      expect(kv.data['auth.session'], isNull);
      // Not stuck: a second tap goes out again.
      calls.clear();
      await tapGuest(tester);
      expect(calls, contains('POST /v1/auth/sign-in'));
    });

    testWidgets('a rate-limited or failing API continues as an offline guest', (tester) async {
      final kv = MemoryKvStore();
      await tester.pumpWidget(app(server(kv, () => http.Response('<html>502 Bad Gateway</html>', 502))));
      await tapGuest(tester);
      expect(find.text('لغتك ومصحفك'), findsOneWidget);
      expect(kv.data['auth.session'], contains('"pendingServer":true'));
    });

    testWidgets('after a sign-out an onboarded user goes home, not through onboarding again', (tester) async {
      final kv = MemoryKvStore();
      final done = AppSettings(onboardingCompletedAt: DateTime.utc(2026, 1, 1));
      await tester.pumpWidget(app(server(kv, () => http.Response('', 503), settings: done)));
      await tapGuest(tester);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  List<Override> offlineOverrides(MemoryKvStore kv) => [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
        quranDataProvider.overrideWith((_) async => q),
        localNotificationsProvider.overrideWithValue(NoopLocalNotificationScheduler()),
        deviceServicesProvider.overrideWithValue(FakeDeviceServices(isIOS: true)),
        apiClientProvider
            .overrideWith((ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: offline())),
      ];

  testWidgets('back (chevron and system back) steps back through onboarding, never to Home', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final kv = MemoryKvStore();
    await tester.pumpWidget(app(offlineOverrides(kv), initial: '/onboarding/download'));
    await tester.pumpAndSettle();
    expect(find.text('القرآن معك\nحتى دون اتصال'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('متى يناسبك؟'), findsOneWidget); // 06 → 05·ب
    expect(kv.data['settings.v1'], contains('"onboardingStep":5'));

    // Android back / iOS edge swipe: the same step back, the app stays open.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('وِردك اليومي'), findsOneWidget); // 05·ب → 05
    expect(kv.data['settings.v1'], contains('"onboardingStep":4'));

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('لغتك ومصحفك'), findsOneWidget); // … → 03
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('المتابعة كضيف'), findsOneWidget); // 03 → 02
    expect(find.text('HOME'), findsNothing);
    expect(kv.data['settings.v1'], contains('"onboardingStep":0'));
  });

  testWidgets('06: the optional recitation switch queues the default reciter (Wi-Fi only) and stops it', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fake = FakeDownloads();
    const alafasy = Reciter(id: 'alafasy', nameAr: 'مشاري العفاسي', nameEn: 'Mishary Alafasy', style: RecitationStyle.murattal, riwaya: 'hafs');
    await tester.pumpWidget(
      app(
        [
          ...offlineOverrides(MemoryKvStore()),
          recitersProvider.overrideWith((_) async => const [alafasy]),
          downloadsControllerProvider.overrideWith(() => fake),
        ],
        initial: '/onboarding/download',
      ),
    );
    await tester.pumpAndSettle();
    const label = 'تلاوة مشاري العفاسي · اختياري · عبر Wi-Fi فقط';
    expect(find.text(label), findsOneWidget);
    final toggle = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label && w.properties.toggled != null);
    expect(tester.widget<Semantics>(toggle).properties.toggled, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(fake.started, ['alafasy']);
    expect(tester.widget<Semantics>(toggle).properties.toggled, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(fake.cancelled, ['alafasy']);
    expect(tester.widget<Semantics>(toggle).properties.toggled, isFalse);
  });

  testWidgets('06: no recitation switch until the reciter catalogue resolves', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app([...offlineOverrides(MemoryKvStore()), recitersProvider.overrideWith((_) async => const <Reciter>[])], initial: '/onboarding/download'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('اختياري · عبر Wi-Fi فقط'), findsNothing);
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
