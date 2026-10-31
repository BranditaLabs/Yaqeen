import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/audio_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/features/listen/data/audio_downloads.dart';
import 'package:yaqeen/features/listen/data/reciter_repository.dart';
import 'package:yaqeen/features/listen/domain/audio_models.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/data/tafsir_repository.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

/// Quran.com / Quran Foundation audio + tafsir through our API (spec §10): the app resolves each
/// surah, caches the answer for offline, falls back to the cached copy, and refreshes weekly.
const qfReciter = {
  'id': 'alafasy',
  'nameAr': 'مشاري راشد العفاسي',
  'nameEn': 'Mishary Rashid Alafasy',
  'style': 'murattal',
  'riwaya': 'hafs',
  'source': 'qf',
  'qfId': 7,
  'hasTimings': true,
  'baseUrl': null,
  'timingUrl': null,
  'sampleUrl': null,
  'sizeBytes': 1722899470,
};

List<List<int>> spans(int n) => [
      for (var i = 0; i < n; i++) [i * 10000, (i + 1) * 10000],
    ];

Map<String, Object?> surahJson(int s, int ayat) => {
      'reciterId': 'alafasy',
      'surah': s,
      'url': 'https://download.quranicaudio.test/qdc/mishari_al_afasy/murattal/$s.mp3',
      'sizeBytes': 1000,
      'durationMs': ayat * 10000,
      'timings': spans(ayat),
    };

/// Our API (+ the audio CDN for file bytes); `online = false` makes every request fail.
class FakeApi {
  bool online = true;
  final requests = <String>[];
  final audio = List<int>.generate(1000, (i) => i % 256);

  http.Client client() => MockClient((req) async {
        requests.add(req.url.path);
        if (!online) throw const SocketException('offline');
        final p = req.url.path;
        http.Response j(Object body) =>
            http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        if (p == '/v1/content/reciters') return j([qfReciter]);
        final m = RegExp(r'^/v1/content/reciters/alafasy/surahs/(\d+)$').firstMatch(p);
        if (m != null) {
          final s = int.parse(m.group(1)!);
          return j(surahJson(s, s == 1 ? 7 : 110));
        }
        if (p == '/v1/content/reciters/alafasy/timings') return j({'1': spans(7), '18': spans(110)});
        if (p == '/v1/content/tafsirs') {
          return j([
            {
              'id': 'muyassar',
              'nameAr': 'التفسير الميسر',
              'nameEn': 'Al-Muyassar',
              'language': 'ar',
              'attribution': 'Quran.com · Quran Foundation',
            },
            {
              'id': 'saadi',
              'nameAr': 'تفسير السعدي',
              'nameEn': "As-Sa'di",
              'language': 'ar',
              'attribution': 'Quran.com · Quran Foundation',
            },
          ]);
        }
        final t = RegExp(r'^/v1/content/tafsirs/([a-z-]+)/surahs/(\d+)$').firstMatch(p);
        if (t != null) {
          return j({
            'tafsirId': t.group(1),
            'surah': int.parse(t.group(2)!),
            'attribution': 'Quran.com · Quran Foundation',
            'ayat': {'2:8': '[${t.group(1)} 2:8-9]', '2:10': '[${t.group(1)} 2:10]'},
          });
        }
        if (req.url.host == 'download.quranicaudio.test') return http.Response.bytes(audio, 200);
        return http.Response('{"error":{"code":"not_found"}}', 404);
      });
}

