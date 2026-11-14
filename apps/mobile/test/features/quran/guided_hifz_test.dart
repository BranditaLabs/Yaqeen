import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/hifz/domain/hifz_plan.dart';
import 'package:yaqeen/features/hifz/domain/review_scheduler.dart';
import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/quran_session.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/features/quran/presentation/session/active_session.dart';
import 'package:yaqeen/features/quran/presentation/session/quran_session_controller.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'one_page_fakes.dart';

/// A player with no recitation on the device: every open ends «unavailable».
class _SilentListen extends FakeListen {
  @override
  Future<void> open(int surah, {int? ayah, int? to, int? times, bool autoplay = true, Reciter? reciter, bool reload = false}) async {
    opened.add(AyahRef(surah, ayah ?? 1));
    state = state.copyWith(status: ListenStatus.unavailable, surah: surah, ayah: ayah ?? 1, playing: false);
  }
}

void main() {
  final q = loadQuran();
  final now = DateTime.utc(2026, 10, 20, 12);
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  const passage = Passage(114, 1, 5);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  Future<MemoryKvStore> withPlan(HifzPlan plan) async {
    final kv = MemoryKvStore();
    await LocalStore(kv).write('hifz', plan.toJson());
    return kv;
  }

  HifzPlan? planIn(MemoryKvStore kv) => HifzPlan.tryParse(jsonDecode(kv.data['db.hifz']!));

  Future<void> open(WidgetTester tester, Widget reader, MemoryKvStore kv, FakeListen listen) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        reader,
        kv: kv,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => q),
          mushafLayoutProvider.overrideWith((_) async => null),
          listenControllerProvider.overrideWith(() => listen),
          initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
  ReaderLayers layers(WidgetTester tester) => container(tester).read(quranSessionControllerProvider);
  QuranSession? session(WidgetTester tester) => container(tester).read(activeSessionProvider);

  testWidgets('guided hifz: listen ×3, repeat ×10 and the test tick themselves; the grade needs «تأكيد»', (tester) async {
    final kv = await withPlan(const HifzPlan(goal: HifzGoal.amma, perDay: 5));
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 604, session: 'hifz', passage: passage), kv, listen);

    // «استماع ×3»: the passage plays three times, the dock stays.
    expect(session(tester)!.stage, SessionStage.listen);
    expect(layers(tester).mode, QuranMode.listen);
    expect(listen.passages.last, (114, 1, 5, 3));
    expect(find.text('استماع ×3 · ×0 / 3'), findsOneWidget);
    listen.set(listen.state.copyWith(roundsDone: 3, loopEnded: true, playing: false));
    await tester.pumpAndSettle();
    expect(session(tester)!.stage, SessionStage.repeat);
    expect(planIn(kv)!.stepsFor(today), {0});

    // «تكرار ×10»: the passage shows; ten «كرّرت» end the stage.
    expect(layers(tester).mode, QuranMode.memorise);
    expect(layers(tester).revealed, passage.range.toSet());
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.textContaining('كرّرت ×').first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(session(tester)!.stage, SessionStage.test);
    expect(planIn(kv)!.stepsFor(today), {0, 1});

    // «اختبار» without a recitation model: every other word hidden, a tap reveals.
    final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
    expect(page.memorise, MemoriseMode.words);
    expect(page.revealed, isEmpty);
    await tester.tap(find.text('انتهيت'));
    await tester.pumpAndSettle();
    expect(find.text('اقتراح: متقنة · يوم'), findsOneWidget);
    expect(planIn(kv)!.portions, isEmpty, reason: 'nothing is saved before «تأكيد»');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    final plan = planIn(kv)!;
    expect(plan.portions.single.id, '114:1-5');
    expect(plan.stepsFor(today), {0, 1, 2});
    expect(find.text('أتممت جلستك'), findsOneWidget);
    expect(kv.data.containsKey(QuranSessionStore.kvKey), isFalse);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    await leave(tester);
  });

  testWidgets('a due review opens at the test; leaving asks for the grade, reveals lower it', (tester) async {
    final kv = await withPlan(
      HifzPlan(
        goal: HifzGoal.amma,
        perDay: 5,
        portions: [
          HifzPortion(
            surah: 114,
            from: 1,
            to: 5,
            memorisedOn: today.subtract(const Duration(days: 1)),
            review: ReviewState(intervalDays: 1, due: today),
          ),
        ],
      ),
    );
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 604, session: 'review', passage: passage, portion: '114:1-5'), kv, listen);
    expect(session(tester)!.stage, SessionStage.test);
    expect(listen.passages, isEmpty, reason: 'a review starts at the test, not with listening');
    tester.widget<MushafPage>(find.byType(MushafPage).first).onAyahTap!(const AyahRef(114, 2));
    await tester.pump();
    expect(session(tester)!.reveals, {const AyahRef(114, 2)});

    await tester.tap(find.byTooltip('الخروج إلى الفهرس'));
    await tester.pumpAndSettle();
    expect(find.text('اقتراح: جيدة · 3 أيام'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(planIn(kv)!.portions.single.review.intervalDays, 3);
    expect(find.text('أتممت جلستك'), findsOneWidget);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    await leave(tester);
  });

  testWidgets('resuming a halaqa after «حفظت» on the hifz screen does not record the next, unstudied portion', (tester) async {
    // «حفظت» recorded today's passage while the halaqa waited at its test.
    final kv = await withPlan(const HifzPlan(goal: HifzGoal.amma, perDay: 5).memorise(q, today));
    await QuranSessionStore(kv).save(
      QuranSession.start(
        QuranSessionKind.hifz,
        passage,
        now: now,
        day: Zoned.isoDate(today),
        page: 604,
        planKey: 'hifz/amma/5',
        portion: passage.toString(),
      ).advance().advance(),
    );
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 604, session: 'resume'), kv, listen);
    expect(session(tester)!.stage, SessionStage.test);
    await tester.tap(find.text('انتهيت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(planIn(kv)!.portions.map((p) => p.id), ['114:1-5'], reason: '114:6 was never studied');
    expect(find.text('أتممت جلستك'), findsOneWidget);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    await leave(tester);
  });

  testWidgets('a new halaqa asks before replacing another surah\'s recitation; kept, it offers listening or «تخطَّ إلى التكرار»', (tester) async {
    final kv = await withPlan(const HifzPlan(goal: HifzGoal.amma, perDay: 5));
    final listen = FakeListen(const ListenState(status: ListenStatus.ready, surah: 18, ayah: 10, playing: true, synced: true));
    await open(tester, const ReaderScreen(initialPage: 604, session: 'hifz', passage: passage), kv, listen);
    await tester.pumpAndSettle();
    expect(find.text('استبدال التشغيل الحالي؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(listen.passages, isEmpty, reason: 'the recitation of al-Kahf keeps playing');
    expect(listen.state.surah, 18);
    expect(session(tester)!.stage, SessionStage.listen);
    expect(find.text('تخطَّ إلى التكرار'), findsOneWidget);
    // Listening after all: the passage plays its three rounds.
    await tester.tap(find.text('استماع ×3'));
    await tester.pumpAndSettle();
    expect(listen.passages.last, (114, 1, 5, 3));
    expect(find.text('تخطَّ إلى التكرار'), findsNothing);
    await leave(tester);
  });

  testWidgets('no recitation on the device: «تنزيل السورة» is not possible without a reciter, «تخطَّ إلى التكرار» is', (tester) async {
    final kv = await withPlan(const HifzPlan(goal: HifzGoal.amma, perDay: 5));
    final listen = _SilentListen();
    await open(tester, const ReaderScreen(initialPage: 604, session: 'hifz', passage: passage), kv, listen);
    await tester.pump();
    expect(find.text('لا تلاوة على الجهاز'), findsOneWidget);
    await tester.tap(find.text('تخطَّ إلى التكرار'));
    await tester.pumpAndSettle();
    expect(session(tester)!.stage, SessionStage.repeat);
    expect(planIn(kv)!.stepsFor(today), isEmpty, reason: 'skipping listening does not tick it');
    await leave(tester);
  });

  testWidgets('by voice: each full recitation counts in «تكرار ×10», the test listens, its card leads to the grade', (tester) async {
    final kv = await withPlan(const HifzPlan(goal: HifzGoal.amma, perDay: 5));
    await kv.write('recite.rationaleSeen', '1');
    final listen = FakeListen();
    final engine = ScriptedRecitationEngine();
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const ReaderScreen(initialPage: 604, session: 'hifz', passage: passage),
        kv: kv,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => q),
          mushafLayoutProvider.overrideWith((_) async => null),
          listenControllerProvider.overrideWith(() => listen),
          recitationEngineProvider.overrideWithValue(engine),
          initialConfigProvider.overrideWithValue(RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.recite] = true)),
          initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    listen.set(listen.state.copyWith(roundsDone: 3, loopEnded: true, playing: false));
    await tester.pumpAndSettle();
    expect(session(tester)!.stage, SessionStage.repeat);
    expect(engine.listening, isTrue, reason: 'the microphone counts repetitions by itself');
    expect(find.text('يستمع لتكرارك'), findsOneWidget);

    final full = [for (final r in passage.range) q.text(r)].join(' ');
    var heard = '';
    for (var i = 1; i <= 10; i++) {
      heard = '$heard $full'.trim();
      engine.emit(heard);
      await tester.pump();
      if (i < 10) expect(layers(tester).repeats, i);
    }
    await tester.pumpAndSettle();
    expect(session(tester)!.stage, SessionStage.test);
    expect(planIn(kv)!.stepsFor(today), {0, 1});

    // «اختبار» is the recite layer: hidden words revealed by the voice.
    expect(layers(tester).mode, QuranMode.recite);
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).recite, isNotNull);
    await tester.tap(find.bySemanticsLabel('ابدأ التسميع').first);
    await tester.pumpAndSettle();
    engine.emit(full);
    await tester.pumpAndSettle();
    expect(find.text('أتممت التسميع'), findsOneWidget);
    await tester.tap(find.text('متابعة إلى التقييم'));
    await tester.pumpAndSettle();
    expect(find.text('اقتراح: متقنة · يوم'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(planIn(kv)!.portions.single.id, '114:1-5');
    expect(find.text('أتممت جلستك'), findsOneWidget);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();
    await leave(tester);
  });
}
