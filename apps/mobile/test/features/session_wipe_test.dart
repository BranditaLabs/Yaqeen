import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/photo_picker.dart';
import 'package:yaqeen/core/platform/social_auth.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/onboarding/presentation/session_controller.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';
import 'package:yaqeen/features/profile/presentation/me_profile_controller.dart';
import 'package:yaqeen/features/quran/data/session_store.dart';

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

String fixture(String name) => File('test/fixtures/community/$name').readAsStringSync();

Object? _decode(http.Request req) {
  if (req.bodyBytes.isEmpty) return null;
  try {
    return jsonDecode(req.body);
  } on Object {
    return req.bodyBytes; // a photo upload
  }
}

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
              bodies.add(_decode(req));
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

  test("the next account is never compared with the previous account's level (no false level-up)", () async {
    Map<String, dynamic> profileAt(int points) => (jsonDecode(fixture('me_profile.json')) as Map).cast<String, dynamic>()
      ..remove('level')
      ..['lifetimePoints'] = points;
    var serverPoints = 800; // level 2
    final c = container(
      google,
      (req) async {
        if (req.url.path == '/v1/auth/sign-in') {
          return json({
            'accessToken': 'a2',
            'refreshToken': 'r2',
            'user': {'id': 'u2', 'displayName': 'Sara Ali'},
          });
        }
        if (req.method == 'GET' && req.url.path == '/v1/me/profile') return json(profileAt(serverPoints));
        return http.Response('', 204);
      },
      social: FakeSocialAuth(credential: const SocialCredential(idToken: 'id')),
    );
    await kv.write(ProfileRepository.meKey, jsonEncode(profileAt(800)));
    await kv.write(ProfileRepository.lastSeenLevelKey, '2');
    final sub = c.listen(levelUpProvider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue(times: 50);
    expect(c.read(meProfileProvider).valueOrNull?.level.level, 2);
    expect(c.read(levelUpProvider).pending, isFalse);

    await c.read(sessionProvider.notifier).signOut();
    await pumpEventQueue(times: 50);
    serverPoints = 6000; // the next account is level 4
    final outcome = await c.read(sessionProvider.notifier).signInWith(SignInProvider.google);
    expect(outcome, SignInOutcome.signedIn);
    await pumpEventQueue(times: 100);

    expect(c.read(meProfileProvider).valueOrNull?.level.level, 4);
    expect(c.read(levelUpProvider).pending, isFalse);
    expect(kv.data[ProfileRepository.lastSeenLevelKey], '4');

    // A real level-up of the new account is still a moment.
    serverPoints = 13000; // level 5
    await c.read(meProfileProvider.notifier).refresh();
    await pumpEventQueue(times: 20);
    expect(c.read(levelUpProvider).pending, isTrue);
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

  // Signing in changes the session first, so a screen that keeps `meProfileProvider` alive (the
  // Home chip, the profile step) refreshes it while the push is still on its way: the guest's
  // choices must survive that refresh.
  group('a guest who links an account while a screen shows the profile', () {
    const guest = Session(provider: SignInProvider.guest, userId: 'g1');
    late Map<String, dynamic> serverProfile;
    setUp(() => serverProfile = (jsonDecode(fixture('me_profile.json')) as Map).cast<String, dynamic>()..['displayName'] = 'Ahmed Hamdy');

    Future<http.Response> server(http.Request req) async {
      if (req.url.path == '/v1/auth/link') {
        return json({
          'accessToken': 'a2',
          'refreshToken': 'r2',
          'user': {'id': 'g1', 'displayName': 'Ahmed Hamdy'},
        });
      }
      if (req.method == 'GET' && req.url.path == '/v1/me/profile') return json(serverProfile);
      if (req.method == 'PATCH' && req.url.path == '/v1/me/profile') {
        serverProfile = {...serverProfile, ...(jsonDecode(req.body) as Map).cast<String, dynamic>()};
        return json(serverProfile);
      }
      if (req.method == 'PUT' && req.url.path == ProfileRepository.photoPath) {
        serverProfile['avatar'] = {'kind': 'photo', 'id': 'p9', 'url': ProfileRepository.ownPhotoLarge, 'smallUrl': '/v1/me/avatar/photo/64'};
        return json(serverProfile['avatar']);
      }
      if (req.method == 'GET' && req.url.path == ProfileRepository.ownPhotoLarge) {
        return http.Response.bytes([9, 9, 9], 200, headers: {'content-type': 'image/webp'});
      }
      return http.Response('', 204);
    }

    test('the PATCH carries the name and preset they chose', () async {
      final c = container(guest, server, social: FakeSocialAuth(credential: const SocialCredential(idToken: 'id')));
      final sub = c.listen(meProfileProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(meProfileProvider.future);
      await c.read(meProfileProvider.notifier).setName('سارة');
      await c.read(meProfileProvider.notifier).setAvatar(const PresetAvatar('f04'));
      expect(calls.where((x) => x.contains('/v1/me/profile')), isEmpty);

      final outcome = await c.read(sessionProvider.notifier).link(SignInProvider.google);
      await pumpEventQueue(times: 50);

      expect(outcome, SignInOutcome.signedIn);
      final patch = calls.indexOf('PATCH /v1/me/profile');
      expect(patch, isNot(-1));
      expect(bodies[patch], {'displayName': 'سارة', 'avatar': {'kind': 'preset', 'id': 'f04'}});
      // A background refresh raced the push: the cache and the screen still show their choices.
      expect(calls.where((x) => x == 'GET /v1/me/profile').length, greaterThanOrEqualTo(2));
      expect(kv.data[ProfileRepository.dirtyKey], isNull);
      final cached = (jsonDecode(kv.data[ProfileRepository.meKey]!) as Map).cast<String, dynamic>();
      expect(cached['displayName'], 'سارة');
      expect(cached['avatar'], {'kind': 'preset', 'id': 'f04'});
      expect(c.read(meProfileProvider).valueOrNull?.displayName, 'سارة');
    });

    test('their photo is uploaded, not deleted by the refresh', () async {
      final c = container(guest, server, social: FakeSocialAuth(credential: const SocialCredential(idToken: 'id')));
      final sub = c.listen(meProfileProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(meProfileProvider.future);
      await c.read(profileRepositoryProvider).uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([1, 2, 3])));
      expect(calls, isEmpty);

      await c.read(sessionProvider.notifier).link(SignInProvider.google);
      await pumpEventQueue(times: 50);

      final put = calls.indexOf('PUT ${ProfileRepository.photoPath}');
      expect(put, isNot(-1));
      expect(bodies[put], [1, 2, 3]);
      final avatar = c.read(meProfileProvider).valueOrNull?.avatar;
      expect(avatar, isA<PhotoAvatar>().having((a) => a.id, 'id', 'p9'));
    });
  });

  test('a refresh still out when the account signs out never brings its profile back', () async {
    final pending = Completer<http.Response>();
    final c = container(google, (req) async {
      if (req.method == 'GET' && req.url.path == '/v1/me/profile') return pending.future;
      return http.Response('', 204);
    });
    await seed(c);
    final sub = c.listen(meProfileProvider, (_, __) {});
    addTearDown(sub.close);
    await c.read(meProfileProvider.future);
    await pumpEventQueue();
    expect(calls, contains('GET /v1/me/profile')); // the background refresh is out

    await c.read(sessionProvider.notifier).signOut();
    pending.complete(json(jsonDecode(fixture('me_profile.json'))));
    await pumpEventQueue(times: 50);

    expect(kv.data[ProfileRepository.meKey], isNull);
    final shown = c.read(meProfileProvider).valueOrNull;
    expect(shown?.displayName, isNot('أحمد'));
    expect(shown?.level.level, 1);
  });
}
