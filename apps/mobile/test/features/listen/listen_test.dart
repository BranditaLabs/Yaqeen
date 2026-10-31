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
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/listen/data/audio_downloads.dart';
import 'package:yaqeen/features/listen/data/reciter_repository.dart';
import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/listen/presentation/now_playing_screen.dart';
import 'package:yaqeen/features/listen/presentation/reciters_screen.dart';
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

  List<Override> overrides(FakeAudioEngine engine, MemoryKvStore kv, {bool harnessed = false}) => [
        if (!harnessed) ...[kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore())],
        audioEngineProvider.overrideWithValue(engine),
        filesDirProvider.overrideWithValue(() async => tmp),
        quranDataProvider.overrideWith((_) async => q),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(MemoryKvStore()), client: fakeServer()),
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

  testWidgets('now playing: surah card, reciter, current ayah and play/pause', (tester) async {
    phone(tester);
    final engine = FakeAudioEngine();
    final kv = MemoryKvStore();
    await tester.runAsync(() async {
      await tester
          .pumpWidget(harness(const NowPlayingScreen(surah: 18, ayah: 2), kv: kv, overrides: overrides(engine, kv, harnessed: true)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('يُشغَّل الآن'), findsOneWidget);
    expect(find.text('الكهف'), findsOneWidget);
    expect(find.text('مشاري راشد العفاسي'), findsOneWidget);
    expect(find.text('السورة 18 · مكية · 110 آيات'), findsOneWidget);
    expect(find.textContaining('﴿٢﴾'), findsOneWidget);
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    await tester.tap(find.byTooltip('إيقاف مؤقت'));
    await tester.pump();
    expect(find.byTooltip('تشغيل'), findsOneWidget);
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
