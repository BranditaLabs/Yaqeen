import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/app/routes/quran_routes.dart';
import 'package:yaqeen/app/shell.dart';
import 'package:yaqeen/core/design/living_sky.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/listen/presentation/mini_player.dart';
import 'package:yaqeen/features/listen/presentation/now_playing_screen.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import '../quran/one_page_fakes.dart';

/// Reports the bottom padding a tab screen sees (what YqInsets.bottom clears), with a «go» button
/// that runs pushListen like Home's listen entry.
class _Probe extends ConsumerWidget {
  const _Probe();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('pad ${MediaQuery.paddingOf(context).bottom.round()}', textDirection: TextDirection.ltr),
              TextButton(onPressed: () => pushListen(context, ref, 36), child: const Text('go')),
            ],
          ),
        ),
      );
}

void main() {
  final q = loadQuran();

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  Widget app(GoRouter router, List<Override> overrides) => ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          skyClockProvider.overrideWithValue(fixedSkyClock),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)),
          mushafLayoutProvider.overrideWith((_) async => null),
          initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
          ...overrides,
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
      );

  GoRouter router({String initial = '/b0'}) {
    final root = GlobalKey<NavigatorState>();
    return GoRouter(
      navigatorKey: root,
      initialLocation: initial,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => AppShell(navigationShell: shell),
          branches: [
            for (var i = 0; i < 5; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: i == 1 ? '/quran' : '/b$i',
                    builder: (_, __) => const _Probe(),
                    routes: i == 1 ? quranRoutes(root) : const [],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  int pad(WidgetTester tester) {
    final text = tester.widget<Text>(find.textContaining('pad ')).data!;
    return int.parse(text.substring(4));
  }

  testWidgets('mini player: shows while recitation is loaded, clears its height, closes, and steps aside for the reader',
      (tester) async {
    phone(tester);
    final listen = FakeListen();
    await tester.pumpWidget(app(router(), [quranDataProvider.overrideWith((_) async => q), listenControllerProvider.overrideWith(() => listen)]));
    await tester.pumpAndSettle();
    final bare = pad(tester);
    expect(find.byType(MiniPlayer), findsNothing);

    listen.set(const ListenState(status: ListenStatus.ready, surah: 18, ayah: 10, playing: true, synced: true));
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('الكهف'), findsOneWidget);
    expect(find.text('الآية 10'), findsOneWidget);
    expect(pad(tester), bare + MiniPlayer.height.round() + 8, reason: 'tab content clears the mini player');

    // A reciter's sample never shows it.
    listen.set(listen.state.copyWith(sampleOf: () => 'afasy'));
    await tester.pump();
    expect(find.byType(MiniPlayer), findsNothing);
    listen.set(listen.state.copyWith(sampleOf: () => null));
    await tester.pump();

    // Close = pause + dismiss; it comes back when recitation plays again.
    await tester.tap(find.byTooltip('إغلاق المشغّل'));
    await tester.pumpAndSettle();
    expect(listen.pauses, 1);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(pad(tester), bare);
    listen.set(listen.state.copyWith(playing: true));
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer), findsOneWidget);

    // A tap opens the reader on the recited page, listening; the mini player steps aside under it.
    await tester.tap(find.text('الكهف'));
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect([reader.initialPage, reader.mode], [q.pageOf(const AyahRef(18, 10)), QuranMode.listen]);
    final container = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    expect(container.read(miniPlayerVisibleProvider), isFalse);
    expect(container.read(readerPresenceProvider), 1);
  });

  testWidgets('mini player while loading is a shimmering pill', (tester) async {
    phone(tester);
    final listen = FakeListen(const ListenState(status: ListenStatus.loading, surah: 18));
    await tester.pumpWidget(
      harness(
        const Scaffold(body: Center(child: MiniPlayer())),
        overrides: [quranDataProvider.overrideWith((_) async => q), listenControllerProvider.overrideWith(() => listen)],
      ),
    );
    await tester.pump();
    expect(find.text('الكهف'), findsNothing);
    expect(find.byTooltip('إغلاق المشغّل'), findsNothing);
  });

  group('redirects into the reader', () {
    String location(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('/quran/listen and /quran/recite before the mushaf text has loaded: the surah start page', (tester) async {
      phone(tester);
      final never = Completer<QuranData>();
      final r = router();
      await tester.pumpWidget(app(r, [quranDataProvider.overrideWith((_) => never.future), listenControllerProvider.overrideWith(FakeListen.new)]));
      await tester.pump();
      r.go('/quran/listen/18?ayah=10');
      await tester.pump();
      await tester.pump();
      expect(location(r), '/quran/read/293?mode=listen&ayah=18%3A10&player=open');
      expect(find.byType(ReaderScreen), findsOneWidget);
      r.go('/quran/recite/36?from=1&to=12&hifz=1');
      await tester.pump();
      await tester.pump();
      expect(location(r), '/quran/read/${surahStartPage(36)}?mode=recite&surah=36&from=1&to=12&session=hifz');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('once loaded: the page of the ayah; a portion loops', (tester) async {
      phone(tester);
      final r = router();
      await tester.pumpWidget(app(r, [quranDataProvider.overrideWith((_) async => q), listenControllerProvider.overrideWith(FakeListen.new)]));
      await tester.pumpAndSettle();
      // In the app the mushaf text is loaded at start-up (Home reads it); here, read it first.
      await tester.runAsync(() => ProviderScope.containerOf(tester.element(find.byType(_Probe))).read(quranDataProvider.future));
      r.go('/quran/listen/18?ayah=60&to=70');
      await tester.pump();
      await tester.pump();
      final page = q.pageOf(const AyahRef(18, 60));
      expect(location(r), '/quran/read/$page?mode=listen&ayah=18%3A60&surah=18&from=60&to=70&player=open');
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect([reader.mode, reader.passage, reader.openPlayer], [QuranMode.listen, const Passage(18, 60, 70), true]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('pushListen (Home, index, challenge) opens the reader listening with the player', (tester) async {
      phone(tester);
      final r = router();
      final listen = FakeListen();
      await tester.pumpWidget(app(r, [quranDataProvider.overrideWith((_) async => q), listenControllerProvider.overrideWith(() => listen)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      for (var i = 0; i < 20 && find.byType(ReaderScreen).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect([reader.initialPage, reader.mode, reader.focus, reader.openPlayer], [surahStartPage(36), QuranMode.listen, const AyahRef(36, 1), true]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
