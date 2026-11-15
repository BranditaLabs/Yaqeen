import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/onboarding/presentation/session_controller.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _invalidRefresh = {
  'error': {'code': 'unauthorized', 'message': 'invalid_refresh_token'},
};

http.Response refused() => json(_invalidRefresh, 401);

Future<MemoryKvStore> signedIn({String access = 'a1', String refresh = 'r1'}) async {
  final secure = MemoryKvStore();
  await TokenStore(secure).save(access: access, refresh: refresh);
  return secure;
}

void main() {
  group('ApiClient refresh', () {
    test('two parallel 401s share one refresh; both retry with the new token', () async {
      final secure = await signedIn();
      var refreshes = 0;
      final refreshGate = Completer<void>();
      final api = ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(secure),
        client: MockClient((req) async {
          if (req.url.path == '/v1/auth/refresh') {
            refreshes++;
            await refreshGate.future;
            // The server rotates: the same refresh token a second time is refused.
            if ((jsonDecode(req.body) as Map)['refreshToken'] != 'r1' || refreshes > 1) return refused();
            return json({'accessToken': 'a2', 'refreshToken': 'r2'});
          }
          if (req.headers['Authorization'] != 'Bearer a2') return refused();
          return json({'path': req.url.path});
        }),
      );
      var expired = 0;
      api.onSessionExpired = () => expired++;

      final a = api.get('/v1/challenge/summary');
      final b = api.get('/v1/challenge/days');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      refreshGate.complete();
      expect(await a, {'path': '/v1/challenge/summary'});
      expect(await b, {'path': '/v1/challenge/days'});
      expect(refreshes, 1);
      expect(expired, 0);
      expect(await TokenStore(secure).refreshToken, 'r2');
    });

    test('a 5xx or network failure on refresh keeps the session', () async {
      final secure = await signedIn();
      var status = 503;
      final api = ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(secure),
        client: MockClient((req) async {
          if (req.url.path == '/v1/auth/refresh') {
            if (status == 0) throw http.ClientException('offline');
            return http.Response('<html>Service Unavailable</html>', status);
          }
          return refused();
        }),
      );
      var expired = 0;
      api.onSessionExpired = () => expired++;

      await expectLater(api.get('/v1/me/points'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 503)));
      status = 429;
      await expectLater(api.get('/v1/me/points'), throwsA(isA<ApiException>().having((e) => e.isPermanent, 'permanent', false)));
      status = 0;
      await expectLater(api.get('/v1/me/points'), throwsA(isA<OfflineException>()));
      expect(expired, 0);
      expect(await TokenStore(secure).refreshToken, 'r1');
    });

    test('a refused refresh token clears the tokens and ends the session once', () async {
      final secure = await signedIn();
      final api = ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(secure), client: MockClient((_) async => refused()));
      var expired = 0;
      api.onSessionExpired = () => expired++;
      final results = await Future.wait([
        api.get('/v1/me/points').then<Object?>((v) => v, onError: (Object e) => e),
        api.get('/v1/me/inbox').then<Object?>((v) => v, onError: (Object e) => e),
      ]);
      expect(results, everyElement(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(expired, 1);
      expect(await TokenStore(secure).accessToken, isNull);
    });

    test('a non-JSON error body is an ApiException, never a FormatException', () async {
      final api = ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(MemoryKvStore()),
        client: MockClient((_) async => http.Response('<html>502 Bad Gateway</html>', 502)),
      );
      await expectLater(
        api.put('/v1/me/consents', {'kind': 'store_offers'}),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 502).having((e) => e.code, 'code', 'error')),
      );
    });
  });

  test('outbox keeps the queue on 401 (the session, not the write, failed)', () async {
    final box = Outbox(MemoryKvStore());
    for (final id in ['a', 'b']) {
      await box.add(OutboxItem(id: id, method: 'POST', path: '/v1/challenge/tasks/fajr/complete'));
    }
    expect(await box.flush((_) async => throw ApiException(401, 'unauthorized')), 0);
    expect((await box.items()).map((e) => e.id), ['a', 'b']);
  });

  group('guest sign-in', () {
    AuthRepository repo(http.Response Function() res) {
      final secure = MemoryKvStore();
      return AuthRepository(
        api: ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(secure), client: MockClient((_) async => res())),
        tokens: TokenStore(secure),
        store: MemoryKvStore(),
      );
    }

    test('a 5xx or 429 continues as an offline guest; other refusals surface', () async {
      expect((await repo(() => http.Response('', 503)).continueAsGuest()).pendingServer, isTrue);
      expect((await repo(() => json({'error': {'code': 'rate_limited'}}, 429)).continueAsGuest()).pendingServer, isTrue);
      await expectLater(repo(() => json({'error': {'code': 'bad_request'}}, 400)).continueAsGuest(), throwsA(isA<ApiException>()));
    });
  });

  group('session controller', () {
    late MemoryKvStore kv;
    late MemoryKvStore secure;
    late List<String> calls;

    ProviderContainer container(Session initial, Future<http.Response> Function(http.Request) handler) {
      calls = [];
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          secureStoreProvider.overrideWithValue(secure),
          initialSessionProvider.overrideWithValue(initial),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              baseUrl: 'https://api.test',
              tokens: ref.watch(tokenStoreProvider),
              client: MockClient((req) {
                calls.add('${req.method} ${req.url.path}');
                return handler(req);
              }),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      kv = MemoryKvStore();
      secure = MemoryKvStore();
    });

    test('an offline guest gets one server account even when start and reconnect race', () async {
      final c = container(const Session(provider: SignInProvider.guest, pendingServer: true), (req) async {
        if (req.url.path == '/v1/auth/sign-in') {
          return json({
            'accessToken': 'a1',
            'refreshToken': 'r1',
            'user': {'id': 'u1', 'displayName': null},
          });
        }
        return http.Response('', 204);
      });
      final s = c.read(sessionProvider.notifier);
      await Future.wait([s.ensureServerAccount(), s.ensureServerAccount()]);
      expect(calls.where((x) => x == 'POST /v1/auth/sign-in'), hasLength(1));
      expect(c.read(sessionProvider).userId, 'u1');
      expect(c.read(sessionProvider).pendingServer, isFalse);
    });

    test('an ended session signs the UI out but keeps queued ticks for the next sign-in', () async {
      secure = await signedIn();
      await Outbox(kv).add(OutboxItem(id: 't', method: 'POST', path: '/v1/challenge/tasks/fajr/complete'));
      await kv.write('cache.challenge.summary', '{}');
      final c = container(const Session(provider: SignInProvider.google, userId: 'u1'), (_) async => refused());
      c.read(apiClientProvider).onSessionExpired = () => c.read(sessionProvider.notifier).expire().ignore();
      await expectLater(c.read(apiClientProvider).get('/v1/me/points'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionProvider).signedIn, isFalse);
      expect(await Outbox(kv).length, 1);
      expect(kv.data['cache.challenge.summary'], isNull);
      expect(await c.read(sessionProvider.notifier).expire(), isFalse); // only once
    });

    test('sign-out drops the account\'s queued writes and cached months', () async {
      secure = await signedIn();
      final c = container(const Session(provider: SignInProvider.google, userId: 'u1'), (req) async {
        if (req.url.path == '/v1/challenge/calendar') return json({'month': req.url.queryParameters['month']});
        if (req.url.path == '/v1/auth/sign-out') return http.Response('', 204);
        throw http.ClientException('offline'); // queued writes can't go out
      });
      final repo = c.read(challengeRepositoryProvider);
      await expectLater(repo.calendar('2026-11'), throwsA(anything)); // body isn't a full calendar — cached anyway
      await Outbox(kv).add(OutboxItem(id: 't', method: 'POST', path: '/v1/challenge/tasks/fajr/complete'));
      await Outbox(kv).add(OutboxItem(id: 's', method: 'PATCH', path: '/v1/me/settings'));
      expect(kv.data['cache.challenge.calendar.2026-11'], isNotNull);

      await c.read(sessionProvider.notifier).signOut();
      expect(c.read(sessionProvider).signedIn, isFalse);
      expect(await Outbox(kv).length, 0);
      expect(kv.data.keys.where((k) => k.startsWith('cache.challenge.')), isEmpty);
      expect(await TokenStore(secure).accessToken, isNull);
    });
  });

  test('a consent tap is recorded at once; the event waits through a failing server', () async {
    final kv = MemoryKvStore();
    var status = 502;
    final repo = ConsentRepository(
      api: ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(MemoryKvStore()),
        client: MockClient((_) async => http.Response('', status)),
      ),
      store: kv,
    );
    await repo.record(ConsentKind.storeOffers, true, ConsentSource.settings);
    expect(repo.granted(ConsentKind.storeOffers), isTrue);
    await repo.syncAll();
    expect(await repo.pending(ConsentKind.storeOffers), isTrue); // 502 never drops a PDPL record
    status = 204;
    await Future.wait([repo.syncAll(), repo.syncAll()]);
    expect(await repo.pending(ConsentKind.storeOffers), isFalse);
  });
}
