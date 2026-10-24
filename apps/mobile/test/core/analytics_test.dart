import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/analytics/analytics.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

void main() {
  test('nothing is sent without ads_measurement consent', () async {
    final sink = DebugAdSink();
    var consent = false;
    final a = Analytics(sinks: [sink], adsConsent: () => consent);
    await a.log(AdEvent.signUp);
    expect(sink.logged, isEmpty);
    consent = true;
    await a.log(AdEvent.signUp);
    expect(sink.logged, ['sign_up']);
  });

  test('install events wait for the consent decision, then send only if granted', () async {
    final sink = DebugAdSink();
    var consent = false;
    final now = DateTime(2026, 10, 20, 9);
    final a = Analytics(sinks: [sink], adsConsent: () => consent, store: MemoryKvStore(), now: () => now);
    await a.logOrQueue(AdEvent.firstOpen);
    await a.logOrQueue(AdEvent.signUp);
    await a.logOrQueue(AdEvent.signUp); // de-duplicated
    await a.logOrQueue(AdEvent.rewardRedeem); // never queued
    expect(sink.logged, isEmpty);

    consent = true;
    await a.onConsentChanged(true);
    expect(sink.logged, ['first_open', 'sign_up']);
    await a.onConsentChanged(true);
    expect(sink.logged, ['first_open', 'sign_up']); // queue cleared
  });

  test('queued events expire after 24 h and are dropped on decline', () async {
    final sink = DebugAdSink();
    var now = DateTime(2026, 10, 20, 9);
    final store = MemoryKvStore();
    final a = Analytics(sinks: [sink], adsConsent: () => false, store: store, now: () => now);
    await a.logOrQueue(AdEvent.signUp);
    await a.onConsentChanged(false);
    expect(store.data, isEmpty);

    await a.logOrQueue(AdEvent.firstOpen);
    now = now.add(const Duration(hours: 25));
    await a.onConsentChanged(true);
    expect(sink.logged, isEmpty);
  });

  test('event names match packages/contracts AD_EVENTS', () {
    expect(AdEvent.values.map((e) => e.wireName).toList(), [
      'first_open',
      'sign_up',
      'onboarding_complete',
      'challenge_join',
      'streak_7',
      'streak_30',
      'reward_redeem',
      'store_click',
      'purchase',
    ]);
  });

  test('deep links route to known screens', () {
    expect(routeForDeepLink(Uri.parse('yaqeen://redeem')), '/challenge/redeem');
    expect(routeForDeepLink(Uri.parse('yaqeen://unknown')), '/home');
  });
}
