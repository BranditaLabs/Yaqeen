import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:math';

import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/config/rollout.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/settings/settings_repository.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';

ApiClient fakeApi(MemoryKvStore secure, Future<http.Response> Function(http.Request r) handler) =>
    ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(secure), client: MockClient(handler));

void main() {
  group('local store', () {
    test('migrates in order once and moves the legacy last-read key', () async {
      final kv = MemoryKvStore()..data['quran.lastRead'] = jsonEncode({'page': 296});
      final store = LocalStore(kv);
      expect(await store.version, 0);
      await store.migrate();
      expect(await store.version, LocalStore.schemaVersion);
      expect((await store.readMap('reading'))['lastRead'], {'page': 296});
      expect(kv.data.containsKey('quran.lastRead'), isFalse);
      await store.migrate(); // idempotent
      expect(await store.version, LocalStore.schemaVersion);
    });
  });

  group('settings', () {
    test('round-trips and tolerates unknown or missing keys', () {
      const s = AppSettings(locale: 'en', quranFontSize: 30, method: CalcMethod.ummAlQura, wirdGoalPages: 4, place: Place.cairo);
      final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.locale, 'en');
      expect(back.quranFontSize, 30);
      expect(back.method, CalcMethod.ummAlQura);
      expect(back.place?.nameAr, 'القاهرة');
      final partial = AppSettings.fromJson({'locale': 'fr', 'quranFontSize': 99, 'future': true});
      expect(partial.locale, 'ar');
      expect(partial.quranFontSize, 34);
      expect(partial.alertModes[PrayerName.sunrise], AlertMode.silent);
      expect(partial.alertModes[PrayerName.isha], AlertMode.notify);
    });

    test('only server fields are patched, coordinates never', () async {
      final kv = MemoryKvStore();
      final outbox = Outbox(kv);
      final repo = SettingsRepository(store: kv, outbox: outbox);
      const a = AppSettings();
      await repo.save(a.copyWith(quranFontSize: 30), previous: a);
      expect(await outbox.items(), isEmpty); // device-only change

      await repo.save(a.copyWith(place: Place.cairo), previous: a);
      await repo.save(a.copyWith(place: Place.cairo, locale: 'en'), previous: a.copyWith(place: Place.cairo));
      final items = await outbox.items();
      expect(items, hasLength(1)); // older patch replaced
      expect(items.single.method, 'PATCH');
      expect(items.single.body, containsPair('locale', 'en'));
      expect(items.single.body, containsPair('city', 'Cairo'));
      expect(items.single.body!.keys, isNot(contains('lat')));
      expect(jsonEncode(items.single.body), isNot(contains('30.04')));
      expect((await repo.load()).locale, 'en');
    });
  });

  group('remote config', () {
    test('parses flags, rollout and points; unknown flags keep defaults', () {
      final c = RemoteConfig.fromJson({
        'features': {'challenge': false, 'recite': true},
        'featureRollout': {'recite': 50},
        'minVersion': {'ios': '1.2.0', 'android': '1.1.0'},
        'maintenance': {'enabled': true, 'messageAr': 'صيانة', 'messageEn': 'Maintenance'},
        'points': {'dailyTotal': 120, 'qadaDayPoints': 60, 'qadaWindowDays': 3, 'challengeLengthDays': 365, 'cheapestRewardPoints': 1000},
      });
      expect(c.isOn(Flags.challenge), isFalse);
      expect(c.isOn(Flags.hifz), isTrue);
      expect(c.isOn(Flags.recite, userId: 'u1'), isFalse); // bucket 53 ≥ 50
      expect(c.isOn(Flags.recite, userId: '00000000-0000-4000-8000-000000000001'), isTrue); // bucket 40
      expect(c.needsUpdate(ios: true, appVersion: '1.1.9'), isTrue);
      expect(c.needsUpdate(ios: false, appVersion: '1.1.0'), isFalse);
      expect(c.dailyTotal, 120);
      expect(c.cheapestRewardPoints, 1000);
    });

    test('caches for an hour and falls back to the cache offline', () async {
      var calls = 0;
      var offline = false;
      var now = DateTime(2026, 10, 20, 9);
      final api = fakeApi(MemoryKvStore(), (r) async {
        calls++;
        if (offline) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({
            'features': {'hifz': false},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = RemoteConfigRepository(api: api, cache: MemoryKvStore(), now: () => now);
      expect((await repo.refresh()).isOn(Flags.hifz), isFalse);
      await repo.refresh();
      expect(calls, 1);
      now = now.add(const Duration(hours: 2));
      offline = true;
      expect((await repo.refresh()).isOn(Flags.hifz), isFalse);
      expect(calls, 2);
    });
  });

  test('rollout buckets match packages/contracts (shared vectors)', () {
    expect(rolloutBucket('u1', 'recite'), 53);
    expect(rolloutBucket('00000000-0000-4000-8000-000000000001', 'recite'), 40);
    expect(rolloutBucket('يقين', 'recite'), 43);
    expect(inRollout(null, 'recite', 50), isFalse);
    expect(inRollout('x', 'recite', null), isTrue);
  });

  test('version compare', () {
    expect(compareVersions('1.10.0', '1.9.3'), 1);
    expect(compareVersions('1.0.0', '1.0.0+5'), 0);
    expect(compareVersions('0.9', '1.0.0'), -1);
  });

  test('outbox sync replays any method in order and reports rejections', () async {
    final secure = MemoryKvStore()..data['auth.access'] = 'tok';
    final seen = <String>[];
    final api = fakeApi(secure, (r) async {
      seen.add('${r.method} ${r.url.path}');
      if (r.url.path.contains('daily_task')) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'outside_qada_window'},
          }),
          400,
        );
      }
      return http.Response('{}', 200);
    });
    final outbox = Outbox(MemoryKvStore());
    final sync = OutboxSync(api: api, outbox: outbox, isSignedIn: () async => true);
    final rejected = <String>[];
    sync.rejected.listen((r) => rejected.add(r.$2.code));
    await outbox.add(OutboxItem(id: '1', method: 'PATCH', path: '/v1/me/settings', body: {'locale': 'en'}));
    await outbox.add(OutboxItem(id: '2', method: 'POST', path: '/v1/challenge/tasks/daily_task/complete', body: {}));
    await outbox.add(OutboxItem(id: '3', method: 'PUT', path: '/v1/me/consents', body: {}));
    expect(await sync.flush(), 3);
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['PATCH /v1/me/settings', 'POST /v1/challenge/tasks/daily_task/complete', 'PUT /v1/me/consents']);
    expect(rejected, ['outside_qada_window']);
    expect(await outbox.items(), isEmpty);
  });

  test('failed flushes back off exponentially with jitter; forced flushes ignore it', () async {
    var now = DateTime(2026, 10, 20, 9);
    var calls = 0;
    final api = fakeApi(MemoryKvStore(), (_) async {
      calls++;
      return http.Response(
        jsonEncode({
          'error': {'code': 'overloaded'},
        }),
        503,
      );
    });
    final outbox = Outbox(MemoryKvStore());
    await outbox.add(OutboxItem(id: '1', method: 'POST', path: '/x'));
    final sync = OutboxSync(api: api, outbox: outbox, isSignedIn: () async => true, now: () => now, random: Random(1));
    await sync.flush();
    expect(calls, 1);
    final first = sync.retryAfter!.difference(now);
    expect(first, lessThanOrEqualTo(OutboxSync.baseDelay));
    await sync.flush(); // still backing off
    expect(calls, 1);
    await sync.flush(force: true);
    expect(calls, 2);
    for (var i = 0; i < 12; i++) {
      now = sync.retryAfter!.add(const Duration(seconds: 1));
      await sync.flush();
    }
    expect(sync.retryAfter!.difference(now), lessThanOrEqualTo(OutboxSync.maxDelay));
    expect(await outbox.length, 1); // 503 is retryable — never dropped
  });

  test('signed-out sync keeps the queue', () async {
    final outbox = Outbox(MemoryKvStore());
    await outbox.add(OutboxItem(id: '1', method: 'POST', path: '/x'));
    final sync =
        OutboxSync(api: fakeApi(MemoryKvStore(), (_) async => http.Response('{}', 200)), outbox: outbox, isSignedIn: () async => false);
    expect(await sync.flush(), 0);
    expect(await outbox.length, 1);
  });

  test('deep links cover the sub-routes and universal links', () {
    expect(routeForDeepLink(Uri.parse('yaqeen://calendar')), '/challenge/calendar');
    expect(routeForDeepLink(Uri.parse('yaqeen://azkar')), '/home/azkar');
    expect(routeForDeepLink(Uri.parse('yaqeen://hifz')), '/quran/hifz');
    expect(routeForDeepLink(Uri.parse('https://yaqin-brand.com/app/redeem')), '/challenge/redeem');
    expect(routeForDeepLink(Uri.parse('https://yaqin-brand.com/app/nope')), '/home');
  });
}
