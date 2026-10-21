import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/core/widgets/yq_button.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/hifz/presentation/hifz_screen.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/presentation/recite_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final now = DateTime(2026, 10, 20, 12);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<dynamic> base({bool recite = false}) => [
        clockProvider.overrideWithValue(() => now),
        quranDataProvider.overrideWith((_) async => q),
        initialConfigProvider.overrideWithValue(
          RemoteConfig(features: {...RemoteConfig.defaultFeatures, Flags.recite: recite}),
        ),
      ];

  testWidgets('hifz: start a plan, memorise today, then rate the review the next day', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    await tester.pumpWidget(harness(const HifzScreen(), kv: kv, overrides: [...base()].cast()));
    await tester.pumpAndSettle();
    expect(find.text('خطة الحفظ'), findsOneWidget);
    await tester.tap(find.text('ابدأ خطة الحفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('خطتي'), findsOneWidget);
    expect(find.text('37 سورة · 564 آية'), findsOneWidget);
    await tester.tap(find.text('حفظ الخطة'));
    await tester.pumpAndSettle();

    expect(find.text('سورة الناس · الآيات 1–5'), findsOneWidget);
    expect(find.text('اكتملت مراجعة اليوم'), findsOneWidget);
    await tester.ensureVisible(find.text('حفظت مقطع اليوم'));
    await tester.tap(find.text('حفظت مقطع اليوم'));
    await tester.pumpAndSettle();
    expect(find.text('غداً'), findsOneWidget);
    expect(kv.data['db.hifz'], contains('"s":114'));

    // Next day: the passage is due.
    final tomorrow = now.add(const Duration(days: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      harness(const HifzScreen(), kv: kv, overrides: [...base(), clockProvider.overrideWithValue(() => tomorrow)].sublist(1).cast()),
    );
    await tester.pumpAndSettle();
    expect(find.text('مستحقة اليوم'), findsOneWidget);
    expect(find.text('سورة الناس · الآيات 6–6'), findsOneWidget);
    await tester.ensureVisible(find.text('جيدة · 3 أيام'));
    await tester.tap(find.text('جيدة · 3 أيام'));
    await tester.pumpAndSettle();
    expect(find.text('اكتملت مراجعة اليوم'), findsOneWidget);
    expect(find.text('بعد 3 أيام'), findsOneWidget);
  });

  testWidgets('recite: flag off falls back to the reader', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const ReciteScreen(surah: 1), overrides: [...base()].cast()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ابدأ التسميع'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('recite: unavailable model shows the notice', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const ReciteScreen(surah: 1), overrides: [...base(recite: true)].cast()));
    await tester.pumpAndSettle();
    expect(find.text('نموذج التسميع غير متاح بعد على هذا الجهاز'), findsOneWidget);
  });

  testWidgets('recite: rationale once, progressive reveal, ok count and a warning', (tester) async {
    phone(tester);
    final engine = ScriptedRecitationEngine();
    await tester.pumpWidget(
      harness(
        const ReciteScreen(surah: 1, from: 1, to: 3),
        overrides: [...base(recite: true), recitationEngineProvider.overrideWithValue(engine)].cast(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(YqSwitch));
    await tester.pump();
    // Hidden ayat: only the markers.
    expect(find.textContaining('ٱلرَّحِيمِ'), findsNothing);

    await tester.tap(find.bySemanticsLabel('ابدأ التسميع').first);
    await tester.pumpAndSettle();
    expect(find.text('نستمع لتلاوتك على جهازك فقط'), findsOneWidget);
    await tester.tap(find.widgetWithText(YqButton, 'ابدأ التسميع'));
    await tester.pumpAndSettle();
    expect(engine.listening, isTrue);

    expect(engine.listening, isTrue);
    engine.emit('بسم الله الرحمن الرحيم الحمد لله رب الناس');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('آيتان صحيحتان'), findsNothing); // ayah 2 has a warning
    expect(find.text('آية واحدة صحيحة'), findsOneWidget);
    expect(find.textContaining('تنبيه:'), findsOneWidget);
    expect(find.textContaining('خطأ'), findsNothing);
  });
}