void main() {
  late Directory tmp;
  late FakeApi server;
  late DateTime now;
  final reciter = Reciter.tryParse(qfReciter)!;
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);

  setUpAll(Zoned.ensureInitialized);
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('yq_qf');
    server = FakeApi();
    now = DateTime.utc(2026, 10, 31, 12);
  });
  tearDown(() async => tmp.delete(recursive: true));

  ApiClient api() => ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(MemoryKvStore()), client: server.client());
  ReciterRepository repo(KvStore kv) => ReciterRepository(api: api(), cache: kv, root: () async => tmp, now: () => now);
  int hits(String path) => server.requests.where((r) => r == path).length;

  group('model', () {
    test('a Quran Foundation reciter has no CDN base; it samples Al-Fatiha', () {
      expect(reciter.isQf, isTrue);
      expect(reciter.qfId, 7);
      expect(reciter.hasTimings, isTrue);
      expect(reciter.surahUrl(1), isNull);
      expect(reciter.hasSample, isTrue);
      expect(Reciter.tryParse(jsonDecode(jsonEncode(reciter.toJson())))!.isQf, isTrue);
    });

    test('an older cached catalogue (no source) still parses as own-CDN', () {
      final old = Reciter.tryParse({
        'id': 'x',
        'nameAr': 'س',
        'nameEn': 'X',
        'style': 'mujawwad',
        'riwaya': 'hafs',
        'baseUrl': 'https://cdn.test/x',
        'timingUrl': null,
        'sampleUrl': null,
        'sizeBytes': 1,
      })!;
      expect(
        [old.source, old.hasTimings, old.hasSample, old.surahUrl(2).toString()],
        [ReciterSource.own, false, false, 'https://cdn.test/x/002.mp3'],
      );
      expect(Reciter.tryParse({...qfReciter, 'style': 'muallim'})!.style, RecitationStyle.muallim);
    });
  });

  group('resolver', () {
    test('resolves once, then serves the cached URL + timings (also offline)', () async {
      final kv = MemoryKvStore();
      final r = repo(kv);
      final a = (await r.surahAudio(reciter, 18))!;
      expect(a.url.toString(), 'https://download.quranicaudio.test/qdc/mishari_al_afasy/murattal/18.mp3');
      expect(a.timings!.ayahCount, 110);
      expect(kv.data.keys, contains(ReciterRepository.audioKey('alafasy', 18)));

      // A fresh repository (app restart) offline still has it.
      server.online = false;
      final again = repo(kv);
      expect((await again.surahAudio(reciter, 18))!.url, a.url);
      expect((await again.timings(reciter, 18))!.startOf(3), const Duration(seconds: 20));
      expect(hits('/v1/content/reciters/alafasy/surahs/18'), 1);
    });

    test('a week-old copy is refreshed online; offline it keeps working; nothing cached → null', () async {
      final kv = MemoryKvStore();
      await repo(kv).surahAudio(reciter, 18);
      now = now.add(const Duration(days: 8));
      await repo(kv).surahAudio(reciter, 18);
      expect(hits('/v1/content/reciters/alafasy/surahs/18'), 2);

      now = now.add(const Duration(days: 8));
      server.online = false;
      expect(await repo(kv).surahAudio(reciter, 18), isNotNull);
      expect(await repo(kv).surahAudio(reciter, 19), isNull);
      expect(() => repo(kv).surahUri(reciter, 19), throwsA(isA<OfflineException>()));
    });

    test('a full download saves every surah\'s timings next to the files', () async {
      final kv = MemoryKvStore();
      expect(await repo(kv).saveOfflineTimings(reciter), isTrue);
      expect(await AudioDownloads.timingsFileIn(tmp, 'alafasy').exists(), isTrue);
      server.online = false;
      final t = await repo(MemoryKvStore()).timings(reciter, 1); // empty KV: only the file has it
      expect(t!.ayahCount, 7);
    });

    test('downloads write the resolved file; a downloaded surah plays from disk', () async {
      final kv = MemoryKvStore();
      final r = repo(kv);
      final d = AudioDownloads(root: () async => tmp, isUnmetered: () async => true, resolve: r.surahUri, client: server.client());
      await d.downloadSurah(reciter, 18);
      expect(await d.has('alafasy', 18), isTrue);
      expect((await d.sourceFor(reciter, 18)).scheme, 'file');
      expect((await d.sourceFor(reciter, 2)).host, 'download.quranicaudio.test');
    });
  });

  group('player', () {
    List<Override> overrides(FakeAudioEngine engine, MemoryKvStore kv) => [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          audioEngineProvider.overrideWithValue(engine),
          filesDirProvider.overrideWithValue(() async => tmp),
          quranDataProvider.overrideWith((_) async => q),
          clockProvider.overrideWithValue(() => now),
          apiClientProvider.overrideWithValue(api()),
        ];

    test('opens a surah at an ayah with the resolved URL and synced timings', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      await c.read(listenControllerProvider.notifier).open(18, ayah: 3);
      final s = c.read(listenControllerProvider);
      expect(s.status, ListenStatus.ready);
      expect(s.synced, isTrue);
      expect(engine.opened.single.toString(), 'https://download.quranicaudio.test/qdc/mishari_al_afasy/murattal/18.mp3');
      expect(engine.current, const Duration(seconds: 20));
    });

    test('the sample plays Al-Fatiha through the resolver', () async {
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      await c.read(listenControllerProvider.notifier).playSample(reciter);
      expect(engine.opened.single.toString(), endsWith('/murattal/1.mp3'));
      expect(c.read(listenControllerProvider).sampleOf, 'alafasy');
    });

    test('offline with nothing cached → unavailable (no crash)', () async {
      server.online = false;
      final engine = FakeAudioEngine();
      final c = ProviderContainer(overrides: overrides(engine, MemoryKvStore()));
      addTearDown(c.dispose);
      await c.read(listenControllerProvider.notifier).open(18, reciter: reciter);
      expect(c.read(listenControllerProvider).status, ListenStatus.unavailable);
    });
  });

  group('tafsir', () {
    TafsirRepository tafsir(KvStore kv, {Future<File?> Function()? pack}) =>
        TafsirRepository(api: api(), store: kv, root: () async => tmp, now: () => now, packFile: pack);

    test('fetches a surah once, caches it on disk, reads it offline; grouped ayat share a commentary', () async {
      final kv = MemoryKvStore();
      final t = await tafsir(kv).lookup(const AyahRef(2, 8));
      expect([t!.text, t.source, t.tafsirId], ['[muyassar 2:8-9]', TafsirSource.qf, 'muyassar']);
      server.online = false;
      final offline = tafsir(kv);
      expect(await offline.forAyah(const AyahRef(2, 9)), '[muyassar 2:8-9]');
      expect(await offline.forAyah(const AyahRef(2, 10)), '[muyassar 2:10]');
      expect(await offline.forAyah(const AyahRef(2, 1)), isNull); // nothing before 2:8 in this surah
      expect(await offline.forAyah(const AyahRef(3, 1)), isNull); // never fetched → placeholder
      expect(hits('/v1/content/tafsirs/muyassar/surahs/2'), 1);
    });

    test('a week-old copy is refreshed when online', () async {
      final kv = MemoryKvStore();
      await tafsir(kv).forAyah(const AyahRef(2, 8));
      now = now.add(const Duration(days: 8));
      await tafsir(kv).forAyah(const AyahRef(2, 8));
      expect(hits('/v1/content/tafsirs/muyassar/surahs/2'), 2);
    });

    test('choosing another tafsir switches the source; the list is cached for offline', () async {
      final kv = MemoryKvStore();
      final r = tafsir(kv);
      expect((await r.list()).map((x) => x.id), ['muyassar', 'saadi']);
      await r.select('saadi');
      expect(await r.forAyah(const AyahRef(2, 8)), '[saadi 2:8-9]');
      server.online = false;
      expect((await tafsir(kv).list()).length, 2);
      expect(await tafsir(kv).selected(), 'saadi');
    });

    test('an installed pack wins over the API', () async {
      final f = File('${tmp.path}/tafsir_pack.json')..writeAsStringSync(jsonEncode({'2:8': '[نص من الحزمة]'}));
      final t = await tafsir(MemoryKvStore(), pack: () async => f).lookup(const AyahRef(2, 8));
      expect([t!.text, t.source], ['[نص من الحزمة]', TafsirSource.pack]);
      expect(hits('/v1/content/tafsirs/muyassar/surahs/2'), 0);
    });
  });
}
