import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/quran_session.dart';
import 'package:yaqeen/features/quran/presentation/quran_index_screen.dart';
import 'package:yaqeen/features/quran/presentation/session/listen_strip.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../../helpers/fonts.dart';
import 'one_page_fakes.dart';

void main() {
  final q = loadQuran();
  final now = DateTime.utc(2026, 10, 20, 12);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  /// The index under a router whose reader route only prints where it was asked to open.
  Future<void> open(WidgetTester tester, {MemoryKvStore? kv, FakeListen? listen}) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: QuranIndexScreen()),
          routes: [GoRoute(path: 'quran/read/:page', builder: (_, s) => Scaffold(body: Text('reader ${s.uri}')))],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(kv ?? MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          clockProvider.overrideWithValue(() => now),
          quranDataProvider.overrideWith((_) async => q),
          listenControllerProvider.overrideWith(() => listen ?? FakeListen()),
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
  }

  testWidgets('long-press a surah: its modes sheet opens the reader in that layer', (tester) async {
    await open(tester);
    await tester.longPress(find.text('البقرة').first);
    await tester.pumpAndSettle();
    expect(find.text('سورة البقرة'), findsWidgets);
    expect(find.text('قراءة'), findsOneWidget);
    expect(find.text('استماع'), findsOneWidget);
    expect(find.text('تحفيظ'), findsOneWidget);
    expect(find.text('تسميع'), findsNothing, reason: 'no recitation model in this build');
    await tester.tap(find.text('تحفيظ'));
    await tester.pumpAndSettle();
    expect(find.text('reader /quran/read/2?mode=memorise'), findsOneWidget);
  });

  testWidgets('the listen orb shows the surah playing with play / pause in its ring', (tester) async {
    final listen = FakeListen(const ListenState(status: ListenStatus.ready, surah: 18, ayah: 3, playing: true, synced: true));
    await open(tester, listen: listen);
    expect(find.byType(ListenPlayButton), findsOneWidget);
    expect(find.text('سورة الكهف'), findsWidgets);
    await tester.tap(find.byType(ListenPlayButton));
    await tester.pump();
    expect(listen.state.playing, isFalse);
  });

  testWidgets('a saved ayah opens with the ayah lit; a session left open is offered on the stage', (tester) async {
    final kv = MemoryKvStore();
    final store = ReadingRepository(LocalStore(kv));
    await store.toggle(Bookmark(kind: BookmarkKind.ayah, page: 50, ref: const AyahRef(3, 1), at: now));
    await QuranSessionStore(kv).save(
      QuranSession.start(QuranSessionKind.free, const Passage(2, 1, 5), now: now, day: '2026-10-20', page: 2, mode: QuranMode.memorise),
    );
    await open(tester, kv: kv);
    expect(find.text('أكمل جلستك · ص 2'), findsOneWidget);
    await tester.tap(find.textContaining('الآية 1 ·').first);
    await tester.pumpAndSettle();
    expect(find.text('reader /quran/read/50?ayah=3:1'), findsOneWidget);
  });
}
