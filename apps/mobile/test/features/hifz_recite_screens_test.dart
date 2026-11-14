import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/asr/asr_model.dart';
import 'package:yaqeen/core/platform/asr/asr_model_store.dart';
import 'package:yaqeen/features/backup/presentation/backup_sync.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';
import 'package:yaqeen/features/recite/domain/recite_progress.dart';
import 'package:yaqeen/features/recite/presentation/asr_model_controller.dart';
import 'package:yaqeen/features/recite/presentation/recite_overlay.dart';
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

    List<Override> reader(FakeListen listen, RecitationEngine engine, {List<Override> extra = const []}) => [
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => printed),
          mushafLayoutProvider.overrideWith((_) async => null),
          listenControllerProvider.overrideWith(() => listen),
          recitationEngineProvider.overrideWithValue(engine),
          initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
          initialConfigProvider.overrideWithValue(RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.recite] = true)),
          ...extra,
        ];

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    MushafPage pageOf(WidgetTester tester) => tester.widget<MushafPage>(find.byType(MushafPage).first);

    Future<void> startReciting(WidgetTester tester, {bool rationale = true}) async {
      await tester.tap(find.bySemanticsLabel('ابدأ التسميع').first);
      await tester.pumpAndSettle();
      if (rationale) {
        expect(find.text('نستمع لتلاوتك على جهازك فقط'), findsOneWidget);
        await tester.tap(find.widgetWithText(YqButton, 'ابدأ التسميع'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('no model on the device: no «تسميع» layer at all', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        harness(const ReaderScreen(initialPage: 40, mode: QuranMode.recite), overrides: reader(FakeListen(), const UnavailableRecitationEngine())),
      );
      await tester.pumpAndSettle();
      expect(find.text('تسميع'), findsNothing);
      expect(pageOf(tester).recite, isNull);
      expect(pageOf(tester).marks, isEmpty);
      await leave(tester);
    });

    testWidgets('recite where I am: hidden words, revealed by the voice, notes, a note plays once', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine();
      final listen = FakeListen(const ListenState(status: ListenStatus.ready, surah: 2, ayah: 250, playing: true, synced: true));
      final kv = MemoryKvStore();
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 40, mode: QuranMode.recite), kv: kv, overrides: reader(listen, engine)));
      await tester.pumpAndSettle();
      expect(listen.pauses, greaterThanOrEqualTo(1), reason: 'recitation pauses before the microphone');
      final passage = Passage.ofPage(printed, 40);
      expect(pageOf(tester).passage, passage);
      // The passage is hidden at once: every word a pill until the voice reveals it.
      final view = pageOf(tester).recite!;
      expect(view.progress.ayat, passage.range);
      expect(view.progress.revealed(0), isFalse);
      expect(find.text('يتحقّق من الكلمات، لا من التجويد'), findsOneWidget);

      await startReciting(tester);
      expect(engine.listening, isTrue);
      expect(engine.lastLive, isTrue);
      expect(kv.data['recite.rationaleSeen'], '1');

      // The first ayah as written, the second with one word heard differently.
      final a1 = printed.text(passage.first);
      final a2 = printed.text(AyahRef(passage.surah, passage.from + 1)).split(' ');
      a2[1] = 'كلمة';
      final a3 = printed.text(AyahRef(passage.surah, passage.from + 2)).split(' ').first;
      engine.emit('$a1 ${a2.join(' ')} $a3');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('2 آيات · 1 ملاحظات · 0 مساعدات'), findsOneWidget);
      expect(find.textContaining('تنبيه:'), findsOneWidget);
      expect(find.textContaining('خطأ'), findsNothing);
      final page = pageOf(tester);
      expect(page.marks, {AyahRef(passage.surah, passage.from + 1): {2}});
      expect(page.recite!.progress.revealed(0), isTrue);

      // A note plays its ayah once from the reciter.
      await tester.tap(find.textContaining('تنبيه:'));
      await tester.pump();
      expect(listen.played.last, AyahRef(passage.surah, passage.from + 1));

      // «إظهار النص»: the hidden words show faintly for beginners.
      await tester.tap(find.byType(YqSwitch));
      await tester.pump();
      expect(pageOf(tester).recite!.showText, isTrue);
      await leave(tester);
    });

    testWidgets('help after a silence: the first letter at 4 s, the word at 8 s, counted once', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine();
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 40, mode: QuranMode.recite), overrides: reader(FakeListen(), engine)));
      await tester.pumpAndSettle();
      await startReciting(tester);
      final passage = Passage.ofPage(printed, 40);
      engine.emit(printed.text(passage.first).split(' ').first);
      await tester.pump();
      ReciteView view() => pageOf(tester).recite!;
      expect(view().progress.current, 1);
      await tester.pump(const Duration(seconds: 4, milliseconds: 250));
      expect(view().progress.hintOf(1), HintLevel.letter);
      await tester.pump(const Duration(seconds: 4));
      expect(view().progress.hintOf(1), HintLevel.word);
      expect(find.textContaining('· 1 مساعدات'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('the end: card with ayat · notes · helps · time; «سمّع الملاحظات فقط» retries the noted ayat', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine();
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 604, mode: QuranMode.recite), overrides: reader(FakeListen(), engine)));
      await tester.pumpAndSettle();
      await startReciting(tester);
      final passage = Passage.ofPage(printed, 604);
      final words = [for (final r in passage.range) printed.text(r)].join(' ').split(' ');
      words[2] = 'كلمة';
      engine.emit(words.join(' '));
      await tester.pumpAndSettle();
      expect(engine.listening, isFalse, reason: 'the passage recited to its end closes the microphone');
      expect(find.text('أتممت التسميع'), findsOneWidget);
      expect(find.text('ملاحظات'), findsOneWidget);
      expect(find.text('سمّع الملاحظات فقط'), findsOneWidget);
      expect(find.textContaining('خطأ'), findsNothing);
      await tester.tap(find.text('سمّع الملاحظات فقط'));
      await tester.pumpAndSettle();
      expect(engine.listening, isTrue);
      expect(engine.starts, 2);
      expect(pageOf(tester).recite!.progress.ayat, [passage.first], reason: 'only the noted ayah');
      await leave(tester);
    });

    testWidgets('a slow phone: «سمّع ثم تحقّق» — record, then every mark at once', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine(live: false);
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 604, mode: QuranMode.recite), overrides: reader(FakeListen(), engine)));
      await tester.pumpAndSettle();
      await startReciting(tester);
      expect(engine.lastLive, isFalse);
      expect(find.text('سمّع ثم تحقّق'), findsOneWidget);
      final passage = Passage.ofPage(printed, 604);
      engine.finalUpdate = RecognitionUpdate.text(printed.text(passage.first), isFinal: true);
      await tester.tap(find.text('إنهاء'));
      await tester.pumpAndSettle();
      expect(find.text('أتممت التسميع'), findsOneWidget);
      expect(pageOf(tester).recite!.progress.recitedAyat, 1);
      await leave(tester);
    });

    testWidgets('the model not on the phone yet: «تسميع» opens the calm sheet; it downloads, then recites', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine(available: false);
      final dir = Directory.systemTemp.createTempSync('asr-sheet');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows may still hold a handle for a moment; the OS temp folder is cleaned anyway.
        }
      });
      final bytes = utf8.encode('model');
      final manifest = AsrModelManifest(
        id: 'm',
        upstream: 'x',
        licence: 'Apache-2.0',
        baseUrl: 'https://cdn.test/',
        files: [
          for (final r in AsrFileRole.values) AsrModelFile(r, '${r.name}.bin', bytes: bytes.length, sha256: sha256.convert(bytes).toString()),
        ],
      );
      final store = AsrModelStore(
        root: () async => dir,
        kv: MemoryKvStore(),
        isUnmetered: () async => false,
        manifest: manifest,
        client: MockClient((_) async {
          engine.available = true;
          return http.Response.bytes(bytes, 200);
        }),
      );
      await tester.pumpWidget(
        harness(
          const ReaderScreen(initialPage: 40),
          overrides: reader(FakeListen(), engine, extra: [asrModelStoreProvider.overrideWithValue(store)]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('تسميع').first);
      await tester.pumpAndSettle();
      expect(find.text('يعمل دون إنترنت ولا يغادر صوتك جهازك'), findsOneWidget);
      expect(find.text('يتحقّق من الكلمات، لا من أحكام التجويد.'), findsOneWidget);
      // On mobile data: never without the user's own choice.
      await tester.tap(find.widgetWithText(YqButton, 'تنزيل'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.text('التنزيل عبر بيانات الجوال'), findsOneWidget);
      await tester.tap(find.text('التنزيل عبر بيانات الجوال'));
      // Files are hashed on background isolates: give them real time.
      for (var i = 0; i < 400 && find.text('يعمل دون إنترنت ولا يغادر صوتك جهازك').evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(ProviderScope.containerOf(tester.element(find.byType(ReaderScreen))).read(asrModelControllerProvider).ready, isTrue);
      expect(find.text('يعمل دون إنترنت ولا يغادر صوتك جهازك'), findsNothing);
      expect(pageOf(tester).recite, isNotNull, reason: 'the layer opened once the model was ready');
      await leave(tester);
    });

    testWidgets('privacy: a whole recitation makes no network call and touches no backed-up store', (tester) async {
      phone(tester);
      final engine = ScriptedRecitationEngine();
      final requests = <http.BaseRequest>[];
      final api = ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(MemoryKvStore()),
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('{}', 200);
        }),
      );
      final kv = MemoryKvStore();
      await tester.pumpWidget(
        harness(
          const ReaderScreen(initialPage: 604, mode: QuranMode.recite),
          kv: kv,
          overrides: reader(FakeListen(), engine, extra: [apiClientProvider.overrideWithValue(api)]),
        ),
      );
      await tester.pumpAndSettle();
      final before = {...kv.data.keys};
      final calls = requests.length;
      await startReciting(tester);
      final passage = Passage.ofPage(printed, 604);
      engine.emit([for (final r in passage.range) printed.text(r)].join(' '));
      await tester.pumpAndSettle();
      expect(find.text('أتممت التسميع'), findsOneWidget);
      expect(requests.skip(calls), isEmpty, reason: 'nothing heard ever leaves the phone');
      final written = kv.data.keys.toSet().difference(before);
      final container = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
      final adapters = container.read(backupAdaptersProvider);
      for (final key in [...written, QuranSessionStore.kvKey, 'recite.rationaleSeen', 'asr.liveSupport', 'asr.downloading']) {
        expect(adapters.where((a) => a.watches(key)), isEmpty, reason: '$key must never reach the cloud backup');
      }
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
