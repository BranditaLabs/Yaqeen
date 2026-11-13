import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/platform/photo_picker.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/community/domain/community_models.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response error(int status, String code) => json(
      {
        'error': {'code': code, 'message': code},
      },
      status,
    );

Map<String, dynamic> fixture(String name) =>
    (jsonDecode(File('test/fixtures/community/$name').readAsStringSync()) as Map).cast<String, dynamic>();

class Rig {
  Rig({required this.account, required Future<http.Response> Function(http.Request req) handler}) {
    api = ApiClient(
      baseUrl: 'https://api.test',
      tokens: TokenStore(secure),
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final isJson = req.headers['Content-Type']?.startsWith('application/json') ?? false;
        bodies.add(isJson && req.bodyBytes.isNotEmpty ? jsonDecode(req.body) : null);
        return handler(req);
      }),
    );
    consents = ConsentRepository(api: api, store: kv);
    repo = ProfileRepository(
      api: api,
      store: kv,
      outbox: outbox,
      docsDir: () async => dir,
      consents: consents,
      isAccount: () => account,
    );
  }

  bool account;
  final kv = MemoryKvStore();
  final secure = MemoryKvStore();
  late final outbox = Outbox(kv);
  late final ApiClient api;
  late final ConsentRepository consents;
  late final ProfileRepository repo;
  final calls = <String>[];
  final bodies = <Object?>[];
  final dir = Directory.systemTemp.createTempSync('yq_profile_test');

  Future<void> signIn() => secure.write('auth.access', 'token');
}

Future<http.Response> offline(http.Request _) async => throw http.ClientException('offline');

