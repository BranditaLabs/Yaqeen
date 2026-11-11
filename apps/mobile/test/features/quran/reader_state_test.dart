import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/settings/settings_controller.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/data/tafsir_repository.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/ayah_sheet.dart';
import 'package:yaqeen/features/quran/presentation/quran_index_screen.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

/// Tafsir whose text arrives when the test says so (null = offline with nothing cached).
class _SlowTafsir extends TafsirRepository {
  var pending = Completer<TafsirText?>();
  @override
  Future<TafsirText?> lookup(AyahRef r) => pending.future;
  @override
  Future<String> selected() async => 'muyassar';
  @override
  Future<List<TafsirInfo>> list() async => const [];
}

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

  List<Override> base() => [
        clockProvider.overrideWithValue(() => now),
        quranDataProvider.overrideWith((_) async => q),
      ];

  Future<void> dismissHint(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('حسناً'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('leaving the reader refreshes «continue reading» for screens kept alive under the tabs', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    await ReadingRepository(LocalStore(kv)).saveLastRead(5, 2, now);
    final open = ValueNotifier(true);
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            Consumer(builder: (_, ref, __) => Text('last:${ref.watch(lastReadProvider).valueOrNull?.page}')),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: open,
                builder: (_, on, __) => on ? const ReaderScreen(initialPage: 293) : const SizedBox(),
              ),
            ),
          ],
        ),
        kv: kv,
        overrides: base(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('last:5'), findsOneWidget);
    open.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('last:293'), findsOneWidget);
  });

  testWidgets('«إبقاء الشاشة مضاءة» follows the setting while reading', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const ReaderScreen(initialPage: 293), overrides: base()));
    await tester.pump();
    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    final device = c.read(deviceServicesProvider) as FakeDeviceServices;
    expect(device.awake, isTrue);
    await c.read(settingsProvider.notifier).update((x) => x.copyWith(keepAwake: false), sync: false);
    await tester.pump();
    expect(device.awake, isFalse);
    await c.read(settingsProvider.notifier).update((x) => x.copyWith(keepAwake: true), sync: false);
    await tester.pump();
    expect(device.awake, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the page slider turns once, when the thumb is let go', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    final repo = ReadingRepository(LocalStore(kv));
    await tester.pumpWidget(harness(const ReaderScreen(initialPage: 293), kv: kv, overrides: base()));
    await dismissHint(tester);
    expect((await repo.lastRead())!.page, 293);
    final drag = await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await drag.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect((await repo.lastRead())!.page, 293); // nothing turned (or downloaded) mid-drag
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await repo.lastRead())!.page, isNot(293));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reader settings › «وضع الاستماع» opens the surah of the page on screen', (tester) async {
    phone(tester);
    final router = GoRouter(
      initialLocation: '/quran/page/293',
      routes: [
        GoRoute(path: '/quran/page/:page', builder: (_, s) => ReaderScreen(initialPage: int.parse(s.pathParameters['page']!))),
        GoRoute(path: '/quran/listen/:surah', builder: (_, s) => Scaffold(body: Text('listen:${s.pathParameters['surah']}'))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kvStoreProvider.overrideWithValue(MemoryKvStore()), secureStoreProvider.overrideWithValue(MemoryKvStore()), ...base()],
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
    await dismissHint(tester);
    await tester.tap(find.byTooltip('إعدادات القراءة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('وضع الاستماع'));
    await tester.pump();
    await tester.tap(find.text('وضع الاستماع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('listen:17'), findsOneWidget); // page 293 opens with the end of Al-Isra
  });

  testWidgets('tafsir: the panel opens at once with a skeleton; offline shows the placeholder and a retry', (tester) async {
    phone(tester);
    final tafsir = _SlowTafsir();
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAyahSheet(context, quran: q, ref: const AyahRef(2, 255)),
              child: const Text('open'),
            ),
          ),
        ),
        overrides: [...base(), tafsirRepositoryProvider.overrideWithValue(tafsir)],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تفسير'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('[نص التفسير الميسر لهذه الآية من مصدر المحتوى المرخّص]'), findsNothing);
    expect(find.text('إعادة المحاولة'), findsNothing);

    tafsir.pending.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('[نص التفسير الميسر لهذه الآية من مصدر المحتوى المرخّص]'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    tafsir.pending = Completer()..complete(const TafsirText(text: '[نص من المصدر]', source: TafsirSource.pack));
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('[نص من المصدر]'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsNothing);
  });
}
