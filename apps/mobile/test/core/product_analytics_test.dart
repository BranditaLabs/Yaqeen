import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/analytics/product_analytics.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late bool consent;
  late bool online;

  ProductAnalytics make(KvStore store) {
    sent = [];
    final client = MockClient((req) async {
      if (!online) throw const SocketException('offline');
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"accepted":1}', 202, headers: {'content-type': 'application/json'});
    });
    final tokens = TokenStore(MemoryKvStore());
    return ProductAnalytics(
      api: ApiClient(baseUrl: 'https://api.test', tokens: tokens, client: client),
      store: store,
      consent: () => consent,
      platform: 'android',
      appVersion: () async => '1.2.3',
      locale: () => 'ar',
      now: () => DateTime.utc(2026, 10, 20, 8),
      random: Random(7),
    );
  }

  setUp(() {
    consent = true;
    online = true;
  });

  test('nothing is recorded without consent', () async {
    consent = false;
    final store = MemoryKvStore();
    final a = make(store);
    await a.track(ProductEvent.appOpen);
    await a.flush();
    expect(sent, isEmpty);
    expect(await store.read('analytics.product.queue.v1'), isNull);
  });

  test('queues, survives offline, then sends one batch with the install id (never the account)', () async {
    final store = MemoryKvStore();
    final a = make(store);
    online = false;
    await a.track(ProductEvent.appOpen);
    await a.track(ProductEvent.tabView, {'tab': 'home'});
    await a.flush();
    expect(sent, isEmpty);
    online = true;
    await a.flush();
    expect(sent, hasLength(1));
    final body = sent.single;
    expect(body['anonId'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(body['appVersion'], '1.2.3');
    expect((body['events'] as List).map((e) => (e as Map)['name']), ['app_open', 'tab_view']);
    expect(body.keys, isNot(contains('userId')));
    await a.flush();
    expect(sent, hasLength(1)); // queue emptied
  });

  test('values outside the closed list are dropped', () async {
    make(MemoryKvStore());
    expect(ProductEvent.tabView.allows({'tab': 'quran'}), isFalse);
    expect(ProductEvent.onboardingStep.allows({'step': 'consent', 'surah': '18'}), isFalse);
  });

  test('withdrawing consent deletes the queue and the install id', () async {
    final store = MemoryKvStore();
    final a = make(store);
    final first = await a.anonId();
    online = false;
    await a.track(ProductEvent.appOpen);
    await a.onConsentChanged(false);
    expect(await store.read('analytics.product.queue.v1'), isNull);
    expect(await a.anonId(), isNot(first));
  });

  test('routes: onboarding steps, three tab roots and rewards only — worship screens never', () async {
    final store = MemoryKvStore();
    final a = make(store);
    online = false;
    final r = RouteTracker(a);
    for (final p in [
      '/onboarding/consent',
      '/onboarding/consent',
      '/home',
      '/home/azkar',
      '/quran',
      '/quran/read/18',
      '/prayer',
      '/challenge',
      '/challenge/redeem',
      '/profile',
      '/home/duas/sleep',
    ]) {
      r.onLocation(p);
    }
    await Future<void>.delayed(Duration.zero);
    online = true;
    await a.flush();
    final events = [for (final e in sent.single['events'] as List) '${(e as Map)['name']} ${jsonEncode(e['props'])}'];
    expect(events, [
      'onboarding_step {"step":"consent"}',
      'tab_view {"tab":"home"}',
      'tab_view {"tab":"challenge"}',
      'redeem_view {}',
      'tab_view {"tab":"profile"}',
    ]);
  });

  test('mirrors PRODUCT_EVENTS in packages/contracts', () {
    final src = File('../../packages/contracts/src/events.ts').readAsStringSync();
    final block = src.substring(src.indexOf('export const PRODUCT_EVENTS = {'), src.indexOf('} as const satisfies'));
    final contract = <String, Map<String, Set<String>>>{};
    for (final m in RegExp(r'^  (\w+): \{(.*)\},$', multiLine: true).allMatches(block)) {
      final props = <String, Set<String>>{};
      for (final p in RegExp(r"(\w+): \[([^\]]*)\]").allMatches(m.group(2)!)) {
        props[p.group(1)!] = {for (final v in RegExp(r"'([^']+)'").allMatches(p.group(2)!)) v.group(1)!};
      }
      contract[m.group(1)!] = props;
    }
    expect({for (final e in ProductEvent.values) e.wire: e.props}, contract);
  });

  test('uuid v4 shape', () {
    expect(uuidV4(Random(1)), matches(RegExp(r'^[0-9a-f-]{36}$')));
  });
}
