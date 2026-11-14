import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:yaqeen/features/recite/presentation/recite_available.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'quran/one_page_fakes.dart';

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
    expect(find.text('ابدأ الحلقة'), findsOneWidget);
    // A ticked step is saved with today's date, so leaving the screen (e.g. to listen) keeps it.
    await tester.tap(find.text('استمع · 3 مرات'));
    await tester.pumpAndSettle();
    expect(kv.data['db.hifz'], contains('"steps"'));
    expect(find.text('أكمل الحلقة'), findsOneWidget, reason: 'a step ticked: the halaqa is under way');
    await tester.ensureVisible(find.text('حفظت مقطع اليوم'));
    await tester.tap(find.text('حفظت مقطع اليوم'));
    await tester.pumpAndSettle();
    expect(find.text('غداً'), findsOneWidget);
    // The card keeps today's passage (also listed for review tomorrow); the next one is a preview.
    expect(find.text('سورة الناس · الآيات 1–5'), findsNWidgets(2));
    expect(find.text('غداً: سورة الناس · الآيات 6–6'), findsOneWidget);
    expect(kv.data['db.hifz'], contains('"s":114'));

    // Next day: the passage is due.
    final tomorrow = now.add(const Duration(days: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      harness(const HifzScreen(), kv: kv, overrides: [...base(), clockProvider.overrideWithValue(() => tomorrow)].sublist(1).cast()),
    );
    await tester.pumpAndSettle();
    expect(find.text('مستحقة اليوم'), findsOneWidget);
    expect(find.text('حُفظت قبل يوم · آخر مراجعة قبل يوم'), findsOneWidget);
    expect(find.text('سورة الناس · الآيات 6–6'), findsOneWidget);
    expect(find.text('راجع'), findsOneWidget, reason: 'the review in the reader, at the test');
    await tester.ensureVisible(find.text('جيدة · 3 أيام'));
    await tester.tap(find.text('جيدة · 3 أيام'));
    await tester.pumpAndSettle();
    expect(find.text('اكتملت مراجعة اليوم'), findsOneWidget);
    expect(find.text('بعد 3 أيام'), findsOneWidget);
  });

  group('recite layer', () {
    final printed = loadQuran();

    List<Override> reader(FakeListen listen, RecitationEngine engine) => [
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => printed),
          mushafLayoutProvider.overrideWith((_) async => null),
          listenControllerProvider.overrideWith(() => listen),
          recitationEngineProvider.overrideWithValue(engine),
          initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
          initialConfigProvider.overrideWithValue(RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.recite] = true)),
        ];

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('no model on the device: no «تسميع» layer at all', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        harness(const ReaderScreen(initialPage: 40, mode: QuranMode.recite), overrides: reader(FakeListen(), const UnavailableRecitationEngine())),
      );
      await tester.pumpAndSettle();
      expect(find.text('تسميع'), findsNothing);
      expect(tester.widget<MushafPage>(find.byType(MushafPage).first).marks, isEmpty);
      await leave(tester);
    });

    testWidgets('recite where I am: page 40, listening paused first, rationale once, notes, a note plays once', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine();
      final listen = FakeListen(const ListenState(status: ListenStatus.ready, surah: 2, ayah: 250, playing: true, synced: true));
      final kv = MemoryKvStore();
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 40, mode: QuranMode.recite), kv: kv, overrides: reader(listen, engine)));
      await tester.pumpAndSettle();
      expect(listen.pauses, greaterThanOrEqualTo(1), reason: 'recitation pauses before the microphone');
      final passage = Passage.ofPage(printed, 40);
      expect(tester.widget<MushafPage>(find.byType(MushafPage).first).passage, passage);

      await tester.tap(find.bySemanticsLabel('ابدأ التسميع').first);
      await tester.pumpAndSettle();
      expect(find.text('نستمع لتلاوتك على جهازك فقط'), findsOneWidget);
      await tester.tap(find.widgetWithText(YqButton, 'ابدأ التسميع'));
      await tester.pumpAndSettle();
      expect(engine.listening, isTrue);
      expect(kv.data['recite.rationaleSeen'], '1');

      // The first ayah as written, the second with one word heard differently.
      final a1 = printed.text(passage.first);
      final a2 = printed.text(AyahRef(passage.surah, passage.from + 1)).split(' ');
      a2[1] = 'كلمة';
      engine.emit('$a1 ${a2.join(' ')}');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('2 آيات · 1 ملاحظات'), findsOneWidget);
      expect(find.textContaining('تنبيه:'), findsOneWidget);
      expect(find.textContaining('خطأ'), findsNothing);
      final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
      expect(page.marks, {AyahRef(passage.surah, passage.from + 1): {2}});

      // A note plays its ayah once.
      await tester.tap(find.textContaining('تنبيه:'));
      await tester.pump();
      expect(listen.passages.last, (passage.surah, passage.from + 1, passage.from + 1, 1));

      // «إظهار الآيات» off: the passage hides, the recited ayat stay revealed.
      await tester.tap(find.byType(YqSwitch));
      await tester.pump();
      final hidden = tester.widget<MushafPage>(find.byType(MushafPage).first);
      expect(hidden.memorise, MemoriseMode.ayat);
      expect(hidden.revealed, {passage.first, AyahRef(passage.surah, passage.from + 1)});
      await leave(tester);
    });
  });

  test('recite entries show only with the flag on and a model on the device', () async {
    Future<bool> entry({required bool flag, RecitationEngine? engine}) async {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          initialConfigProvider.overrideWithValue(RemoteConfig(features: {...RemoteConfig.defaultFeatures, Flags.recite: flag})),
          if (engine != null) recitationEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      c.listen(reciteEntryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      return c.read(reciteEntryProvider);
    }

    expect(await entry(flag: false, engine: ScriptedRecitationEngine()), isFalse);
    expect(await entry(flag: true), isFalse); // no model yet: no entry that leads to «not available»
    expect(await entry(flag: true, engine: ScriptedRecitationEngine()), isTrue);
  });
}
