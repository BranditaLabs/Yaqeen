import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
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
