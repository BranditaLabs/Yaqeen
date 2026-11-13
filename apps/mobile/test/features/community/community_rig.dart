import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';

/// Shared test rig for the community screens: a MockClient API routed by `METHOD /path`, an
/// in-memory KV store, a signed-in session and the three competition flags on.

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response errorResponse(int status, String code) => jsonResponse(
      {
        'error': {'code': code, 'message': code},
      },
      status,
    );

Object? fixture(String name) => jsonDecode(File('test/fixtures/community/$name').readAsStringSync());

Map<String, dynamic> fixtureMap(String name) => (fixture(name) as Map).cast<String, dynamic>();

/// The shared league fixture with every avatar a preset (no network images in widget tests).
Map<String, dynamic> leagueJoined() {
  final j = fixtureMap('league_current_joined.json');
  j['rows'] = [
    for (final r in j['rows'] as List)
      {
        ...(r as Map).cast<String, dynamic>(),
        if ((r['avatar'] as Map)['kind'] == 'photo') 'avatar': {'kind': 'preset', 'id': 'f05'},
      },
  ];
  return j;
}

/// Thrown by a route to simulate no connectivity.
http.Response offline() => throw http.ClientException('offline');

typedef Route = http.Response Function(http.Request req);

class CommunityRig {
  CommunityRig({Map<String, Route>? routes, this.signedIn = true, Map<String, bool>? flags}) : routes = {...?routes} {
    features = {
      ...RemoteConfig.defaultFeatures,
      Flags.leagues: true,
      Flags.tournaments: true,
      Flags.leaderboard: true,
      ...?flags,
    };
    api = ApiClient(
      baseUrl: 'https://api.test',
      tokens: TokenStore(MemoryKvStore()),
      client: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        calls.add(req.url.query.isEmpty ? key : '$key?${req.url.query}');
        final isJson = req.headers['Content-Type']?.startsWith('application/json') ?? false;
        bodies[key] = isJson && req.bodyBytes.isNotEmpty ? jsonDecode(req.body) : null;
        final gate = gates[key];
        if (gate != null) await gate.future;
        if (offlineAll) throw http.ClientException('offline');
        final route = this.routes[key];
        if (route == null) return errorResponse(404, 'not_found');
        return route(req);
      }),
    );
  }

  final Map<String, Route> routes;
  final bool signedIn;

  /// Every request fails as if there were no connection.
  bool offlineAll = false;

  /// A slow connection: a request to `METHOD /path` waits until its completer completes.
  final gates = <String, Completer<void>>{};
  late final Map<String, bool> features;
  final kv = MemoryKvStore();
  late final ApiClient api;
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final device = FakeDeviceServices();
  final dir = Directory.systemTemp.createTempSync('yq_community_test');
  DateTime now = DateTime.utc(2026, 11, 17, 10); // Tuesday, Cairo noon

  late final outbox = Outbox(kv);

  Future<List<OutboxItem>> queued() => outbox.items();

  List<Override> get overrides => [
        apiClientProvider.overrideWithValue(api),
        filesDirProvider.overrideWithValue(() async => dir),
        deviceServicesProvider.overrideWithValue(device),
        clockProvider.overrideWithValue(() => now),
        initialConfigProvider.overrideWithValue(RemoteConfig(features: features)),
        initialSessionProvider.overrideWithValue(
          signedIn
              ? const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد محمود')
              : const Session(provider: SignInProvider.guest, pendingServer: true),
        ),
      ];
}
