import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/domain/annotations.dart';
import 'package:yaqeen/features/quran/domain/ayah_search.dart';
import 'package:yaqeen/features/quran/domain/khatma.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/ayah_results.dart';
import 'package:yaqeen/features/quran/presentation/khatma_screen.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/quran_index_screen.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final index = AyahSearchIndex.buildSync(q);
  final now = DateTime.utc(2026, 10, 20, 12);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  List<Override> base() => [
        clockProvider.overrideWithValue(() => now),
        quranDataProvider.overrideWith((_) async => q),
        ayahSearchIndexProvider.overrideWith((_) async => index),
      ];

  Future<void> leave(WidgetTester tester) async {
    // Dispose the reader so its timers (chrome auto-hide, wird counter) don't outlive the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('index: an Arabic phrase finds ayat, lit, in everyday spelling', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(harness(const Scaffold(body: QuranIndexScreen()), overrides: base()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الحي القيوم');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.textContaining('في الآيات'), findsOneWidget);
    expect(find.textContaining('سورة البقرة · الآية 255'), findsWidgets);
  });

  testWidgets('reader: a focused ayah is lit; the title opens «انتقل إلى» and jumps', (tester) async {
    size(tester, const Size(390, 844));
    final kv = MemoryKvStore();
    await tester.pumpWidget(
      harness(
        const ReaderScreen(initialPage: 42, focus: AyahRef(2, 255)),
        kv: kv,
        overrides: [...base(), initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true))],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
    expect(page.selected, const AyahRef(2, 255));

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    expect(find.text('انتقل إلى'), findsOneWidget);
    await tester.tap(find.text('الصفحة').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '300');
    await tester.tap(find.text('انتقل'));
    await tester.pumpAndSettle();
    expect(find.text('300 من 604'), findsWidgets);
    await leave(tester);
  });

  testWidgets('reader: memorise mode hides the ayat and a tap reveals one', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(
      harness(
        const ReaderScreen(initialPage: 1),
        overrides: [...base(), initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true))],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إخفاء الآيات'));
    await tester.pumpAndSettle();
    final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
    expect(page.memorise, MemoriseMode.ayat);
    expect(page.revealed, isEmpty);
    page.onAyahTap!(const AyahRef(1, 2));
    await tester.pump();
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).revealed, {const AyahRef(1, 2)});
    await leave(tester);
  });

  testWidgets('reader: two pages side by side on a wide screen', (tester) async {
    size(tester, const Size(1180, 820));
    await tester.pumpWidget(
      harness(
        const ReaderScreen(initialPage: 3),
        overrides: [...base(), initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true))],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final pages = tester.widgetList<MushafPage>(find.byType(MushafPage)).map((p) => p.page).toSet();
    expect(pages, containsAll([3, 4]));
    await leave(tester);
  });

  testWidgets('reader paints highlights and note markers from the device store', (tester) async {
    size(tester, const Size(390, 844));
    final kv = MemoryKvStore();
    final repo = ReadingRepository(LocalStore(kv));
    await repo.setHighlight(const AyahRef(1, 3), MarkColor.green);
    await repo.setNote(const AyahRef(1, 4), 'تدبّر', DateTime(2026));
    await tester.pumpWidget(
      harness(
        const ReaderScreen(initialPage: 1),
        kv: kv,
        overrides: [...base(), initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true))],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
    expect(page.annotations.highlights[const AyahRef(1, 3)], MarkColor.green);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    await leave(tester);
  });

  testWidgets('khatma: start a 30-day plan, see today\'s portion and status', (tester) async {
    size(tester, const Size(390, 844));
    final kv = MemoryKvStore();
    await tester.pumpWidget(harness(const KhatmaScreen(), kv: kv, overrides: base()));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد ختمة جارية'), findsOneWidget);
    await tester.tap(find.text('ابدأ ختمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 يوماً'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ابدأ'));
    await tester.pumpAndSettle();
    expect(find.text('حصّة اليوم'), findsOneWidget);
    expect(find.text('من الصفحة 1 إلى 21'), findsOneWidget);
    final plan = await ReadingRepository(LocalStore(kv)).khatma();
    expect(plan, isA<Khatma>());
    expect(plan!.targetDate, '2026-11-18');
  });
}
