import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/notifications/push_registration.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

class _Push implements PushService {
  String? current = 'fcm-token-aaaaaaaaaaaaaaaaaaaa';
  final refresh = StreamController<String>.broadcast();
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String?> token() async => current;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushOpened> get onOpened => const Stream.empty();
}

void main() {
  late List<http.Request> calls;
  late _Push push;
  late PushRegistrar reg;

  setUp(() {
    calls = [];
    push = _Push();
    final api = ApiClient(
      baseUrl: 'https://api.test',
      tokens: TokenStore(MemoryKvStore()),
      client: MockClient((req) async {
        calls.add(req);
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    reg = PushRegistrar(api: api, push: push, store: MemoryKvStore(), platform: 'android', appVersion: () async => '1.2.0');
  });

  test('registers the token once per account, token and version; follows refreshes', () async {
    await reg.sync(null);
    expect(calls, isEmpty, reason: 'signed out: nothing to register');

    await reg.sync('u1');
    expect(calls.single.url.path, '/v1/me/devices');
    expect(jsonDecode(calls.single.body), {'platform': 'android', 'fcmToken': 'fcm-token-aaaaaaaaaaaaaaaaaaaa', 'appVersion': '1.2.0'});

    await reg.sync('u1');
    expect(calls, hasLength(1), reason: 'unchanged: not re-sent');

    push.refresh.add('fcm-token-bbbbbbbbbbbbbbbbbbbb');
    await pumpEventQueue();
    expect(calls, hasLength(2));
    expect(jsonDecode(calls.last.body)['fcmToken'], 'fcm-token-bbbbbbbbbbbbbbbbbbbb');

    push.current = 'fcm-token-bbbbbbbbbbbbbbbbbbbb';
    await reg.sync('u2');
    expect(calls, hasLength(3), reason: 'another account on this install');
  });

  test('a tapped campaign push counts its open; plain links do not call the API', () async {
    await reg.sync('u1');
    calls.clear();
    await reg.opened(PushOpened(Uri.parse('yaqeen://redeem')));
    expect(calls, isEmpty);
    await reg.opened(PushOpened(Uri.parse('yaqeen://redeem'), campaignId: 'c-1'));
    expect(calls.single.url.path, '/v1/me/campaigns/c-1/opened');
  });
}
