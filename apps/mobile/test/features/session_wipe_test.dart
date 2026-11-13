import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/social_auth.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/onboarding/presentation/session_controller.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

String fixture(String name) => File('test/fixtures/community/$name').readAsStringSync();

/// Account deletion wipes the profile, the competitions' caches, the `community` consent and the
/// Quran session; sign-out wipes the account's profile but keeps on-device Quran data (design §8).
void main() {
  late MemoryKvStore kv;
  late MemoryKvStore secure;
  late Directory dir;
  late List<String> calls;
  late List<Object?> bodies;

  setUp(() async {
    kv = MemoryKvStore();
    secure = MemoryKvStore();
    dir = Directory.systemTemp.createTempSync('yq_wipe');
    calls = [];
    bodies = [];
    await TokenStore(secure).save(access: 'a1', refresh: 'r1');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  ProviderContainer container(Session initial, Future<http.Response> Function(http.Request) handler, {SocialAuth? social}) {
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(secure),
        initialSessionProvider.overrideWithValue(initial),
        filesDirProvider.overrideWithValue(() async => dir),
        if (social != null) socialAuthProvider.overrideWithValue(social),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            baseUrl: 'https://api.test',
            tokens: ref.watch(tokenStoreProvider),
            client: MockClient((req) async {
              calls.add('${req.method} ${req.url.path}');
              bodies.add(req.body.isEmpty ? null : jsonDecode(req.body));
              return handler(req);
            }),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A signed-in phone that has a cached profile, competition caches, a photo file, a Quran
  /// session and the `community` consent.
  Future<void> seed(ProviderContainer c) async {
    await kv.write(ProfileRepository.meKey, fixture('me_profile.json'));
    await kv.write(ProfileRepository.lastSeenLevelKey, '3');
    await kv.write('community.league.v1', '{}');
    await kv.write('community.seenWeek', '2026-11-07');
    await kv.write(QuranSessionStore.kvKey, '{"page":3}');
    await c.read(consentRepositoryProvider).adopt(ConsentKind.community, true);
    final photos = Directory('${dir.path}${Platform.pathSeparator}profile')..createSync(recursive: true);
    File('${photos.path}${Platform.pathSeparator}avatar_p1.webp').writeAsBytesSync([1, 2, 3]);
  }

  const google = Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد');

  test('deleteAccount wipes the profile, the community caches and consent, and the Quran session', () async {
    final c = container(google, (_) async => http.Response('', 204));
    await seed(c);

    await c.read(sessionProvider.notifier).deleteAccount();

    expect(calls, contains('DELETE /v1/me'));
    for (final key in ProfileRepository.wipedKeys) {
      expect(kv.data[key], isNull, reason: key);
    }
    expect(kv.data[QuranSessionStore.kvKey], isNull);
    expect(c.read(consentRepositoryProvider).granted(ConsentKind.community), isFalse);
    expect(Directory('${dir.path}${Platform.pathSeparator}profile').existsSync(), isFalse);
    expect(c.read(sessionProvider).signedIn, isFalse);
  });

  test('sign-out forgets the account\'s profile and community consent but keeps the Quran session', () async {
    final c = container(google, (_) async => http.Response('', 204));
    await seed(c);

    await c.read(sessionProvider.notifier).signOut();

    expect(kv.data[ProfileRepository.meKey], isNull);
    expect(kv.data['community.league.v1'], isNull);
    expect(kv.data['community.seenWeek'], isNull);
    expect(c.read(consentRepositoryProvider).granted(ConsentKind.community), isFalse);
    expect(Directory('${dir.path}${Platform.pathSeparator}profile').existsSync(), isFalse);
    expect(kv.data[QuranSessionStore.kvKey], '{"page":3}'); // on-device Quran data stays
  });

  test('a guest who links an account pushes the name they chose on this phone', () async {
    const guest = Session(provider: SignInProvider.guest, userId: 'g1');
    final c = container(
      guest,
      (req) async {
        if (req.url.path == '/v1/auth/link') {
          return json({
            'accessToken': 'a2',
            'refreshToken': 'r2',
            'user': {'id': 'g1', 'displayName': 'Ahmed Hamdy'},
          });
        }
        if (req.method == 'GET' && req.url.path == '/v1/me/profile') {
          return json((jsonDecode(fixture('me_profile.json')) as Map)..['displayName'] = 'Ahmed Hamdy');
        }
        if (req.method == 'PATCH' && req.url.path == '/v1/me/profile') {
          return json((jsonDecode(fixture('me_profile.json')) as Map)..['displayName'] = 'سارة');
        }
        return http.Response('', 204);
      },
      social: FakeSocialAuth(credential: const SocialCredential(idToken: 'id')),
    );
    // Chosen as a guest in onboarding: local only, marked dirty.
    await c.read(profileRepositoryProvider).saveName('سارة');
    expect(calls.where((x) => x.contains('/v1/me/profile')), isEmpty);

    final outcome = await c.read(sessionProvider.notifier).link(SignInProvider.google);

    expect(outcome, SignInOutcome.signedIn);
    expect(calls, containsAllInOrder(['POST /v1/auth/link', 'GET /v1/me/profile', 'PATCH /v1/me/profile']));
    expect(bodies[calls.indexOf('PATCH /v1/me/profile')], {'displayName': 'سارة'});
    expect(kv.data[ProfileRepository.dirtyKey], isNull);
    expect((jsonDecode(kv.data[ProfileRepository.meKey]!) as Map)['displayName'], 'سارة');
  });
}
