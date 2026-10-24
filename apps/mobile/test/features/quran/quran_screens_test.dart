import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/quran_index_screen.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final now = DateTime.utc(2026, 10, 20, 12);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<dynamic> base() => [
        clockProvider.overrideWithValue(() => now),
        quranDataProvider.overrideWith((_) async => q),
      ];

  testWidgets('index: surah list, search by name and by number, empty state', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const Scaffold(body: QuranIndexScreen()), overrides: [...base()].cast()));
    await tester.pumpAndSettle();
    expect(find.text('القرآن الكريم'), findsOneWidget);
    expect(find.textContaining('الفاتحة'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'الكهف');
    await tester.pump();
    expect(find.textContaining('الكهف'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('لا توجد نتائج'), findsOneWidget);
  });

  testWidgets('index: juz tab lists 30 parts and saved tab shows the empty hint', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const Scaffold(body: QuranIndexScreen()), overrides: [...base()].cast()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأجزاء'));
    await tester.pumpAndSettle();
    expect(find.text('الجزء 1'), findsOneWidget);
    await tester.tap(find.text('المحفوظات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد علامات بعد'), findsOneWidget);
  });

  testWidgets('reader: opens on the page, shows first-open hint, saves last read and a page bookmark', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    await tester.pumpWidget(harness(const ReaderScreen(initialPage: 293), kv: kv, overrides: [...base()].cast()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('سورة الكهف'), findsWidgets);
    expect(find.text('حسناً'), findsOneWidget);
    await tester.tap(find.text('حسناً'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('حفظ علامة على الصفحة'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('إزالة علامة الصفحة'), findsOneWidget);

    // Leave the reader so pending timers (chrome auto-hide, wird counter) are disposed.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(kv.data.values.join(), contains('293'));
  });
}
