import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/app/routes/quran_routes.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/hifz/domain/hifz_plan.dart';
import 'package:yaqeen/features/home/widgets/continue_reading.dart';
import 'package:yaqeen/features/home/widgets/orbs.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/quran_session.dart';
import 'package:yaqeen/features/quran/domain/wird.dart';
import 'package:yaqeen/features/quran/presentation/session/quran_entry.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/features/quran/presentation/session/active_session.dart';
import 'package:yaqeen/features/quran/presentation/session/quran_session_controller.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'one_page_fakes.dart';

void main() {
  final q = loadQuran();
  final now = DateTime.utc(2026, 10, 20, 12);
  const today = '2026-10-20';

  group('QuranSession', () {
    test('hifz starts at «استماع ×3» and walks listen → repeat → test → done; review starts at the test', () {
      final s = QuranSession.start(QuranSessionKind.hifz, const Passage(114, 1, 6), now: now, day: today);
      expect(s.stage, SessionStage.listen);
      expect(s.stage.hifzStep, 0);
      final repeat = s.withRound(2).advance();
      expect(repeat.stage, SessionStage.repeat);
      expect(repeat.round, 0, reason: 'each stage counts its own rounds');
      expect(repeat.advance().stage, SessionStage.test);
      expect(repeat.advance().advance().finished, isTrue);
      expect(s.skipToRepeat().stage, SessionStage.repeat);
      expect(repeat.skipToRepeat(), same(repeat));

      final review = QuranSession.start(QuranSessionKind.review, const Passage(114, 1, 6), now: now, day: today, portion: '114:1-6');
      expect(review.stage, SessionStage.test);
      expect(QuranSession.start(QuranSessionKind.wird, const Passage(2, 1, 5), now: now, day: today).stage, SessionStage.reading);
      expect(QuranSessionKind.hifz.guided && QuranSessionKind.review.guided, isTrue);
      expect(QuranSessionKind.wird.guided || QuranSessionKind.free.guided, isFalse);
    });

    test('reveals stay inside the passage; a new passage starts clean', () {
      final s = QuranSession.start(QuranSessionKind.free, const Passage(1, 2, 4), now: now, day: today)
          .reveal(const [AyahRef(1, 3), AyahRef(1, 7)])
          .withResults('الحمد لله');
      expect(s.reveals, {const AyahRef(1, 3)});
      final other = s.withPassage(const Passage(1, 5, 7));
      expect(other.reveals, isEmpty);
      expect(other.results, isEmpty);
      expect(s.withPassage(const Passage(1, 2, 4)), same(s));
    });

    test('JSON round-trips; anything unreadable is simply no session', () {
      final s = QuranSession.start(QuranSessionKind.review, const Passage(78, 1, 16), now: now, day: today, planKey: 'hifz/amma/5', portion: '78:1-16')
          .advance()
          .reveal(const [AyahRef(78, 4)])
          .withResults('عم يتساءلون')
          .withPage(582)
          .withMode(QuranMode.recite);
      final back = QuranSession.tryParse(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.toJson(), s.toJson());
      expect(back.reveals, {const AyahRef(78, 4)});
      expect(back.mode, QuranMode.recite);
      expect(QuranSession.tryParse(null), isNull);
      expect(QuranSession.tryParse({'v': 2}), isNull);
      expect(QuranSession.tryParse({...s.toJson(), 'kind': 'party'}), isNull);
      expect(QuranSession.tryParse({...s.toJson(), 'passage': 'x'}), isNull);
    });

    test('stale after midnight, after a plan edit, or when the portion is no longer today\'s', () {
      final s = QuranSession.start(QuranSessionKind.hifz, const Passage(114, 1, 6), now: now, day: today, planKey: 'hifz/amma/5', portion: '114:1-6');
      expect(s.isStale(today: today, planKey: 'hifz/amma/5', portion: '114:1-6'), isFalse);
      expect(s.isStale(today: '2026-10-21', planKey: 'hifz/amma/5', portion: '114:1-6'), isTrue);
      expect(s.isStale(today: today, planKey: 'hifz/amma/7', portion: '114:1-6'), isTrue);
      expect(s.isStale(today: today, planKey: 'hifz/amma/5', portion: '113:1-5'), isTrue);
      final free = QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: today);
      expect(free.isStale(today: today), isFalse);
    });

    test('the store keeps one session on the device; wipe removes the key', () async {
      final kv = MemoryKvStore();
      final store = QuranSessionStore(kv);
      final s = QuranSession.start(QuranSessionKind.wird, const Passage(2, 1, 5), now: now, day: today, page: 2);
      await store.save(s);
      expect(kv.data.keys, contains(QuranSessionStore.kvKey));
      expect((await store.load())!.toJson(), s.toJson());
      await kv.write(QuranSessionStore.kvKey, '{broken');
      expect(await store.load(), isNull);
      await QuranSessionStore.wipe(kv);
      expect(kv.data.containsKey(QuranSessionStore.kvKey), isFalse);
    });

    test('a saved session from yesterday is dropped, not resumed', () async {
      final kv = MemoryKvStore();
      final yesterday = QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: '2026-10-19');
      await QuranSessionStore(kv).save(yesterday);
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      expect(await loadValidSession(c.read), isNull);
      expect(kv.data.containsKey(QuranSessionStore.kvKey), isFalse);
    });

    test('a stale check clears only the session it judged, in the session writes\' order', () async {
      final kv = MemoryKvStore();
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore()), clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      final store = QuranSessionStore(kv);
      final ctl = c.read(activeSessionProvider.notifier);
      final old = QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: '2026-10-19');
      await store.save(old);
      // A reader begins a new session (and closes) while the check that judged [old] is still running.
      final fresh = QuranSession.start(QuranSessionKind.free, const Passage(2, 6, 9), now: now.add(const Duration(seconds: 1)), day: today);
      await ctl.begin(fresh);
      ctl.detach(fresh.id);
      await ctl.discard(old.id);
      expect((await store.load())!.id, fresh.id);
      await ctl.discard(fresh.id);
      expect(await store.load(), isNull);
    });

    test('detach lets go only of the reader\'s own session', () async {
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(MemoryKvStore()), secureStoreProvider.overrideWithValue(MemoryKvStore())],
      );
      addTearDown(c.dispose);
      final ctl = c.read(activeSessionProvider.notifier);
      final first = QuranSession.start(QuranSessionKind.wird, const Passage(2, 1, 5), now: now, day: today);
      final next = QuranSession.start(QuranSessionKind.hifz, const Passage(114, 1, 5), now: now.add(const Duration(seconds: 1)), day: today);
      await ctl.begin(next);
      ctl.detach(first.id); // the closing reader's session is not the one running
      expect(c.read(activeSessionProvider)?.id, next.id);
      ctl.detach(null);
      expect(c.read(activeSessionProvider)?.id, next.id);
      ctl.detach(next.id);
      expect(c.read(activeSessionProvider), isNull);
    });

    test('«أكمل جلستك» re-checks when a session starts or ends, not on every page turn', () async {
      final kv = MemoryKvStore();
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore()), clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(quranResumeProvider, (_, __) {});
      addTearDown(sub.close);
      expect(await c.read(quranResumeProvider.future), isNull);
      final ctl = c.read(activeSessionProvider.notifier);
      final s = QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: today, page: 2);
      await ctl.begin(s);
      expect((await c.read(quranResumeProvider.future))!.page, 2);
      var rebuilt = 0;
      final watch = c.listen(quranResumeProvider, (_, __) => rebuilt++);
      addTearDown(watch.close);
      ctl.update((x) => x.withPage(3));
      ctl.update((x) => x.withPage(4));
      await Future<void>.delayed(Duration.zero);
      expect(rebuilt, 0, reason: 'a page turn does not reload or re-validate the saved session');
      // The reader closes: the session saved with its last page is offered.
      ctl.detach(s.id);
      expect((await c.read(quranResumeProvider.future))!.page, 4);
    });

    test('a guided session keeps the hifz plan\'s (device) day when the saved place is in another day', () async {
      // An instant whose day on the device differs from the place's, whatever zone the host runs in.
      final east = DateTime(2026, 10, 20, 0, 30).timeZoneOffset >= Duration.zero;
      final instant = (east ? DateTime(2026, 10, 20, 0, 30) : DateTime(2026, 10, 20, 23, 30)).toUtc();
      final zone = east ? 'Pacific/Pago_Pago' : 'Pacific/Kiritimati';
      final kv = MemoryKvStore();
      await LocalStore(kv).write('hifz', const HifzPlan(goal: HifzGoal.amma, perDay: 5).toJson());
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          clockProvider.overrideWithValue(() => instant),
          quranDataProvider.overrideWith((_) async => q),
          initialSettingsProvider.overrideWithValue(AppSettings(place: Place(nameAr: 'مكان', nameEn: 'Place', country: 'XX', lat: 0, lng: 0, timezone: zone))),
        ],
      );
      addTearDown(c.dispose);
      const device = '2026-10-20';
      expect(sessionDay(c.read, QuranSessionKind.hifz), device);
      expect(sessionToday(c.read), isNot(device), reason: 'the place is in another day');
      expect(sessionDay(c.read, QuranSessionKind.wird), sessionToday(c.read));
      final s = QuranSession.start(
        QuranSessionKind.hifz,
        const Passage(114, 1, 5),
        now: instant,
        day: sessionDay(c.read, QuranSessionKind.hifz),
        planKey: 'hifz/amma/5',
        portion: '114:1-5',
      );
      await QuranSessionStore(kv).save(s);
      expect((await loadValidSession(c.read))?.id, s.id);
    });
  });

  group('sessions in the reader', () {
    setUpAll(loadAppFonts);
    setUp(() => YqGlassConfig.enableBlur = false);

    List<Override> base({int goal = 2}) => [
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => q),
          mushafLayoutProvider.overrideWith((_) async => null),
          listenControllerProvider.overrideWith(FakeListen.new),
          initialSettingsProvider.overrideWithValue(AppSettings(readerHintSeen: true, wirdGoalPages: goal)),
        ];

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    ReaderLayers layers(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(ReaderScreen))).read(quranSessionControllerProvider);

    testWidgets('kill + restore: a memorised passage comes back with its reveals', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await tester.pumpWidget(
        harness(const ReaderScreen(initialPage: 1, mode: QuranMode.memorise, passage: Passage(1, 2, 4), session: 'free'), kv: kv, overrides: base()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      tester.widget<MushafPage>(find.byType(MushafPage).first).onAyahTap!(const AyahRef(1, 3));
      await tester.pump();
      expect(layers(tester).revealed, {const AyahRef(1, 3)});
      await tester.pump(const Duration(milliseconds: 50));
      final saved = QuranSession.tryParse(jsonDecode(kv.data[QuranSessionStore.kvKey]!))!;
      expect(saved.kind, QuranSessionKind.free);
      expect(saved.reveals, {const AyahRef(1, 3)});

      // The app is killed: a new process, the same device store.
      await leave(tester);
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 1, session: 'resume'), kv: kv, overrides: base()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final l = layers(tester);
      expect(l.mode, QuranMode.memorise);
      expect(l.passage, const Passage(1, 2, 4));
      expect(l.revealed, {const AyahRef(1, 3)});
      expect(tester.widget<MushafPage>(find.byType(MushafPage).first).memorise, MemoriseMode.ayat);
      await leave(tester);
    });

    testWidgets('a wird session counts towards its goal and ends with its card (gold), then is gone', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 5, session: 'wird'), kv: kv, overrides: base(goal: 1)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('0 / 1'), findsOneWidget);
      expect(kv.data[QuranSessionStore.kvKey], contains('"kind":"wird"'));
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.text('أتممت جلستك'), findsOneWidget);
      expect(kv.data.containsKey(QuranSessionStore.kvKey), isFalse);
      await tester.tap(find.text('إغلاق'));
      await tester.pumpAndSettle();
      await leave(tester);
    });

    testWidgets('the wird orb starts «ابدأ وردك» from the last page read and opens the reader on it', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Center(child: WirdOrb(done: 0, goal: 2))),
            routes: [GoRoute(path: 'quran/read/:page', builder: (_, s) => Scaffold(body: Text('reader ${s.uri}')))],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(kv),
            secureStoreProvider.overrideWithValue(MemoryKvStore()),
            ...base(),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: YqTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WirdOrb));
      await tester.pumpAndSettle();
      expect(find.text('ابدأ وردك'), findsNWidgets(2));
      expect(find.text('2 صفحات من ص 1 · نحو 4 د'), findsOneWidget);
      await tester.tap(find.text('ابدأ وردك').last);
      await tester.pumpAndSettle();
      expect(find.text('reader /quran/read/1?session=resume'), findsOneWidget);
      expect(kv.data[QuranSessionStore.kvKey], contains('"kind":"wird"'));
      expect(kv.data[QuranSessionStore.kvKey], contains('"goal":2'));
    });

    testWidgets('a wird session started after today\'s goal is met does not end as it opens; it counts on from there', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await ReadingRepository(LocalStore(kv)).saveWird(const WirdDay(date: today, pages: {1, 2}, ticked: true));
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 5, session: 'wird'), kv: kv, overrides: base()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('أتممت جلستك'), findsNothing);
      expect(find.text('2 / 4'), findsOneWidget, reason: 'two pages read today, two more for this session');
      expect(kv.data[QuranSessionStore.kvKey], contains('"goal":4'));
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('أتممت جلستك'), findsNothing);
      await leave(tester);
    });

    testWidgets('a saved session that opens already met (no goal of its own) does not end as it opens', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await ReadingRepository(LocalStore(kv)).saveWird(const WirdDay(date: today, pages: {1, 2}, ticked: true));
      await QuranSessionStore(kv).save(
        QuranSession.start(QuranSessionKind.wird, const Passage(2, 1, 5), now: now, day: today, page: 5, planKey: 'wird/2'),
      );
      await tester.pumpWidget(harness(const ReaderScreen(initialPage: 5, session: 'resume'), kv: kv, overrides: base()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('أتممت جلستك'), findsNothing);
      await leave(tester);
    });

    testWidgets('«التالي» replaces the reader: back goes home, no reader is left showing the next one\'s layers', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await LocalStore(kv).write('hifz', const HifzPlan(goal: HifzGoal.amma, perDay: 5).toJson());
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Center(child: Text('home'))),
            routes: [
              GoRoute(
                path: 'quran/read/:page',
                builder: (_, s) {
                  final p = s.uri.queryParameters;
                  return ReaderScreen(
                    key: ValueKey(s.uri.toString()),
                    initialPage: int.parse(s.pathParameters['page']!),
                    mode: QuranMode.parse(p['mode']),
                    passage: passageOfQuery(p),
                    session: p['session'],
                    portion: p['portion'],
                  );
                },
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(kv),
            secureStoreProvider.overrideWithValue(MemoryKvStore()),
            ...base(goal: 1),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: YqTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.push('/quran/read/5?session=wird').ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.text('أتممت جلستك'), findsOneWidget);
      await tester.tap(find.text('ابدأ الحلقة'));
      await tester.pumpAndSettle();

      // One reader: the halaqa's, holding its own session (the closed reader did not take it away).
      expect(find.byType(ReaderScreen), findsOneWidget);
      final c = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
      expect(c.read(activeSessionProvider)?.kind, QuranSessionKind.hifz);
      expect(c.read(quranSessionControllerProvider).mode, QuranMode.listen);
      expect(c.read(quranSessionControllerProvider).passage, const Passage(114, 1, 5));

      // Back: home, not the wird reader redrawn with the halaqa's layers.
      await tester.tap(find.byTooltip('الخروج إلى الفهرس'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(c.read(activeSessionProvider), isNull);
      expect(kv.data[QuranSessionStore.kvKey], contains('"kind":"hifz"'), reason: 'the halaqa stays saved for «أكمل جلستك»');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('continue reading offers «أكمل جلستك · ص {page}» for a session left open today', (tester) async {
      phone(tester);
      final kv = MemoryKvStore();
      await QuranSessionStore(kv).save(
        QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: today, page: 2, mode: QuranMode.memorise),
      );
      await tester.pumpWidget(harness(const Scaffold(body: ContinueReading()), kv: kv, overrides: base()));
      await tester.pumpAndSettle();
      expect(find.text('أكمل جلستك · ص 2'), findsOneWidget);
    });
  });
}
