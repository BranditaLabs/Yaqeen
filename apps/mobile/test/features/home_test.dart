import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/home/home_screen.dart';
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

  Future<void> pump(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: HomeScreen()),
        overrides: [
          clockProvider.overrideWithValue(() => now),
          initialSettingsProvider.overrideWithValue(const AppSettings(place: Place.cairo)),
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
    expect(find.text('0 / 2 صفحات'), findsOneWidget);
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

  testWidgets('Friday suggests al-Kahf', (tester) async {
    await pump(tester, DateTime.utc(2026, 10, 23, 7));
    expect(find.text('الجمعة: سورة الكهف'), findsOneWidget);
    expect(find.text('سورة الكهف · الصفحة 293 · الجزء 15'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
