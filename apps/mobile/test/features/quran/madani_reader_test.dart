import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/quran/data/mushaf_fonts.dart';
import 'package:yaqeen/features/quran/domain/ayah_search.dart';
import 'package:yaqeen/features/quran/domain/mushaf_layout.dart';
import 'package:yaqeen/features/quran/domain/page_geometry.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/ayah_results.dart';
import 'package:yaqeen/features/quran/presentation/madani_page.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/page_curl.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

/// Fonts can't download in tests: pages are marked loaded and glyphs measure in the test font.
class _FakeLoader implements PageFontLoader {
  final loaded = <String>[];
  @override
  Future<void> load(String family, Uint8List bytes) async => loaded.add(family);
}

/// A deterministic stand-in for QCF advance widths: ≈ 1.55 font sizes per word, so a full line is
/// ≈ 15.5 like the real fonts, with some spread between words and lines.
double _unit(MushafWord w) => w.isEnd ? 0.9 : 1.2 + (w.code.codeUnitAt(0) % 9) * 0.1;

void main() {
  final layoutJson = jsonDecode(File('assets/quran/layout_v2.json').readAsStringSync()) as Map<String, dynamic>;
  final layout = MushafLayout.fromJson(layoutJson);
  final quranJson = jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>;
  final q = QuranData.fromJson(quranJson, pageStarts: layout.starts);

  group('layout asset (layout_v2.json)', () {
    test('604 pages × 15 lines; every ayah exactly once, in reading order, with its end marker', () {
      expect(layout.pages, hasLength(604));
      final seen = <AyahRef>[];
      for (final (i, page) in layout.pages.indexed) {
        expect(page, hasLength(15), reason: 'page ${i + 1}');
        final words = [
          for (final l in page)
            if (l is TextLine) ...l.words,
        ];
        expect(words, isNotEmpty);
        for (final w in words) {
          if (seen.isEmpty || seen.last != w.ref) seen.add(w.ref);
        }
        // Positions run 1..n inside an ayah, ending with exactly one end marker.
        final byAyah = <AyahRef, List<MushafWord>>{};
        for (final w in words) {
          byAyah.putIfAbsent(w.ref, () => []).add(w);
        }
        for (final e in byAyah.entries) {
          expect([for (final w in e.value) w.position], List.generate(e.value.length, (k) => k + 1), reason: '${e.key}');
          expect(e.value.where((w) => w.isEnd), hasLength(1), reason: '${e.key}');
          expect(e.value.last.isEnd, isTrue, reason: '${e.key}');
        }
        expect(layout.starts[i], words.first.ref, reason: 'page ${i + 1} start');
      }
      expect(seen, hasLength(QuranData.totalAyat));
      var r = const AyahRef(1, 1);
      for (final s in seen) {
        expect(s, r);
        if (s != const AyahRef(114, 6)) r = q.next(r);
      }
    });

    test('surah bands and Basmala lines sit right before each surah; never for At-Tawbah', () {
      final bands = <int>[];
      MushafLine? prev;
      for (final page in layout.pages) {
        for (final l in page) {
          if (l is SurahBandLine) bands.add(l.surah);
          if (l is BasmalaLine) expect(prev, isA<SurahBandLine>());
          if (prev case SurahBandLine(:final surah) when surah != 1 && surah != 9) {
            expect(l, isA<BasmalaLine>());
          }
          prev = l;
        }
      }
      expect(bands, List.generate(114, (i) => i + 1));
      // An-Nisa's band ends page 76; its Basmala opens page 77 (the 1421 print).
      expect(layout.page(76).last, isA<SurahBandLine>());
      expect(layout.page(77).first, isA<BasmalaLine>());
      expect(layout.basmalaWords, hasLength(4));
      expect(layout.fontsFor(77), [77, 1]);
      expect(layout.fontsFor(3), [3]);
    });

    test('the app counts the printed pages: QuranData pages match the layout, surah start pages agree', () {
      for (var p = 1; p <= 604; p++) {
        final fromText = {for (final s in q.page(p)) ...s.ayat.map((a) => a.ref)};
        final fromLayout = {
          for (final l in layout.page(p))
            if (l is TextLine) ...l.words.map((w) => w.ref),
        };
        expect(fromText, fromLayout, reason: 'page $p');
      }
      for (final s in q.surahs) {
        expect(q.pageOf(AyahRef(s.number, 1)), s.startPage, reason: 'surah ${s.number}');
      }
      // A page where the 1421 print differs from the Tanzil metadata.
      expect(q.firstOfPage(121), const AyahRef(5, 78));
    });
  });

  group('page geometry', () {
    final sizes = [
      const Size(300, 486), // 320×568 phone, after margins and header/footer
      const Size(362, 740), // 390×844
      const Size(520, 820), // tablet portrait
      const Size(552, 730), // one page of a 1180×820 spread
      const Size(800, 300), // very wide, very short
    ];

    test('every page fits every box: 15 lines share the height, no word leaves the width', () {
      for (final size in sizes) {
        for (var p = 1; p <= 604; p++) {
          final g = PageGeometry.compute(lines: layout.page(p), size: size, unitWidth: _unit, opening: MushafLayout.isOpening(p));
          expect(g.fits, isTrue, reason: 'page $p at $size');
          expect(g.pitch * MushafLayout.linesPerPage, lessThanOrEqualTo(size.height + 0.01));
          expect(g.fontSize, greaterThan(4));
          expect(g.pitch, greaterThanOrEqualTo(g.fontSize * PageGeometry.minPitch - 0.01), reason: 'lines must not touch');
        }
      }
    });

    test('full lines are justified to the block edges; short lines are centred', () {
      // Like the real fonts: a full line's glyphs add up to ≈ 15.5 font sizes (±2 %), whatever its word
      // count; the page's short lines (≤ 6 words here) are ≈ 1.5 per word.
      final page = layout.page(604);
      final units = <MushafWord, double>{};
      for (final (i, l) in page.indexed) {
        if (l is! TextLine) continue;
        final n = l.words.length;
        for (final w in l.words) {
          units[w] = n > 6 ? (15.5 + (i % 3 - 1) * 0.3) / n : 1.5;
        }
      }
      final g = PageGeometry.compute(lines: page, size: const Size(362, 740), unitWidth: (w) => units[w]!);
      final textLines = g.lines.where((l) => l.words.isNotEmpty).toList();
      for (final l in textLines) {
        final full = l.words.length > 6;
        final left = l.words.last.rect.left;
        final right = l.words.first.rect.right;
        if (full) {
          expect(right, closeTo(g.block.right, 0.5), reason: 'line ${l.slot} justified');
          expect(left, closeTo(g.block.left, 0.5), reason: 'line ${l.slot} justified');
        } else {
          expect((left + right) / 2, closeTo(g.block.center.dx, 0.5), reason: 'line ${l.slot} centred');
          expect(left, greaterThan(g.block.left + 40));
        }
      }
    });

    test('hit-testing: a point maps to its word and ayah; gaps go to the nearer word; margins hit nothing', () {
      final g = PageGeometry.compute(lines: layout.page(50), size: const Size(362, 740), unitWidth: _unit);
      for (final l in g.lines) {
        for (final w in l.words) {
          expect(g.wordAt(w.rect.center), w.word);
          expect(g.ayahAt(w.rect.center), w.word.ref);
        }
      }
      final line = g.lines.firstWhere((l) => l.words.length > 3);
      // Right to left: the first word is the rightmost.
      expect(line.words.first.rect.left, greaterThan(line.words.last.rect.left));
      final a = line.words[1];
      final gapPoint = Offset(a.rect.left - a.gap * 0.2, a.rect.center.dy);
      expect(g.wordAt(gapPoint), a.word);
      expect(g.wordAt(const Offset(-20, 300)), isNull);
      // The surah band and Basmala lines carry no ayah.
      expect(g.ayahAt(g.lines[0].rect.center), isNull);
      expect(g.ayahAt(g.lines[1].rect.center), isNull);
      // rectsOf merges an ayah's words per line.
      expect(g.rectsOf(const AyahRef(3, 1)), hasLength(1));
      expect(g.endMarkerOf(const AyahRef(3, 1)), isNotNull);
    });

    test('opening pages are short and centred, with the full-page glyph size', () {
      final regular = PageGeometry.compute(lines: layout.page(3), size: const Size(362, 740), unitWidth: _unit);
      final g = PageGeometry.compute(lines: layout.page(1), size: const Size(362, 740), unitWidth: _unit, opening: true);
      expect(g.lines, hasLength(8));
      expect(g.block.top, greaterThan(100));
      expect(g.block.width, lessThan(362 * PageGeometry.openingWidth + 0.5));
      expect(g.fontSize, lessThanOrEqualTo(362 / PageGeometry.referenceLineUnits + 0.01));
      expect(g.fontSize, greaterThan(regular.fontSize * 0.7));
      expect(g.fits, isTrue);
    });
  });

  group('page turn', () {
    test('RTL: dragging right turns forward; progress follows the finger', () {
      expect(TurnDrag.directionOf(30), TurnDirection.forward);
      expect(TurnDrag.directionOf(-30), TurnDirection.backward);
      const w = 400.0;
      var d = const TurnDrag(direction: TurnDirection.forward, leafWidth: w, start: Offset(20, 500), position: Offset(20, 500));
      expect(d.progress, 0);
      d = d.moveTo(const Offset(20 + w * TurnDrag.curlSpan / 2, 480));
      expect(d.progress, closeTo(0.5, 1e-9));
      d = d.moveTo(const Offset(-200, 480)); // dragged back past the start
      expect(d.progress, 0);
      final b = const TurnDrag(direction: TurnDirection.backward, leafWidth: w, start: Offset(380, 500), position: Offset(380, 500))
          .moveTo(const Offset(380 - w * TurnDrag.curlSpan / 4, 500));
      expect(b.progress, closeTo(0.75, 1e-9), reason: 'the previous leaf comes back from turned (1) towards flat (0)');
    });

    test('release: past a quarter completes, short of it snaps back; a fling decides by direction', () {
      const base = TurnDrag(direction: TurnDirection.forward, leafWidth: 400, start: Offset.zero, position: Offset.zero);
      final short = base.moveTo(const Offset(100, 0)); // progress 0.156
      expect(short.completes(0), isFalse);
      expect(short.target(0), 0);
      final far = base.moveTo(const Offset(200, 0)); // 0.3125
      expect(far.completes(0), isTrue);
      expect(far.target(0), 1);
      expect(short.completes(900), isTrue, reason: 'a fling forward completes');
      expect(far.completes(-900), isFalse, reason: 'a fling back cancels');
      const back = TurnDrag(direction: TurnDirection.backward, leafWidth: 400, start: Offset(400, 0), position: Offset(400, 0));
      expect(back.moveTo(const Offset(200, 0)).target(0), 0, reason: 'backward completes at flat');
      expect(back.moveTo(const Offset(380, 0)).target(0), 1, reason: 'and snaps back to turned');
      expect(back.moveTo(const Offset(380, 0)).target(-900), 0);
      expect(base.progressVelocity(640), closeTo(1, 1e-9));
    });

    test('fold: flat at 0, fully over the spine at 1, the flap mirrors the lifted part', () {
      const leaf = Rect.fromLTWH(0, 0, 400, 800);
      expect(FoldGeometry.of(leaf: leaf, progress: 0).flat, isTrue);
      final done = FoldGeometry.of(leaf: leaf, progress: 1, grabY: 400);
      expect(done.flap.every((p) => p.dx >= 400 - 0.01), isTrue, reason: 'the whole leaf has left the page');
      final mid = FoldGeometry.of(leaf: leaf, progress: 0.4, grabY: 790, lift: -40);
      expect(mid.front, isNotEmpty);
      expect(mid.revealed, isNotEmpty);
      // The outer corner is carried to f; reflecting twice is the identity.
      expect((mid.reflect(mid.c) - mid.f).distance, lessThan(1e-6));
      const p = Offset(30, 300);
      expect((mid.reflect(mid.reflect(p)) - p).distance, lessThan(1e-6));
      // The canvas matrix matches the point reflection.
      final m = mid.reflection;
      final x = m[0] * p.dx + m[4] * p.dy + m[12];
      final y = m[1] * p.dx + m[5] * p.dy + m[13];
      expect((Offset(x, y) - mid.reflect(p)).distance, lessThan(1e-6));
      expect(turnStyleOf(PageTurn.book, reduceMotion: false), TurnStyle.curl);
      expect(turnStyleOf(PageTurn.slide, reduceMotion: false), TurnStyle.slide);
      expect(turnStyleOf(PageTurn.book, reduceMotion: true), TurnStyle.fade);
    });
  });

  group('fonts', () {
    testWidgets('a page font on disk loads under the page family; a non-font is rejected and removed', (tester) async {
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('mushaf');
        addTearDown(() => dir.deleteSync(recursive: true));
        final loader = _FakeLoader();
        File('${dir.path}/mushaf/qcf_v2/p007.ttf')
          ..createSync(recursive: true)
          ..writeAsBytesSync([0, 1, 0, 0, ...List.filled(20, 7)]);
        final bad = File('${dir.path}/mushaf/qcf_v2/p008.ttf')..writeAsStringSync('<html>captive portal</html>');
        final fonts = MushafFonts(root: () async => dir, baseUrl: 'https://cdn.example/qcf', loader: loader);
        expect(fonts.urlFor(7).toString(), 'https://cdn.example/qcf/p7.ttf');
        expect(await fonts.downloadedCount(), 2);
        expect(await fonts.ensure(7), isTrue);
        expect(fonts.isReady(7), isTrue);
        expect(loader.loaded, [MushafFonts.family(7)]);
        expect(MushafFonts.family(7), 'QCF2_P007');
        expect(await fonts.ensure(8), isFalse, reason: 'not a font: deleted, not loaded');
        expect(bad.existsSync(), isFalse);
        expect(fonts.hasFailed(8), isTrue);
      });
    });
  });

  group('text fallback', () {
    testWidgets('auto-fits every tested page into a small screen: no overflow, no scroll', (tester) async {
      await loadAppFonts();
      final t = await AppLocalizations.delegate.load(const Locale('ar'));
      for (final p in [1, 2, 3, 50, 187, 255, 582, 604]) {
        const box = Size(296, 470);
        final size = FittedMushafPage.fit(quran: q, page: p, box: box, comfortable: false, t: t);
        expect(
          FittedMushafPage.measureHeight(quran: q, page: p, width: box.width, fontSize: size, comfortable: false, t: t),
          lessThanOrEqualTo(box.height),
        );
      }
      tester.view.physicalSize = const Size(320, 568) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: SizedBox(
              width: 296,
              height: 470,
              child: FittedMushafPage(
                page: MushafPage(quran: q, page: 50, theme: MushafTheme.paper, fontSize: 26, comfortable: false, locale: 'ar'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.widget<MushafPage>(find.byType(MushafPage)).fontSize, lessThan(26));
    });
  });

  group('reader on printed pages', () {
    setUpAll(loadAppFonts);
    setUp(() => YqGlassConfig.enableBlur = false);
    final index = AyahSearchIndex.buildSync(q);

    MushafFonts fonts() {
      final f = MushafFonts(root: () async => Directory.systemTemp, baseUrl: 'http://localhost:1/', loader: _FakeLoader());
      for (var p = 1; p <= 604; p++) {
        f.markLoaded(p);
      }
      return f;
    }

    Future<void> open(WidgetTester tester, {int page = 50, Size size = const Size(390, 844)}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          ReaderScreen(initialPage: page),
          overrides: [
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)),
            quranDataProvider.overrideWith((_) async => q),
            ayahSearchIndexProvider.overrideWith((_) async => index),
            mushafLayoutProvider.overrideWith((_) async => layout),
            mushafFontsProvider.overrideWithValue(fonts()),
            initialSettingsProvider.overrideWithValue(const AppSettings(readerHintSeen: true, autoNight: false)),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    /// The page the pager shows (single-page layout).
    int shown(WidgetTester tester) => tester.widget<MushafPager>(find.byType(MushafPager)).index + 1;

    testWidgets('draws the printed page (and its neighbours for turning) with nothing scrollable', (tester) async {
      await open(tester);
      expect(find.byType(MadaniPage), findsWidgets);
      expect(find.byType(MushafPage), findsNothing);
      expect(find.byType(Scrollable), findsNothing);
      final pages = tester.widgetList<MadaniPage>(find.byType(MadaniPage)).map((p) => p.page).toSet();
      expect(pages, {49, 50, 51});
      await leave(tester);
    });

    testWidgets('a long press on a word opens the ayah sheet for its ayah', (tester) async {
      await open(tester);
      final page = find.byWidgetPredicate((w) => w is MadaniPage && w.page == 50);
      final state = tester.state<MadaniPageState>(page);
      final word = state.geometry!.lines[5].words[2];
      final origin = tester.getTopLeft(page);
      await tester.longPressAt(origin + word.rect.center);
      await tester.pumpAndSettle();
      expect(find.text('خيارات الآية'), findsOneWidget);
      expect(find.textContaining('آل عمران'), findsWidgets);
      await leave(tester);
    });

    testWidgets('memorise hides words in place: the layout does not move; a tap reveals the ayah', (tester) async {
      await open(tester);
      final page = find.byWidgetPredicate((w) => w is MadaniPage && w.page == 50);
      final before = [
        for (final l in tester.state<MadaniPageState>(page).geometry!.lines)
          for (final w in l.words) w.rect,
      ];
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إخفاء الآيات'));
      await tester.pumpAndSettle();
      final widget = tester.widget<MadaniPage>(page);
      expect(widget.memorise, MemoriseMode.ayat);
      final state = tester.state<MadaniPageState>(page);
      final after = [
        for (final l in state.geometry!.lines)
          for (final w in l.words) w.rect,
      ];
      expect(after, before);
      final word = state.geometry!.lines[4].words.first;
      await tester.tapAt(tester.getTopLeft(page) + word.rect.center);
      await tester.pump();
      expect(tester.widget<MadaniPage>(page).revealed, contains(word.word.ref));
      await leave(tester);
    });

    testWidgets('tap zones: the left third turns to the next page, the right third back', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(40, 420));
      await tester.pumpAndSettle();
      expect(shown(tester), 51);
      await tester.tapAt(const Offset(350, 420));
      await tester.pumpAndSettle();
      expect(shown(tester), 50);
      await leave(tester);
    });

    testWidgets('a drag left → right turns forward; a short drag snaps back', (tester) async {
      await open(tester);
      final g = await tester.startGesture(const Offset(30, 600));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(shown(tester), 50, reason: 'too short: snapped back');
      await tester.timedDrag(find.byType(MushafPager), const Offset(260, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(shown(tester), 51);
      await tester.timedDrag(find.byType(MushafPager), const Offset(-260, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(shown(tester), 50);
      await leave(tester);
    });

    testWidgets('a wide screen shows the spread (odd page on the right) and turns it as a whole', (tester) async {
      await open(tester, page: 76, size: const Size(1180, 820));
      final current = tester.widgetList<MadaniPage>(find.byType(MadaniPage)).map((p) => p.page).toSet();
      expect(current, containsAll([75, 76]));
      final right = tester.getCenter(find.byWidgetPredicate((w) => w is MadaniPage && w.page == 75));
      final left = tester.getCenter(find.byWidgetPredicate((w) => w is MadaniPage && w.page == 76));
      expect(right.dx, greaterThan(left.dx));
      await tester.tapAt(const Offset(60, 400));
      await tester.pumpAndSettle();
      expect(tester.widget<MushafPager>(find.byType(MushafPager)).index, 38, reason: 'spread 77–78');
      expect(find.byType(Scrollable), findsNothing);
      await leave(tester);
    });
  });
}
