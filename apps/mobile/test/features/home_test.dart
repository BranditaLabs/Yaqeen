import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/calendar/data/hijri_today.dart';
import 'package:yaqeen/features/calendar/domain/hijri_day.dart';
import 'package:yaqeen/features/home/home_screen.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/wird.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  Future<void> pump(WidgetTester tester, DateTime now, {DateTime Function()? clock, String locale = 'ar', List<Override> extra = const []}) async {
    tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: HomeScreen()),
        skyClock: clock ?? () => now,
        locale: locale,
        overrides: [
          clockProvider.overrideWithValue(clock ?? () => now),
          ...extra,
          initialSettingsProvider.overrideWithValue(AppSettings(place: Place.cairo, locale: locale)),
          quranDataProvider.overrideWith((_) async => q),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Tuesday 15:00 Cairo: evening greeting, Asr next with countdown, guest join CTA', (tester) async {
    await pump(tester, DateTime.utc(2026, 10, 20, 12));
    expect(find.text('مساء الخير'), findsOneWidget);
    expect(find.text('ضيف'), findsOneWidget);
    expect(find.text('العصر'), findsWidgets);
    expect(find.text('3:53 م · الأذان بعد'), findsOneWidget);
    expect(find.text('00:53:00'), findsOneWidget);
    expect(find.text('ابدأ القراءة'), findsOneWidget);
    expect(find.text('0 / 2 صفحات'), findsNWidgets(2)); // wird orb + the Quran stop in «Your day»
    // «Your day»: the challenge closes the timeline.
    await tester.scrollUntilVisible(find.text('ابدأ رحلة 365 يوماً'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('ابدأ رحلة 365 يوماً'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('morning before Dhuhr; at adhan time the hero says «حان وقت صلاة»', (tester) async {
    await pump(tester, DateTime.utc(2026, 10, 20, 12, 55)); // Asr 15:53 Cairo = 12:53 UTC
    expect(find.text('حان وقت صلاة العصر'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, DateTime.utc(2026, 10, 20, 5));
    expect(find.text('صباح الخير'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left open across Dhuhr, the greeting turns to evening', (tester) async {
    var now = DateTime.utc(2026, 10, 20, 9, 30); // 12:30 Cairo, Dhuhr ≈ 12:40
    await pump(tester, now, clock: () => now);
    expect(find.text('صباح الخير'), findsOneWidget);
    now = DateTime.utc(2026, 10, 20, 10);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('مساء الخير'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('left open past midnight, the wird orb drops the day before', (tester) async {
    var now = DateTime.utc(2026, 10, 20, 20, 50); // 23:50 Cairo
    await pump(
      tester,
      now,
      clock: () => now,
      extra: [todayWirdProvider.overrideWith((_) async => const WirdDay(date: '2026-10-20', pages: {1, 2}))],
    );
    await tester.pump();
    expect(find.text('اكتمل وردك'), findsOneWidget);
    now = DateTime.utc(2026, 10, 20, 21, 5); // 00:05 the next day
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('اكتمل وردك'), findsNothing);
    expect(find.text('0 / 2 صفحات'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in English the Hijri month is named in English', (tester) async {
    const h = HijriDay(gregorian: '2026-10-20', hijriDay: 8, hijriMonth: 5, hijriYear: 1448, monthNameAr: 'جمادى الأولى', weekday: 2);
    await pump(tester, DateTime.utc(2026, 10, 20, 12), locale: 'en', extra: [hijriTodayProvider.overrideWith((_) async => h)]);
    await tester.pump();
    expect(find.textContaining('8 Jumada al-Ula 1448'), findsOneWidget);
    expect(find.textContaining('جمادى'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Friday suggests al-Kahf', (tester) async {
    await pump(tester, DateTime.utc(2026, 10, 23, 7));
    expect(find.text('الجمعة: سورة الكهف'), findsOneWidget);
    expect(find.text('سورة الكهف · الصفحة 293 · الجزء 15'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the page light follows the sun across the day (mirrored in RTL)', (tester) async {
    double sunGlowX() {
      final glow = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byKey(const ValueKey('sky-light')), matching: find.byType(DecoratedBox)))
          .map((b) => (b.decoration as BoxDecoration).gradient)
          .whereType<RadialGradient>()
          .first;
      return (glow.center as Alignment).x;
    }

    await pump(tester, DateTime.utc(2026, 10, 20, 4)); // 07:00 Cairo, after Fajr
    await tester.pump(const Duration(seconds: 2));
    final morning = sunGlowX();
    await tester.pumpWidget(const SizedBox());
    await pump(tester, DateTime.utc(2026, 10, 20, 15, 30)); // 18:30 Cairo, after Maghrib
    await tester.pump(const Duration(seconds: 2));
    final evening = sunGlowX();
    // Arabic: the day starts on the right (x > 0) and moves left.
    expect(morning, greaterThan(evening));
    await tester.pumpWidget(const SizedBox());
  });
}
