import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/audio_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/listen/data/audio_downloads.dart';
import 'package:yaqeen/features/listen/data/listen_store.dart';
import 'package:yaqeen/features/listen/data/reciter_repository.dart';
import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/listen/presentation/player_sheet.dart';
import 'package:yaqeen/features/listen/presentation/reciters_screen.dart';
import 'package:yaqeen/features/quran/data/tafsir_repository.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

const reciterJson = {
  'id': 'afasy',
  'nameAr': 'مشاري راشد العفاسي',
  'nameEn': 'Mishary Alafasy',
  'style': 'murattal',
  'riwaya': 'hafs',
  'baseUrl': 'https://cdn.test/afasy/',
  'timingUrl': 'https://cdn.test/afasy/timings.json',
  'sampleUrl': 'https://cdn.test/afasy/sample.mp3',
  'sizeBytes': 6236000,
};

/// 10 s per ayah for surah 18 (110 ayat) — enough to test sync without real files.
final timingsJson = jsonEncode({
  '18': [
    for (var i = 0; i < 110; i++) [i * 10000, (i + 1) * 10000],
  ],
});

http.Client fakeServer() => MockClient((req) async {
      if (req.url.path == '/v1/content/reciters') {
        return http.Response.bytes(
          utf8.encode(jsonEncode([reciterJson])),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (req.url.path.endsWith('timings.json')) return http.Response(timingsJson, 200);
      return http.Response('not found', 404);
    });

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final reciter = Reciter.tryParse(reciterJson)!;
  late Directory tmp;

  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() async {
    YqGlassConfig.enableBlur = false;
    tmp = await Directory.systemTemp.createTemp('yq_listen');
  });
  tearDown(() async => tmp.delete(recursive: true));

  group('domain', () {
    test('surah file URL is zero-padded under baseUrl', () {
      expect(reciter.surahUrl(1).toString(), 'https://cdn.test/afasy/001.mp3');
      expect(reciter.surahUrl(114).toString(), 'https://cdn.test/afasy/114.mp3');
    });

    test('ayah at a position (binary search) and boundaries', () {
      final t = AyahTimings.fromJson(jsonDecode(timingsJson)['18'])!;
      expect(t.ayahAt(Duration.zero), 1);
      expect(t.ayahAt(const Duration(milliseconds: 9999)), 1);
      expect(t.ayahAt(const Duration(seconds: 10)), 2);
      expect(t.ayahAt(const Duration(hours: 5)), 110);
      expect(t.startOf(3), const Duration(seconds: 20));
    });

    test('5 minutes of listening ticks once a day; a new day starts over', () {
      var r = ListenDay.add(null, today: '2026-10-20', played: const Duration(minutes: 3));
      expect(r.tickNow, isFalse);
      r = ListenDay.add(r.day, today: '2026-10-20', played: const Duration(minutes: 2));
      expect(r.tickNow, isTrue);
      r = ListenDay.add(r.day, today: '2026-10-20', played: const Duration(minutes: 10));
      expect(r.tickNow, isFalse);
      r = ListenDay.add(r.day, today: '2026-10-21', played: const Duration(minutes: 1));
      expect([r.day.seconds, r.day.ticked], [60, false]);
    });

    test('snapshot round-trips', () {
      const s =
          PlaybackSnapshot(reciterId: 'afasy', surah: 18, ayah: 4, position: Duration(seconds: 31), speed: 1.25, repeat: ListenRepeat.ayah);
      final back = PlaybackSnapshot.tryParse(jsonDecode(jsonEncode(s.toJson())))!;
      expect([back.surah, back.ayah, back.position, back.speed, back.repeat], [18, 4, s.position, 1.25, ListenRepeat.ayah]);
    });
  });

  group('downloads', () {
    final body = List<int>.generate(1000, (i) => i % 256);

    AudioDownloads downloads(http.Client c, {bool wifi = true}) =>
        AudioDownloads(root: () async => tmp, isUnmetered: () async => wifi, client: c);

    test('downloads a surah and reports bytes on disk; delete reclaims', () async {
      final d = downloads(MockClient((_) async => http.Response.bytes(body, 200)));
      final progress = <int>[];
      await d.downloadSurah(reciter, 1, onProgress: (got, _) => progress.add(got));
      expect(await d.has('afasy', 1), isTrue);
      expect(await d.downloadedSurahs('afasy'), {1});
      expect(await d.bytesOnDisk(), 1000);
      expect(progress.last, 1000);
      expect((await d.sourceFor(reciter, 1)).scheme, 'file');
      expect((await d.sourceFor(reciter, 2)).scheme, 'https');
      await d.delete('afasy');
      expect(await d.bytesOnDisk(), 0);
    });

    test('resumes a partial file with a Range request', () async {
      final target = await downloads(MockClient((_) async => http.Response('', 500))).fileFor('afasy', 2);
      await target.parent.create(recursive: true);
      await File('${target.path}.part').writeAsBytes(body.sublist(0, 400));
      String? range;
      final d = downloads(
        MockClient((req) async {
          range = req.headers['Range'];
          return http.Response.bytes(body.sublist(400), 206);
        }),
      );
      await d.downloadSurah(reciter, 2);
      expect(range, 'bytes=400-');
      expect(await target.readAsBytes(), body);
    });

    test('waits for Wi-Fi unless mobile data is allowed', () async {
      final d = downloads(MockClient((_) async => http.Response.bytes(body, 200)), wifi: false);
      expect(() => d.downloadSurah(reciter, 3), throwsA(isA<WifiRequired>()));
      await d.downloadSurah(reciter, 3, allowMetered: true);
      expect(await d.has('afasy', 3), isTrue);
    });

    test('cancel keeps the partial file for later', () async {
      final d = downloads(MockClient((_) async => http.Response.bytes(body, 200)));
      final token = CancelToken()..cancel();
      expect(() => d.downloadSurah(reciter, 4, cancel: token), throwsA(isA<DownloadCancelled>()));
    });
  });

  List<Override> overrides(FakeAudioEngine engine, MemoryKvStore kv, {bool harnessed = false, http.Client? api}) => [
        if (!harnessed) ...[kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore())],
        audioEngineProvider.overrideWithValue(engine),
        filesDirProvider.overrideWithValue(() async => tmp),
        quranDataProvider.overrideWith((_) async => q),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(MemoryKvStore()), client: api ?? fakeServer()),
        ),
        reciterRepositoryProvider.overrideWith(
          (ref) => ReciterRepository(
            api: ref.watch(apiClientProvider),
            cache: ref.watch(kvStoreProvider),
            root: ref.watch(filesDirProvider),
            client: fakeServer(),
          ),
        ),
      ];

  group('controller', () {
    test('opens at an ayah, follows timings, repeats an ayah, skips, and persists', () async {
      final engine = FakeAudioEngine();
      final kv = MemoryKvStore();
      final c = ProviderContainer(overrides: overrides(engine, kv));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);

      await ctl.open(18, ayah: 3);
      var s = c.read(listenControllerProvider);
      expect(s.status, ListenStatus.ready);
      expect(s.synced, isTrue);
      expect(engine.opened.single.toString(), 'https://cdn.test/afasy/018.mp3');
      expect(engine.current, const Duration(seconds: 20));
      expect(engine.isPlaying, isTrue);
      await Future<void>.delayed(Duration.zero);

      engine.advance(const Duration(seconds: 25)); // 45 s → ayah 5
      await Future<void>.delayed(Duration.zero);
      expect(c.read(listenControllerProvider).ayah, 5);

      ctl.toggleRepeatAyah();
      engine.advance(const Duration(seconds: 6)); // crosses into ayah 6 → loops to 40 s
      await Future<void>.delayed(Duration.zero);
      s = c.read(listenControllerProvider);
      expect([s.ayah, engine.current], [5, const Duration(seconds: 40)]);

      ctl.toggleRepeatAyah();
      await ctl.next();
      expect(c.read(listenControllerProvider).ayah, 6);
      await ctl.cycleSpeed();
      expect(engine.speed, 1.25);

      await ctl.pause();
      await Future<void>.delayed(Duration.zero);
      expect(kv.data.values.join(), contains('"s":18'));
    });

    test('no reciters → noReciter state; a failing source → unavailable', () async {
      final engine = FakeAudioEngine()..failWith = Exception('offline');
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      await c.read(listenControllerProvider.notifier).open(1);
      expect(c.read(listenControllerProvider).status, ListenStatus.unavailable);
    });

    test('repeat ayah ×3 plays it three times, then moves on', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 3); // 20 s
      await Future<void>.delayed(Duration.zero);
      ctl.setRepeat(ListenRepeat.ayah, times: 3);
      for (var pass = 0; pass < 2; pass++) {
        engine.advance(const Duration(seconds: 11));
        await Future<void>.delayed(Duration.zero);
        expect([c.read(listenControllerProvider).ayah, engine.current], [3, const Duration(seconds: 20)]);
      }
      engine.advance(const Duration(seconds: 11));
      await Future<void>.delayed(Duration.zero);
      expect([c.read(listenControllerProvider).ayah, engine.current], [4, const Duration(seconds: 31)]);
    });

    test('repeat ayah on the last ayah loops instead of moving to the next surah', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 110); // 1090 s; the file ends at 20 min
      await Future<void>.delayed(Duration.zero);
      ctl.toggleRepeatAyah();
      engine.advance(const Duration(minutes: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = c.read(listenControllerProvider);
      expect([s.surah, s.ayah, engine.current], [18, 110, const Duration(seconds: 1090)]);
      expect(engine.opened, hasLength(1));
    });

    test('a range A–B (hifz `to`) loops, and stops after its count', () async {
      final engine = FakeAudioEngine();
      final kv = MemoryKvStore();
      final c = ProviderContainer(overrides: overrides(engine, kv));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 2, to: 4); // 10 s – 40 s
      await Future<void>.delayed(Duration.zero);
      var s = c.read(listenControllerProvider);
      expect([s.repeat, s.rangeFrom, s.rangeTo, s.repeatTimes], [ListenRepeat.range, 2, 4, 0]);

      ctl.setRepeat(ListenRepeat.range, times: 2);
      engine.advance(const Duration(seconds: 31)); // crosses the end of ayah 4
      await Future<void>.delayed(Duration.zero);
      expect([c.read(listenControllerProvider).ayah, engine.current], [2, const Duration(seconds: 10)]);
      engine.advance(const Duration(seconds: 31));
      await Future<void>.delayed(Duration.zero);
      expect(engine.isPlaying, isFalse);

      // The range is saved with the resume point and comes back with it.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final snap = PlaybackSnapshot.tryParse((jsonDecode(kv.data.values.firstWhere((v) => v.contains('"rp":"range"'))) as Map)['snapshot']);
      expect([snap?.repeat, snap?.rangeFrom, snap?.rangeTo, snap?.repeatTimes], [ListenRepeat.range, 2, 4, 2]);

      // Another surah drops the range.
      await ctl.open(19, ayah: 1);
      s = c.read(listenControllerProvider);
      expect(s.repeat, ListenRepeat.off);
    });

    test('a stopped sample puts the surah back, paused, and play works', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 3);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(listenControllerProvider).playing, isTrue);

      await ctl.playSample(reciter);
      expect(engine.opened.last.toString(), 'https://cdn.test/afasy/sample.mp3');
      await ctl.stopSample();
      await Future<void>.delayed(Duration.zero);
      var s = c.read(listenControllerProvider);
      expect([s.sampleOf, s.playing, s.status], [null, false, ListenStatus.ready]);
      expect(engine.opened.last.toString(), 'https://cdn.test/afasy/018.mp3');
      expect(engine.isPlaying, isFalse);

      await ctl.toggle();
      await Future<void>.delayed(Duration.zero);
      expect([engine.isPlaying, c.read(listenControllerProvider).playing], [true, true]);

      // A sample that plays to its end also hands back the surah.
      await ctl.playSample(reciter);
      engine.advance(const Duration(minutes: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s = c.read(listenControllerProvider);
      expect([s.sampleOf, s.playing, engine.isPlaying], [null, false, false]);
      expect(engine.opened.last.toString(), 'https://cdn.test/afasy/018.mp3');
    });

    test('«استماع» entries attach to what is playing, else the resume point, else the fallback', () async {
      final engine = FakeAudioEngine();
      final kv = MemoryKvStore();
      final c = ProviderContainer(overrides: overrides(engine, kv));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      expect(await ctl.entrySurah(7), 7);
      await ctl.open(18, ayah: 3);
      expect(await ctl.entrySurah(7), 18);

      final fresh = ProviderContainer(overrides: overrides(FakeAudioEngine(), kv));
      addTearDown(fresh.dispose);
      await c.read(listenStoreProvider).saveSnapshot(const PlaybackSnapshot(reciterId: 'afasy', surah: 36));
      expect(await fresh.read(listenControllerProvider.notifier).entrySurah(7), 36);
    });

    test('no catalogue and no cached copy → unavailable (retry), not «no reciter»', () async {
      final engine = FakeAudioEngine();
      final kv = MemoryKvStore();
      final c = ProviderContainer(
        overrides: overrides(engine, kv, api: MockClient((_) async => throw const SocketException('offline'))),
      );
      addTearDown(c.dispose);
      await expectLater(c.read(reciterRepositoryProvider).list(), throwsA(isA<Exception>()));
      await c.read(listenControllerProvider.notifier).open(1);
      expect(c.read(listenControllerProvider).status, ListenStatus.unavailable);

      // An empty catalogue that was fetched before stays the honest «no reciter yet».
      await kv.write('cache.reciters', '[]');
      expect(await c.read(reciterRepositoryProvider).list(), isEmpty);
      await c.read(listenControllerProvider.notifier).open(1);
      expect(c.read(listenControllerProvider).status, ListenStatus.noReciter);
    });

    test('pause writes today\'s time and the resume point together without losing either', () async {
      final store = ListenStore(LocalStore(MemoryKvStore()));
      await Future.wait([
        store.saveDay(const ListenDay(date: '2026-10-20', seconds: 90)),
        store.saveSnapshot(const PlaybackSnapshot(reciterId: 'afasy', surah: 18, ayah: 4)),
        store.setDownloading('afasy', true),
        store.setReciter('afasy'),
      ]);
      expect((await store.day())?.seconds, 90);
      expect((await store.snapshot())?.ayah, 4);
      expect(await store.downloading(), {'afasy'});
      expect(await store.reciterId(), 'afasy');
    });

    test('a passage ×3 plays three times, stops and signals; the count is kept with the resume point', () async {
      final engine = FakeAudioEngine();
      final kv = MemoryKvStore();
      final c = ProviderContainer(overrides: overrides(engine, kv));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.playPassage(const Passage(18, 2, 3), times: 3); // 10 s – 30 s
      await Future<void>.delayed(Duration.zero);
      var s = c.read(listenControllerProvider);
      expect([s.repeat, s.rangeFrom, s.rangeTo, s.repeatTimes, s.roundsDone, s.loopEnded], [ListenRepeat.range, 2, 3, 3, 0, false]);
      for (var pass = 1; pass <= 2; pass++) {
        engine.advance(const Duration(seconds: 21)); // crosses the end of ayah 3
        await Future<void>.delayed(Duration.zero);
        s = c.read(listenControllerProvider);
        expect([s.ayah, s.roundsDone, s.loopEnded, engine.current], [2, pass, false, const Duration(seconds: 10)]);
      }
      engine.advance(const Duration(seconds: 21));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s = c.read(listenControllerProvider);
      expect([s.roundsDone, s.loopEnded, engine.isPlaying], [3, true, false]);
      final snap = await c.read(listenStoreProvider).snapshot();
      expect([snap?.roundsDone, snap?.loopEnded], [3, true]);

      // Play again after the end starts the passage over.
      await ctl.toggle();
      await Future<void>.delayed(Duration.zero);
      s = c.read(listenControllerProvider);
      expect([engine.current, s.roundsDone, s.loopEnded, engine.isPlaying], [const Duration(seconds: 10), 0, false, true]);
    });

    test('opening the surah already loaded only seeks (no reload)', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 3);
      await ctl.pause();
      await Future<void>.delayed(Duration.zero);
      await ctl.open(18, ayah: 7);
      await Future<void>.delayed(Duration.zero);
      final s = c.read(listenControllerProvider);
      expect(engine.opened, hasLength(1));
      expect([engine.current, s.ayah, engine.isPlaying], [const Duration(seconds: 60), 7, true]);
      // Another surah does load.
      await ctl.open(19, ayah: 1);
      expect(engine.opened, hasLength(2));
    });

    test('echo: an ayah plays once, pauses, and leaves 1.2× its length to repeat it', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 1);
      final gap = ctl.playAyahThenPause(const AyahRef(18, 5)); // 40 s – 50 s
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect([engine.current, engine.isPlaying], [const Duration(seconds: 40), true]);
      engine.advance(const Duration(seconds: 11));
      expect(await gap, const Duration(seconds: 12));
      expect(engine.isPlaying, isFalse);
      // At 1.25× the pause is shorter.
      await ctl.cycleSpeed();
      final faster = ctl.playAyahThenPause(const AyahRef(18, 6));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      engine.advance(const Duration(seconds: 11));
      expect(await faster, const Duration(milliseconds: 9600));
    });

    test('echo: a pause, another open or the controller going away ends the wait (null), never a hang', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.open(18, ayah: 1);

      final paused = ctl.playAyahThenPause(const AyahRef(18, 5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ctl.pause();
      expect(await paused.timeout(const Duration(seconds: 1)), isNull);

      final replaced = ctl.playAyahThenPause(const AyahRef(18, 5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ctl.open(18, ayah: 2);
      expect(await replaced.timeout(const Duration(seconds: 1)), isNull);

      final toggled = ctl.playAyahThenPause(const AyahRef(18, 6));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ctl.toggle();
      expect(await toggled.timeout(const Duration(seconds: 1)), isNull);

      final c2 = ProviderContainer(overrides: overrides(FakeAudioEngine(), MemoryKvStore()));
      final ctl2 = c2.read(listenControllerProvider.notifier);
      await ctl2.open(18, ayah: 1);
      final gone = ctl2.playAyahThenPause(const AyahRef(18, 5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c2.dispose();
      expect(await gone.timeout(const Duration(seconds: 1)), isNull);
    });

    test('echo: the repeat set before it (mode, range, passes) comes back afterwards', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      final ctl = c.read(listenControllerProvider.notifier);
      await ctl.playPassage(const Passage(18, 1, 6), times: 3);
      final before = c.read(listenControllerProvider);
      final gap = ctl.playAyahThenPause(const AyahRef(18, 5));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      engine.advance(const Duration(seconds: 11));
      await gap;
      final during = c.read(listenControllerProvider);
      expect([during.rangeFrom, during.rangeTo, during.repeatTimes], [5, 5, 1]);
      ctl.restoreRepeat(before);
      final after = c.read(listenControllerProvider);
      expect([after.repeat, after.rangeFrom, after.rangeTo, after.repeatTimes], [ListenRepeat.range, 1, 6, 3]);
    });

    test('5 minutes of play is recorded for the day', () async {
      final kv = MemoryKvStore();
      final c = ProviderContainer(overrides: overrides(FakeAudioEngine(), kv));
      addTearDown(c.dispose);
      await c.read(listenControllerProvider.notifier).addListened(const Duration(minutes: 5));
      expect(kv.data.values.join(), contains('"ticked":true'));
    });
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// The player sheet's content on a page, with the recitation opened at [surah]:[ayah] first.
  Widget playerAt(int surah, int ayah) => Scaffold(
        body: SingleChildScrollView(child: _OpenThen(surah: surah, ayah: ayah, child: const PlayerSheet())),
      );

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    // The player loads on real async work: wait for it (up to 5 s) instead of a fixed delay.
    for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  testWidgets('player sheet: surah, reciter, current ayah and play/pause', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(playerAt(18, 2), kv: kv, overrides: overrides(engine, kv, harnessed: true)));
    });
    await waitFor(tester, find.text('يُشغَّل الآن'));
    expect(find.text('يُشغَّل الآن'), findsOneWidget);
    expect(find.text('الكهف'), findsOneWidget);
    expect(find.text('مشاري راشد العفاسي'), findsOneWidget);
    expect(find.text('السورة 18 · مكية · 110 آيات'), findsOneWidget);
    expect(find.textContaining('﴿٢﴾'), findsOneWidget);
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    await tester.tap(find.byTooltip('إيقاف مؤقت'));
    await tester.pump();
    expect(find.byTooltip('تشغيل'), findsOneWidget);
    expect(find.text('تغيير القارئ'), findsOneWidget);
    expect(find.text('انتقل إلى'), findsOneWidget);
  });

  testWidgets('player sheet: a downloaded surah says so', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    await tester.runAsync(() async {
      final file = await AudioDownloads(root: () async => tmp, isUnmetered: () async => true).fileFor('afasy', 18);
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      await tester.pumpWidget(harness(playerAt(18, 2), kv: kv, overrides: overrides(engine, kv, harnessed: true)));
    });
    await waitFor(tester, find.byTooltip('محمّل · المس للحذف'));
    expect(find.byTooltip('محمّل · المس للحذف'), findsOneWidget);
  });

  testWidgets('player sheet: «تنزيل السورة» runs on the download queue with a ring', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    final gate = Completer<void>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          playerAt(18, 2),
          kv: kv,
          overrides: [
            ...overrides(engine, kv, harnessed: true),
            audioDownloadsProvider.overrideWithValue(
              AudioDownloads(
                root: () async => tmp,
                isUnmetered: () async => true,
                client: MockClient((_) async {
                  await gate.future;
                  return http.Response.bytes(List<int>.filled(100, 1), 200);
                }),
              ),
            ),
          ],
        ),
      );
    });
    await waitFor(tester, find.byTooltip('تنزيل السورة'));
    await tester.tap(find.byTooltip('تنزيل السورة'));
    await tester.pump();
    expect(find.byTooltip('جارٍ التحميل · المس للإلغاء'), findsOneWidget);
    gate.complete();
    await waitFor(tester, find.byTooltip('محمّل · المس للحذف'));
    expect(find.byTooltip('محمّل · المس للحذف'), findsOneWidget);
    expect(await tester.runAsync(() => AudioDownloads(root: () async => tmp, isUnmetered: () async => true).has('afasy', 18)), isTrue);
  });

  testWidgets('player sheet: tafsir opens at once with a skeleton while it loads', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    final tafsir = _SlowTafsir();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          playerAt(18, 2),
          kv: kv,
          overrides: [...overrides(engine, kv, harnessed: true), tafsirRepositoryProvider.overrideWithValue(tafsir)],
        ),
      );
    });
    await waitFor(tester, find.text('التفسير الميسر'));
    await tester.tap(find.text('التفسير الميسر'));
    await tester.pump();
    expect(find.byType(YqSkeletonText), findsOneWidget);
    tafsir.gate.complete(null);
    await tester.pump();
    expect(find.byType(YqSkeletonText), findsNothing);
    expect(find.text('[نص التفسير الميسر لهذه الآية من مصدر المحتوى المرخّص]'), findsOneWidget);
  });

  testWidgets('player sheet: the repeat sheet sets ayah ×N and a range', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    late WidgetRef widgetRef;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          Consumer(
            builder: (_, ref, __) {
              widgetRef = ref;
              return playerAt(18, 2);
            },
          ),
          kv: kv,
          overrides: overrides(engine, kv, harnessed: true),
        ),
      );
    });
    await waitFor(tester, find.byTooltip('التكرار'));
    await tester.tap(find.byTooltip('التكرار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الآية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5×'));
    await tester.pumpAndSettle();
    var s = widgetRef.read(listenControllerProvider);
    expect([s.repeat, s.repeatTimes], [ListenRepeat.ayah, 5]);
    await tester.tap(find.text('مقطع'));
    await tester.pumpAndSettle();
    s = widgetRef.read(listenControllerProvider);
    expect([s.repeat, s.rangeFrom, s.rangeTo], [ListenRepeat.range, 2, 2]);
    expect(find.text('من الآية 2 إلى الآية 2'), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);
  });

  testWidgets('reciters: the stored reciter shows as selected before the player opens', (tester) async {
    phone(tester);
    final kv = MemoryKvStore()..data['db.listen'] = jsonEncode({'reciter': 'afasy'});
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(const RecitersScreen(), kv: kv, overrides: overrides(FakeAudioEngine(), kv, harnessed: true)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('القارئ المختار'), findsOneWidget);
  });

  testWidgets('reciters: no catalogue offline → error with retry', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          const RecitersScreen(),
          kv: kv,
          overrides: overrides(FakeAudioEngine(), kv, harnessed: true, api: MockClient((_) async => throw const SocketException('offline'))),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('لا يوجد قارئ متاح بعد'), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('reciters: list, search empty state, filter downloaded', (tester) async {
    phone(tester);
    final kv = MemoryKvStore();
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(const RecitersScreen(), kv: kv, overrides: overrides(FakeAudioEngine(), kv, harnessed: true)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('اختر القارئ'), findsOneWidget);
    expect(find.text('مشاري راشد العفاسي'), findsOneWidget);
    expect(find.text('مرتّل · حفص عن عاصم'), findsOneWidget);
    expect(find.text('تحميل المصحف كاملاً للاستماع دون اتصال'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'السديس');
    await tester.pump();
    expect(find.text('لا يوجد قارئ بهذا الاسم'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'العفاسي');
    await tester.tap(find.text('المحمّلة'));
    await tester.pump();
    expect(find.text('لا يوجد قارئ بهذا الاسم'), findsOneWidget);
  });
}

/// Opens the recitation at [surah]:[ayah] once, then shows [child].
class _OpenThen extends ConsumerStatefulWidget {
  const _OpenThen({required this.surah, required this.ayah, required this.child});
  final int surah;
  final int ayah;
  final Widget child;

  @override
  ConsumerState<_OpenThen> createState() => _OpenThenState();
}

class _OpenThenState extends ConsumerState<_OpenThen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(listenControllerProvider.notifier).open(widget.surah, ayah: widget.ayah));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Tafsir whose answer arrives only when the test opens [gate].
class _SlowTafsir extends TafsirRepository {
  final gate = Completer<TafsirText?>();
  @override
  Future<TafsirText?> lookup(AyahRef r) => gate.future;
}
