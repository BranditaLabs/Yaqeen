import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/ayah_sheet.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/page_curl.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/features/quran/presentation/session/mode_dock.dart';
import 'package:yaqeen/features/quran/presentation/session/quran_session_controller.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'one_page_fakes.dart';

void main() {
  final q = loadQuran();

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  List<Override> base(FakeListen listen) => [
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)),
        quranDataProvider.overrideWith((_) async => q),
        mushafLayoutProvider.overrideWith((_) async => null),
        listenControllerProvider.overrideWith(() => listen),
        initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true)),
      ];

  Future<void> open(WidgetTester tester, Widget reader, FakeListen listen, {MemoryKvStore? kv, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(reader, kv: kv, overrides: base(listen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  int shown(WidgetTester tester) => tester.widget<MushafPager>(find.byType(MushafPager)).index + 1;
  Finder segment(String label) => find.descendant(of: find.byType(ModeSwitch), matching: find.text(label));
  ReaderLayers layers(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ReaderScreen))).read(quranSessionControllerProvider);

  // Recitation on page 582 (an-Naba 1–30), playing with per-ayah timings.
  const reciting = ListenState(status: ListenStatus.ready, surah: 78, ayah: 29, playing: true, synced: true);

  testWidgets('switching layers never pushes a route', (tester) async {
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 5), listen);
    bool onTop() => ModalRoute.of(tester.element(find.byType(ReaderScreen)))!.isCurrent;
    expect(find.byType(ModeSwitch), findsOneWidget);

    await tester.tap(segment('استماع'));
    await tester.pumpAndSettle();
    expect(layers(tester).mode, QuranMode.listen);
    expect(listen.opened, [q.firstOfPage(5)]); // from the page on screen, not the surah's start
    expect(onTop(), isTrue);

    await tester.tap(segment('تحفيظ'));
    await tester.pumpAndSettle();
    expect(layers(tester).mode, QuranMode.memorise);
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).memorise, MemoriseMode.ayat);
    expect(onTop(), isTrue);

    await tester.tap(segment('قراءة'));
    await tester.pumpAndSettle();
    expect(layers(tester).mode, QuranMode.read);
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).memorise, MemoriseMode.off);
    expect(onTop(), isTrue);
    await leave(tester);
  });

  testWidgets('recite is offered only with the flag and a model; one segment shows no switch', (tester) async {
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 5), listen);
    expect(segment('تسميع'), findsNothing);
    await leave(tester);
  });

  testWidgets('labels fold to named icons when 1.3× text would overflow 360 pt', (tester) async {
    final listen = FakeListen();
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(size: Size(360, 780), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: ModeSwitch(
                  modes: QuranMode.values,
                  selected: QuranMode.read,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
        locale: 'en',
        overrides: base(listen),
      ),
    );
    await tester.pump();
    expect(find.text('Memorise'), findsNothing);
    expect(find.bySemanticsLabel('Memorise'), findsOneWidget);
    expect(find.byTooltip('Memorise'), findsOneWidget);
  });

  testWidgets('the page follows the recitation: 582 → 583, announced', (tester) async {
    final listen = FakeListen(reciting);
    await open(tester, const ReaderScreen(initialPage: 582, mode: QuranMode.listen), listen);
    expect(listen.opened, isEmpty); // already reciting this page: nothing reopens
    expect(shown(tester), 582);
    listen.set(reciting.copyWith(ayah: 31)); // first ayah of page 583
    await tester.pumpAndSettle();
    expect(shown(tester), 583);
    await leave(tester);
  });

  testWidgets('a look ahead holds following for 8 s, with the way back on a chip', (tester) async {
    final listen = FakeListen(reciting);
    await open(tester, const ReaderScreen(initialPage: 582, mode: QuranMode.listen), listen);
    await tester.tapAt(const Offset(40, 420)); // left third: the next page, by hand
    await tester.pumpAndSettle();
    expect(shown(tester), 583);
    listen.set(reciting.copyWith(ayah: 30)); // still on 582
    await tester.pump(const Duration(milliseconds: 500));
    expect(shown(tester), 583, reason: 'following waits');
    expect(find.text('عُد إلى موضع التلاوة'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    expect(find.text('عُد إلى موضع التلاوة'), findsNothing);
    listen.set(reciting.copyWith(ayah: 28));
    await tester.pumpAndSettle();
    expect(shown(tester), 582, reason: 'after 8 s the page follows again');

    // The chip takes the reader straight back.
    await tester.tapAt(const Offset(40, 420));
    await tester.pumpAndSettle();
    listen.set(reciting.copyWith(ayah: 27));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('عُد إلى موضع التلاوة'));
    await tester.pumpAndSettle();
    expect(shown(tester), 582);
    await leave(tester);
  });

  testWidgets('without timings the page follows only at a surah boundary', (tester) async {
    const unsynced = ListenState(status: ListenStatus.ready, surah: 78, ayah: 1, playing: true);
    final listen = FakeListen(unsynced);
    await open(tester, const ReaderScreen(initialPage: 582, mode: QuranMode.listen), listen);
    listen.set(unsynced.copyWith(ayah: 31));
    await tester.pumpAndSettle();
    expect(shown(tester), 582);
    listen.set(unsynced.copyWith(surah: 79, ayah: 1));
    await tester.pumpAndSettle();
    expect(shown(tester), surahStartPage(79));
    await leave(tester);
  });

  testWidgets('no following while a sheet is open', (tester) async {
    final listen = FakeListen(reciting);
    await open(tester, const ReaderScreen(initialPage: 582, mode: QuranMode.listen), listen);
    showReaderSettings(tester.element(find.byType(ReaderScreen)), page: 582);
    await tester.pumpAndSettle();
    listen.set(reciting.copyWith(ayah: 31));
    await tester.pumpAndSettle();
    expect(shown(tester), 582);
    await leave(tester);
  });

  testWidgets('the ayah sheet starts a layer «من هنا» and closes the passage «إلى هنا»', (tester) async {
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 1), listen);
    MushafPage page() => tester.widget<MushafPage>(find.byType(MushafPage).first);

    page().onAyahLongPress!(const AyahRef(1, 2));
    await tester.pumpAndSettle();
    expect(find.text('استمع من هنا'), findsOneWidget);
    expect(find.text('سمّع من هنا'), findsNothing); // no recite model in this build
    await tester.tap(find.text('احفظ من هنا'));
    await tester.pumpAndSettle();
    expect(find.text('اختر المقطع'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(layers(tester).mode, QuranMode.memorise);
    expect(page().passage, const Passage(1, 2, 7));

    // «من هنا» at 1:3, picker closed without choosing; «إلى هنا» at 1:5 closes the passage.
    page().onAyahLongPress!(const AyahRef(1, 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('احفظ من هنا'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 40)); // outside the picker
    await tester.pumpAndSettle();
    page().onAyahLongPress!(const AyahRef(1, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلى هنا'));
    await tester.pumpAndSettle();
    expect(page().passage, const Passage(1, 3, 5));

    // «استمع من هنا» plays from that ayah and turns the listen layer on.
    page().onAyahLongPress!(const AyahRef(1, 6));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استمع من هنا'));
    await tester.pumpAndSettle();
    expect(listen.opened.first, const AyahRef(1, 6));
    expect(layers(tester).mode, QuranMode.listen);
    await leave(tester);
  });

  testWidgets('memorising a chosen passage hides only its ayat; a tap reveals one', (tester) async {
    final listen = FakeListen();
    await open(tester, const ReaderScreen(initialPage: 1, mode: QuranMode.memorise, passage: Passage(1, 2, 4)), listen);
    final page = tester.widget<MushafPage>(find.byType(MushafPage).first);
    expect(page.memorise, MemoriseMode.ayat);
    expect(page.passage, const Passage(1, 2, 4));
    page.onAyahTap!(const AyahRef(1, 3));
    page.onAyahTap!(const AyahRef(1, 6)); // outside the passage: nothing to reveal
    await tester.pump();
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).revealed, {const AyahRef(1, 3)});
    await tester.tap(find.text('إظهار الكل'));
    await tester.pump();
    expect(tester.widget<MushafPage>(find.byType(MushafPage).first).revealed, const Passage(1, 2, 4).range.toSet());
    // «استماع ×3» loops the passage three times.
    await tester.tap(find.text('استماع ×3'));
    await tester.pump();
    expect(listen.passages, [(1, 2, 4, 3)]);
    await leave(tester);
  });
}
