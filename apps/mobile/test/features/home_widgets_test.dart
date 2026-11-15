import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/design/motion.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/widgets/yq_avatar.dart';
import 'package:yaqeen/core/widgets/yq_ring.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/challenge/domain/challenge_models.dart';
import 'package:yaqeen/features/challenge/presentation/challenge_controller.dart';
import 'package:yaqeen/features/home/widgets/profile_chip.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/presentation/me_profile_controller.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';
import 'package:yaqeen/core/platform/location_service.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/floating_tab_bar.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';
import 'package:yaqeen/features/home/data/tasbeeh_controller.dart';
import 'package:yaqeen/features/home/home_screen.dart';
import 'package:yaqeen/features/home/widgets/orbs.dart';
import 'package:yaqeen/core/design/living_sky.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

/// The challenge summary that never arrives (an account's first load with nothing cached).
class _PendingChallenge extends ChallengeController {
  @override
  Future<ChallengeSummary> build() => Completer<ChallengeSummary>().future;
}

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  Widget tile(Widget child, {List<Override> overrides = const [], MemoryKvStore? kv}) => harness(
        Scaffold(body: Center(child: SizedBox(width: 180, child: child))),
        kv: kv,
        overrides: [initialSettingsProvider.overrideWithValue(const AppSettings(place: Place.cairo)), ...overrides],
      );

  group('Qibla orb', () {
    testWidgets('live: follows the compass and says when the phone faces the Qibla', (tester) async {
      final headings = StreamController<HeadingReading>();
      addTearDown(headings.close);
      await tester
          .pumpWidget(tile(const QiblaOrb(), overrides: [compassServiceProvider.overrideWithValue(FakeCompassService(headings.stream))]));
      // Cairo → Kaaba ≈ 136°.
      headings.add(const HeadingReading(100));
      await tester.pumpAndSettle();
      expect(find.text('استدر يميناً'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('بوصلة مباشرة')), findsOneWidget); // live dot, announced
      headings.add(const HeadingReading(136));
      await tester.pumpAndSettle();
      expect(find.text('أنت في اتجاه القبلة'), findsOneWidget);
      headings.add(const HeadingReading(200));
      await tester.pumpAndSettle();
      expect(find.text('استدر يساراً'), findsOneWidget);
    });

    testWidgets('no compass: shows the bearing from north', (tester) async {
      await tester.pumpWidget(tile(const QiblaOrb(), overrides: [compassServiceProvider.overrideWithValue(FakeCompassService())]));
      await tester.pumpAndSettle();
      expect(find.text('136°'), findsOneWidget); // centre of the orb
      expect(find.text('136° من الشمال'), findsOneWidget); // status: the ring's top is north
    });

    testWidgets('stops listening while its tab is hidden', (tester) async {
      var listeners = 0;
      final headings = StreamController<HeadingReading>.broadcast(onListen: () => listeners++, onCancel: () => listeners--);
      addTearDown(headings.close);
      Widget at(bool enabled) => tile(
            TickerMode(enabled: enabled, child: const QiblaOrb()),
            overrides: [compassServiceProvider.overrideWithValue(FakeCompassService(headings.stream))],
          );
      await tester.pumpWidget(at(true));
      expect(listeners, 1);
      await tester.pumpWidget(at(false));
      expect(listeners, 0);
      await tester.pumpWidget(at(true));
      expect(listeners, 1);
    });
  });

  testWidgets('tasbeeh orb: tap counts, the count persists, hold resets', (tester) async {
    final kv = MemoryKvStore();
    await tester.pumpWidget(tile(const TasbeehOrb(), kv: kv));
    await tester.pump();
    for (var i = 0; i < 34; i++) {
      await tester.tap(find.byType(TasbeehOrb));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('34'), findsOneWidget);
    expect(find.text('الدورة 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // debounced save
    expect(kv.data[TasbeehController.key], '34');

    await tester.longPress(find.byType(TasbeehOrb));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // toast gone, save done
    expect(find.text('0'), findsOneWidget);
    expect(kv.data[TasbeehController.key], '0');
  });

  testWidgets('a saved count is restored on start', (tester) async {
    final kv = MemoryKvStore()..data[TasbeehController.key] = '99';
    await tester.pumpWidget(tile(const TasbeehOrb(), kv: kv));
    await tester.pumpAndSettle();
    expect(find.text('99'), findsOneWidget);
    expect(find.text('الدورة 4'), findsOneWidget);
  });

  group('living sky palette', () {
    final d = DateTime.utc(2026, 10, 20);
    DateTime h(double hours) => d.add(Duration(minutes: (hours * 60).round()));
    final keys = skyKeyframes(
      previousIsha: h(-5),
      fajr: h(2.5),
      sunrise: h(4),
      dhuhr: h(9.7),
      asr: h(12.9),
      maghrib: h(15.3),
      isha: h(16.6),
      nextFajr: h(26.5),
    );

    test('each keyframe shows its own palette', () {
      expect(skyPaletteAt(keys, h(2.5)), SkyPalette.dawn);
      expect(skyPaletteAt(keys, h(12.9)), SkyPalette.golden);
      expect(skyPaletteAt(keys, h(16.6)), SkyPalette.night);
    });

    test('between keyframes it blends continuously (no steps)', () {
      final mid = skyPaletteAt(keys, h((12.9 + 15.3) / 2));
      expect(mid, SkyPalette.lerp(SkyPalette.golden, SkyPalette.dusk, 0.5));
      final a = skyPaletteAt(keys, h(13.0));
      final b = skyPaletteAt(keys, h(13.1));
      expect(a == b, isFalse); // six minutes later the light has moved a little
    });

    test('before Fajr it is still night, easing into dawn', () {
      expect(skyPaletteAt(keys, h(-5)), SkyPalette.night);
      expect(skyPaletteAt(keys, h(2.4)) == SkyPalette.night, isFalse);
    });

    test('the sun x is mirrored in RTL', () {
      expect(skyX(0.25, rtl: false), closeTo(-0.5, 1e-9));
      expect(skyX(0.25, rtl: true), closeTo(0.5, 1e-9));
    });
  });

  group('profile chip and one-time moments (§5.9)', () {
    const google = Session(provider: SignInProvider.google, userId: 'u1', displayName: 'Ahmed Hamdy');
    const guest = Session(provider: SignInProvider.guest, userId: 'g1');
    final profileJson = File('test/fixtures/community/me_profile.json').readAsStringSync(); // «أحمد», level 3 · مواظب, 40%
    late List<String> calls;

    setUp(() => calls = []);

    /// Home inside a router (so the chip can go to /profile), with an API that is always offline.
    Widget home({
      required MemoryKvStore kv,
      Session session = google,
      List<Override> extra = const [],
      GoRouter? router,
    }) {
      final r = router ??
          GoRouter(
            initialLocation: '/home',
            routes: [
              GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: HomeScreen())),
              GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('PROFILE'))),
            ],
          );
      return ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          skyClockProvider.overrideWithValue(fixedSkyClock),
          clockProvider.overrideWithValue(fixedSkyClock),
          initialSettingsProvider.overrideWithValue(const AppSettings(place: Place.cairo)),
          initialSessionProvider.overrideWithValue(session),
          quranDataProvider.overrideWith((_) async => q),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              baseUrl: 'https://api.test',
              tokens: ref.watch(tokenStoreProvider),
              client: MockClient((req) async {
                calls.add('${req.method} ${req.url.path}');
                throw http.ClientException('offline');
              }),
            ),
          ),
          ...extra,
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: YqTheme.light(),
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: r,
        ),
      );
    }

    Future<void> open(WidgetTester tester, Widget app) async {
      tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3)); // toasts and the glint finish
      await tester.pumpWidget(const SizedBox());
    }

    Finder chip(String label) =>
        find.descendant(of: find.byType(ProfileChip), matching: find.bySemanticsLabel(label));

    testWidgets('the chip paints from the cached profile while the API is offline', (tester) async {
      final kv = MemoryKvStore()..data[ProfileRepository.meKey] = profileJson;
      await open(tester, home(kv: kv));
      expect(chip('أحمد، المستوى 3 · مواظب، 40%'), findsOneWidget);
      final ring = tester.widget<YqLevelAvatar>(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar)));
      expect(ring.level, 3);
      expect(ring.size, 48);
      expect(ring.showLevel, isTrue);
      expect(ring.achieved, isFalse); // lapis: gold only for the glint or the top level
      expect(find.text('أحمد'), findsWidgets); // the header greets with the profile name
      expect(calls, contains('GET /v1/me/profile')); // tried in the background, never awaited
      await close(tester);
    });

    testWidgets('tapping the chip opens /profile', (tester) async {
      final kv = MemoryKvStore()..data[ProfileRepository.meKey] = profileJson;
      await open(tester, home(kv: kv));
      await tester.tap(find.byType(ProfileChip));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a guest gets the avatar without a ring and «افتح ملفّك»', (tester) async {
      await open(tester, home(kv: MemoryKvStore(), session: guest));
      expect(chip('ضيف، افتح ملفّك'), findsOneWidget);
      expect(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar)), findsNothing);
      expect(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqAvatar)), findsOneWidget);
      await close(tester);
    });

    testWidgets('the top level («منارة») is the only resting gold ring', (tester) async {
      final top = (jsonDecode(profileJson) as Map)
        ..['level'] = {'level': 6, 'nameAr': 'منارة', 'nameEn': 'Beacon', 'progress': 1, 'nextAt': null};
      final kv = MemoryKvStore()
        ..data[ProfileRepository.meKey] = jsonEncode(top)
        ..data[ProfileRepository.lastSeenLevelKey] = '6';
      await open(tester, home(kv: kv));
      final ring = tester.widget<YqLevelAvatar>(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar)));
      expect(ring.achieved, isTrue);
      await close(tester);
    });

    testWidgets('an account whose challenge summary is still loading sees a skeleton, not the join CTA', (tester) async {
      final kv = MemoryKvStore()..data[ProfileRepository.meKey] = profileJson;
      await open(tester, home(kv: kv, extra: [challengeControllerProvider.overrideWith(_PendingChallenge.new)]));
      await tester.scrollUntilVisible(find.text('خطة الحفظ'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('ابدأ رحلة 365 يوماً'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is YqSkeletonBox && w.height == 72 && w.radius == 24),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('the week result shows on Home once per app open, and then no level-up toast', (tester) async {
      final kv = MemoryKvStore()
        ..data[ProfileRepository.meKey] = profileJson
        ..data[ProfileRepository.lastSeenLevelKey] = '2'; // a level-up is owed too
      var asked = 0;
      // Stands in for the competitions stream's sheet: once per finished week (KV community.seenWeek).
      Future<bool> weekResult(BuildContext context, WidgetRef ref) async {
        asked++;
        final week = ref.read(meProfileProvider).valueOrNull?.league?.lastWeek;
        final kv = ref.read(kvStoreProvider);
        if (week == null || await kv.read('community.seenWeek') == week.startsOn) return false;
        await kv.write('community.seenWeek', week.startsOn);
        if (!context.mounted) return false;
        await showYqSheet<void>(context, builder: (_) => const Text('انتهى الأسبوع'));
        return true;
      }

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: HomeScreen())),
          GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('PROFILE'))),
        ],
      );
      await open(tester, home(kv: kv, router: router, extra: [homeWeekResultProvider.overrideWithValue(weekResult)]));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
      expect(asked, 1);
      expect(find.text('بلغت مستوى مواظب'), findsNothing); // at most one moment per open
      await tester.tapAt(const Offset(20, 40)); // dismiss the sheet
      await tester.pump(const Duration(milliseconds: 500));

      // Home again in the same app open (e.g. back from Profile): nothing more.
      router.go('/profile');
      await tester.pumpAndSettle();
      router.go('/home');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('انتهى الأسبوع'), findsNothing);
      expect(asked, 1);
      expect(find.text('بلغت مستوى مواظب'), findsNothing);
      expect(kv.data[ProfileRepository.lastSeenLevelKey], '2'); // still owed, for the next moment
      await close(tester);
    });

    testWidgets('the chip ring draws in once (600 ms); under reduce-motion it is there at once', (tester) async {
      final kv = MemoryKvStore()..data[ProfileRepository.meKey] = profileJson;
      await open(tester, home(kv: kv));
      final chipRing = find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar));
      expect(tester.widget<YqLevelAvatar>(chipRing).drawIn, Motion.ringDrawSmall);
      await close(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final kv2 = MemoryKvStore()
        ..data[ProfileRepository.meKey] = profileJson
        ..data[ProfileRepository.lastSeenLevelKey] = '2';
      await open(tester, home(kv: kv2));
      await tester.pump(const Duration(milliseconds: 100));
      // The level-up toast comes at once, with no light sweep to wait for.
      expect(find.text('بلغت مستوى مواظب'), findsOneWidget);
      final ring = find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqRing));
      expect(find.descendant(of: ring, matching: find.byType(CustomPaint)), findsOneWidget); // no glint layer
      await tester.pumpAndSettle(); // nothing keeps ticking
      await close(tester);
    });

    testWidgets('a reached level glints the chip and toasts once, then is marked seen', (tester) async {
      final kv = MemoryKvStore()
        ..data[ProfileRepository.meKey] = profileJson
        ..data[ProfileRepository.lastSeenLevelKey] = '2';
      await open(tester, home(kv: kv));
      await tester.pump(const Duration(milliseconds: 100));
      final ring = tester.widget<YqLevelAvatar>(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar)));
      expect(ring.achieved, isTrue); // gold during the glint
      expect(ring.glint, isTrue); // the light sweeps round the chip once
      await tester.pump(const Duration(milliseconds: 50));
      expect(kv.data[ProfileRepository.lastSeenLevelKey], '3');
      // The quiet toast follows the light.
      await tester.pump(Motion.glint);
      expect(find.text('بلغت مستوى مواظب'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('بلغت مستوى مواظب'), findsNothing);
      final after = tester.widget<YqLevelAvatar>(find.descendant(of: find.byType(ProfileChip), matching: find.byType(YqLevelAvatar)));
      expect(after.achieved, isFalse); // back to lapis
      await tester.pumpWidget(const SizedBox());

      // The next app open: already seen.
      await open(tester, home(kv: kv));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('بلغت مستوى مواظب'), findsNothing);
      await close(tester);
    });

    testWidgets('neither moment holds up the first frame', (tester) async {
      final kv = MemoryKvStore()
        ..data[ProfileRepository.meKey] = profileJson
        ..data[ProfileRepository.lastSeenLevelKey] = '2';
      var asked = 0;
      bool? homeWasLaidOut;
      final never = Completer<bool>();
      tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        home(
          kv: kv,
          extra: [
            homeWeekResultProvider.overrideWithValue((context, __) {
              asked++;
              // Asked only once Home has been laid out and painted (after the first frame).
              final box = context.findRenderObject();
              homeWasLaidOut = box is RenderBox && box.hasSize && box.attached;
              return never.future;
            }),
          ],
        ),
      );
      // The first frame is Home itself: the hero is there whatever the moments do.
      expect(find.text('مساء الخير'), findsOneWidget);
      expect(find.text('العصر'), findsWidgets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked, 1);
      expect(homeWasLaidOut, isTrue);
      // A sheet that never answers keeps Home usable, and no toast jumps in front of it.
      expect(find.byType(ProfileChip), findsOneWidget);
      await tester.tap(find.byType(ProfileChip));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.text('بلغت مستوى مواظب'), findsNothing);
      never.complete(false);
      await close(tester);
    });
  });

  // Full-screen renders of the redesigned Home (also the screenshots shared for review).
  for (final locale in ['ar', 'en']) {
    testWidgets('home golden ($locale)', (tester) async {
      debugDisableShadows = false;
      tester.view.physicalSize = const Size(390 * 3, 1960 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final kv = MemoryKvStore()..data[TasbeehController.key] = '21';
      await tester.pumpWidget(
        harness(
          locale: locale,
          kv: kv,
          overrides: [
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)), // Tue 15:00 Cairo
            initialSettingsProvider.overrideWithValue(AppSettings(place: Place.cairo, locale: locale)),
            quranDataProvider.overrideWith((_) async => q),
            // Live compass, phone pointing a little left of the Qibla (≈136°).
            compassServiceProvider.overrideWithValue(FakeCompassService(Stream.value(const HeadingReading(126)))),
          ],
          Scaffold(
            extendBody: true,
            body: Stack(
              children: [
                const Positioned.fill(child: HomeScreen()),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: FloatingTabBar(
                    currentIndex: 0,
                    onSelect: (_) {},
                    tabs: [
                      YqTab(icon: YqIcons.home, label: locale == 'ar' ? 'الرئيسية' : 'Home'),
                      YqTab(icon: YqIcons.quran, label: locale == 'ar' ? 'القرآن' : 'Quran'),
                      YqTab(icon: YqIcons.prayer, label: locale == 'ar' ? 'الصلاة' : 'Prayer'),
                      YqTab(icon: YqIcons.challenge, label: locale == 'ar' ? 'التحدي' : 'Challenge'),
                      YqTab.avatar(initial: 'أ', label: locale == 'ar' ? 'حسابي' : 'Profile'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400)); // saved tasbeeh count loaded
      try {
        await expectLater(find.byType(Scaffold).first, matchesGoldenFile('../goldens/home_$locale.png'));
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