void main() {
  group('name and avatar: local first', () {
    test('signed in: saved at once, one queued PATCH that merges name and avatar, no network', () async {
      final r = Rig(account: true, handler: offline);
      await r.signIn();
      await r.repo.saveName('  سارة ');
      await r.repo.saveAvatar(const PresetAvatar('f02'));
      expect(r.calls, isEmpty);
      final cached = await r.repo.cached();
      expect(cached!.displayName, 'سارة');
      expect(cached.avatar, const PresetAvatar('f02'));
      final items = await r.outbox.items();
      expect(items, hasLength(1));
      expect(items.single.method, 'PATCH');
      expect(items.single.path, '/v1/me/profile');
      expect(items.single.body, {
        'displayName': 'سارة',
        'avatar': {'kind': 'preset', 'id': 'f02'},
      });
      // A newer name replaces the queued one.
      await r.repo.saveName('Sara');
      expect((await r.outbox.items()).single.body!['displayName'], 'Sara');
    });

    test('guest: nothing reaches the network or the Outbox; dirty flags remember the change', () async {
      final r = Rig(account: false, handler: offline);
      await r.repo.saveName('ضيف كريم');
      await r.repo.saveAvatar(const PresetAvatar('m01'));
      expect(r.calls, isEmpty);
      expect(await r.outbox.items(), isEmpty);
      expect(jsonDecode(r.kv.data[ProfileRepository.dirtyKey]!), {'name': true, 'avatar': true, 'photo': false});
      final photo = await r.repo.uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3])));
      expect(photo.isOk, isTrue);
      expect(r.calls, isEmpty);
      final local = (await r.repo.cached())!.avatar as PhotoAvatar;
      expect(local.isLocalOnly, isTrue);
      expect(File(local.localPath!).existsSync(), isTrue);
    });

    test('refresh keeps a queued name on top of the server value until it is delivered', () async {
      final r = Rig(account: true, handler: (req) async => json(fixture('me_profile.json')));
      await r.signIn();
      await r.outbox.add(OutboxItem(id: '1', method: 'PATCH', path: '/v1/me/profile', body: {'displayName': 'Local'}));
      final p = await r.repo.refresh();
      expect(p.displayName, 'Local');
      expect(p.handle, 'ahmed-4821');
    });
  });

  group('photo', () {
    test('signed in: uploads directly, then stores the 256-px copy from the authed path', () async {
      final r = Rig(
        account: true,
        handler: (req) async {
          if (req.method == 'PUT' && req.url.path == '/v1/me/avatar/photo') {
            expect(req.headers['Content-Type'], 'image/jpeg');
            return json({'kind': 'photo', 'id': 'p1', 'url': '/v1/me/avatar/photo/256', 'smallUrl': '/v1/me/avatar/photo/96'});
          }
          if (req.method == 'GET' && req.url.path == '/v1/me/avatar/photo/256') return http.Response.bytes([1, 2, 3, 4], 200);
          return error(404, 'not_found');
        },
      );
      await r.signIn();
      final res = await r.repo.uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 9])));
      expect(res.isOk, isTrue);
      expect(r.calls, ['PUT /v1/me/avatar/photo', 'GET /v1/me/avatar/photo/256']);
      final a = (await r.repo.cached())!.avatar as PhotoAvatar;
      expect(a.id, 'p1');
      expect(File(a.localPath!).readAsBytesSync(), [1, 2, 3, 4]);
      expect(r.kv.data.containsKey(ProfileRepository.pendingUploadKey), isFalse);
      expect(await r.outbox.items(), isEmpty); // never the Outbox
    });

    test('offline upload keeps the local photo and a pending retry; too large restores the previous picture', () async {
      final r = Rig(account: true, handler: offline);
      await r.signIn();
      await r.repo.saveAvatar(const PresetAvatar('m02'));
      final res = await r.repo.uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF])));
      expect(res.errorOrNull, CommunityFailure.offline);
      expect((await r.repo.cached())!.avatar, isA<PhotoAvatar>());
      expect(r.kv.data.containsKey(ProfileRepository.pendingUploadKey), isTrue);
      // The queued preset change would undo the photo on replay: it is dropped.
      expect((await r.outbox.items()).where((i) => i.body?.containsKey('avatar') ?? false), isEmpty);

      final big = Rig(account: true, handler: (req) async => error(413, 'photo_too_large'));
      await big.signIn();
      await big.repo.saveAvatar(const PresetAvatar('f01'));
      final res2 = await big.repo.uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF])));
      expect(res2.errorOrNull, CommunityFailure.photoTooLarge);
      expect((await big.repo.cached())!.avatar, const PresetAvatar('f01'));
      expect(big.kv.data.containsKey(ProfileRepository.pendingUploadKey), isFalse);
    });
  });

  group('community', () {
    test('join is a direct PUT (not the Outbox) with the attestation, and adopts the consent', () async {
      final r = Rig(
        account: true,
        handler: (req) async => json({
          'leagues': true,
          'leaderboard': false,
          'leaderboardCountry': false,
          'banned': false,
          'attestedAdult': true,
          'country': 'EG',
        }),
      );
      await r.signIn();
      final res = await r.repo.joinCommunity(
        const CommunityUpdate(leagues: true, displayName: 'سارة', attestAdult: true, source: CommunitySource.onboarding),
      );
      expect(res.valueOrNull!.leagues, isTrue);
      expect(r.calls, ['PUT /v1/me/community']);
      expect(r.bodies.single, {'leagues': true, 'displayName': 'سارة', 'attestAdult': true, 'source': 'onboarding'});
      expect(await r.outbox.items(), isEmpty);
      expect(r.consents.granted(ConsentKind.community), isTrue);
      final p = (await r.repo.cached())!;
      expect(p.community.leagues, isTrue);
      expect(p.displayName, 'سارة');
    });

    test('offline join fails with offline and queues nothing', () async {
      final r = Rig(account: true, handler: offline);
      await r.signIn();
      final res = await r.repo.joinCommunity(const CommunityUpdate(leagues: true, attestAdult: true));
      expect(res.errorOrNull, CommunityFailure.offline);
      expect(await r.outbox.items(), isEmpty);
      expect(r.consents.granted(ConsentKind.community), isFalse);
    });

    test('every server code maps to its typed failure', () async {
      for (final (status, code, failure) in [
        (400, 'attestation_required', CommunityFailure.attestationRequired),
        (403, 'community_banned', CommunityFailure.communityBanned),
        (400, 'name_required', CommunityFailure.nameRequired),
        (400, 'invalid_name', CommunityFailure.invalidName),
        (409, 'name_locked', CommunityFailure.nameLocked),
        (403, 'feature_off', CommunityFailure.featureOff),
        (403, 'account_required', CommunityFailure.accountRequired),
        (500, 'internal', CommunityFailure.unknown),
      ]) {
        final r = Rig(account: true, handler: (req) async => error(status, code));
        await r.signIn();
        expect((await r.repo.joinCommunity(const CommunityUpdate(leagues: true))).errorOrNull, failure, reason: code);
      }
    });

    test('guests cannot join, without any request', () async {
      final r = Rig(account: false, handler: offline);
      expect((await r.repo.joinCommunity(const CommunityUpdate(leagues: true))).errorOrNull, CommunityFailure.accountRequired);
      expect(r.calls, isEmpty);
    });

    test('leave is queued and applied here at once; two leaves merge into one PUT', () async {
      final r = Rig(account: true, handler: (req) async => json(fixture('me_profile.json')));
      await r.signIn();
      await r.repo.refresh();
      r.calls.clear();
      final p = await r.repo.leaveCommunity(leagues: true);
      expect(p.community.leagues, isFalse);
      expect(p.league, isNull);
      await r.repo.leaveCommunity(leaderboard: true);
      expect(r.calls, isEmpty);
      final items = await r.outbox.items();
      expect(items, hasLength(1));
      expect(items.single.method, 'PUT');
      expect(items.single.body, {'leagues': false, 'leaderboard': false, 'leaderboardCountry': false, 'source': 'settings'});
      expect((await r.repo.cached())!.community.anyOn, isFalse);
    });

    test('attest is a direct POST', () async {
      final r = Rig(
        account: true,
        handler: (req) async => json({
          'leagues': false,
          'leaderboard': false,
          'leaderboardCountry': false,
          'banned': false,
          'attestedAdult': true,
          'country': null,
        }),
      );
      await r.signIn();
      expect((await r.repo.attest()).valueOrNull!.attestedAdult, isTrue);
      expect(r.calls, ['POST /v1/me/attestation']);
      expect(r.bodies.single, {'attestAdult': true});
    });
  });

  group('pushAfterSignIn', () {
    test('fetches first, pushes only the dirty name, and the server wins for the avatar', () async {
      final server = fixture('me_profile.json')
        ..['displayName'] = 'Server Name'
        ..['avatar'] = {'kind': 'preset', 'id': 'm07'};
      final r = Rig(
        account: false,
        handler: (req) async {
          if (req.method == 'GET') return json(server);
          if (req.method == 'PATCH') return json({...server, 'displayName': 'محلي'});
          return error(404, 'not_found');
        },
      );
      await r.repo.saveName('محلي');
      // The avatar was never changed on this phone.
      r.account = true;
      await r.signIn();
      final p = await r.repo.pushAfterSignIn();
      expect(r.calls, ['GET /v1/me/profile', 'PATCH /v1/me/profile']);
      expect(r.bodies.last, {'displayName': 'محلي'});
      expect(p!.displayName, 'محلي');
      expect(p.avatar, const PresetAvatar('m07'));
      expect(r.kv.data.containsKey(ProfileRepository.dirtyKey), isFalse);
    });

    test('nothing dirty → nothing pushed', () async {
      final r = Rig(account: true, handler: (req) async => json(fixture('me_profile.json')));
      await r.signIn();
      await r.repo.pushAfterSignIn();
      expect(r.calls, ['GET /v1/me/profile']);
    });
  });

  test('wipe removes profile and community keys and the photo folder', () async {
    final r = Rig(account: false, handler: offline);
    await r.repo.saveName('x');
    await r.repo.uploadPhoto(PickedPhoto(bytes: Uint8List.fromList([1, 2, 3])));
    await r.kv.write('community.league.v1', '{}');
    await r.kv.write('community.seenWeek', '2026-11-07');
    await r.kv.write('settings.v1', '{}');
    await r.repo.wipe();
    expect(r.kv.data.keys, ['settings.v1']);
    expect(Directory('${r.dir.path}${Platform.pathSeparator}profile').existsSync(), isFalse);
  });
}
