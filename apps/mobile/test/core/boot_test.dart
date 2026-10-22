import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/app/bootstrap.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/settings/settings_repository.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';

void main() {
  group('Boot.step never blocks start-up', () {
    test('a throwing step yields its fallback', () async {
      expect(await Boot.step<int>('x', () async => throw StateError('plugin'), 7), 7);
    });

    test('a step that never answers yields its fallback after the limit', () async {
      final v = await Boot.step<int>('x', () => Future.delayed(const Duration(seconds: 5), () => 1), 7, limit: const Duration(milliseconds: 20));
      expect(v, 7);
    });

    test('a healthy step yields its value', () async {
      expect(await Boot.step<int>('x', () async => 1, 7), 1);
    });
  });

  group('corrupt caches start with defaults instead of a dead app', () {
    late MemoryKvStore kv;
    late ApiClient api;
    setUp(() {
      kv = MemoryKvStore();
      api = ApiClient(baseUrl: 'http://localhost', tokens: TokenStore(MemoryKvStore()));
    });

    test('settings: wrong types (TypeError) and torn JSON', () async {
      final repo = SettingsRepository(store: kv, outbox: Outbox(kv));
      kv.data['settings.v1'] = '{"locale": 42, "onboarded": "yes"}';
      expect(await repo.load(), isA<AppSettings>());
      kv.data['settings.v1'] = '{"locale": "a';
      expect(await repo.load(), isA<AppSettings>());
    });

    test('remote config', () async {
      final repo = RemoteConfigRepository(api: api, cache: kv);
      kv.data['cache.config'] = '{"config": 3';
      expect(await repo.cached(), isA<RemoteConfig>());
      expect(kv.data.containsKey('cache.config'), isFalse);
      kv.data['cache.config'] = '[1,2]';
      expect(await repo.cached(), isA<RemoteConfig>());
    });

    test('session falls back to a guest', () async {
      kv.data['auth.session'] = '{"provider": 5';
      final s = await AuthRepository(api: api, tokens: TokenStore(MemoryKvStore()), store: kv).load();
      expect(s.userId, Session.none.userId);
    });

    test('consents stay off', () async {
      kv.data['consents.v1'] = 'not json';
      final c = ConsentRepository(api: api, store: kv);
      await c.load();
      expect(c.all.values, everyElement(isFalse));
    });

    test('a torn local collection reads as empty', () async {
      kv.data['db.reading'] = '{"lastRead": {';
      expect(await LocalStore(kv).readMap('reading'), isEmpty);
    });
  });
}
