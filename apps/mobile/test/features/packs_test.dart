import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/network/resumable_download.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/content/data/pack_repository.dart';
import 'package:yaqeen/features/content/domain/content_pack.dart';
import 'package:yaqeen/features/onboarding/presentation/onboarding_screens.dart';
import 'package:yaqeen/features/quran/data/tafsir_repository.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

// Bracketed test text only — never real tafsir (rule 9).
final packBody = utf8.encode(jsonEncode({'1:1': '[نص تفسير تجريبي]'}));
final packSha = sha256.convert(packBody).toString();

Map<String, Object> packJson({int version = 1, String? sha}) => {
      'id': 'tafsir-test',
      'kind': 'tafsir',
      'titleAr': 'التفسير الميسر',
      'titleEn': 'Al-Muyassar',
      'version': version,
      'url': 'https://cdn.test/tafsir-test.json',
      'sha256': sha ?? packSha,
      'sizeBytes': packBody.length,
    };

void main() {
  late Directory tmp;
  setUpAll(loadAppFonts);
  setUp(() async {
    YqGlassConfig.enableBlur = false;
    tmp = await Directory.systemTemp.createTemp('yq_packs');
  });
  tearDown(() async => tmp.delete(recursive: true));

  http.Response json(Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  PackRepository repo({required List<Object> catalogue, List<int>? body, bool online = true, bool wifi = true, KvStore? kv}) {
    final client = MockClient((req) async {
      if (!online) throw http.ClientException('offline');
      if (req.url.path == '/v1/content/packs') return json(catalogue);
      return http.Response.bytes(body ?? packBody, 200);
    });
    final store = kv ?? MemoryKvStore();
    return PackRepository(
      api: ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(MemoryKvStore()), client: client),
      cache: store,
      store: LocalStore(store),
      root: () async => tmp,
      isUnmetered: () async => wifi,
      client: client,
    );
  }

  test('catalogue parses, drops rows with a bad checksum, and survives offline from cache', () async {
    final kv = MemoryKvStore();
    final list = await repo(catalogue: [packJson(), packJson(sha: 'nope')], kv: kv).catalogue();
    expect(list.map((p) => p.id), ['tafsir-test']);
    final offline = await repo(catalogue: const [], online: false, kv: kv).catalogue();
    expect(offline.single.kind, PackKind.tafsir);
  });

  test('a verified pack installs and the tafsir comes from it', () async {
    final r = repo(catalogue: [packJson()]);
    final pack = (await r.catalogue()).single;
    final tafsir = TafsirRepository(packFile: () => r.installedFile(PackKind.tafsir));
    expect(await tafsir.forAyah(const AyahRef(1, 1)), isNull); // placeholder until installed
    await r.install(pack);
    expect(await TafsirRepository(packFile: () => r.installedFile(PackKind.tafsir)).forAyah(const AyahRef(1, 1)), '[نص تفسير تجريبي]');
    expect(await r.installedVersion('tafsir-test'), 1);
    expect(await r.bytesOnDisk(), packBody.length);
    await r.remove('tafsir-test');
    expect(await r.installedFile(PackKind.tafsir), isNull);
  });

  test('a checksum mismatch installs nothing', () async {
    final r = repo(catalogue: [packJson()], body: utf8.encode('tampered'));
    final pack = (await r.catalogue()).single;
    await expectLater(r.install(pack), throwsA(isA<PackChecksumMismatch>()));
    expect(await r.installedFile(PackKind.tafsir), isNull);
    expect(await r.bytesOnDisk(), 0);
  });

  test('waits for Wi-Fi unless mobile data is allowed', () async {
    final r = repo(catalogue: [packJson()], wifi: false);
    final pack = (await r.catalogue()).single;
    await expectLater(r.install(pack), throwsA(isA<WifiRequired>()));
    await r.install(pack, allowMetered: true);
    expect(await r.installedVersion('tafsir-test'), 1);
  });

  test('weekly check: once per 7 days, only newer versions of installed packs', () async {
    final kv = MemoryKvStore();
    final day0 = DateTime(2026, 10, 20);
    final v1 = repo(catalogue: [packJson()], kv: kv);
    expect(await v1.checkWeekly(day0), isEmpty); // nothing installed yet
    await v1.install((await v1.catalogue()).single);
    final v2 = repo(catalogue: [packJson(version: 2)], kv: kv);
    expect(await v2.checkWeekly(day0.add(const Duration(days: 3))), isEmpty); // too soon
    expect((await v2.checkWeekly(day0.add(const Duration(days: 8)))).single.version, 2);
    expect(needsUpdate(null, ContentPack.tryParse(packJson(version: 2))!), isFalse);
  });

  testWidgets('onboarding 06 lists the tafsir pack once the catalogue has one', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = MockClient((req) async => json([packJson()]));
    await tester.pumpWidget(
      harness(
        const DownloadStep(),
        overrides: [
          filesDirProvider.overrideWithValue(() async => tmp),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: client),
          ),
        ],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('التفسير الميسر'), findsOneWidget);
    expect(find.textContaining('تحميل ·'), findsOneWidget);
    expect(find.text('متاح بعد اعتماد المصدر المرخّص'), findsNothing);
  });
}
