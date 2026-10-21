import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/analytics/analytics.dart';
import 'package:yaqeen/core/notifications/push_service.dart';

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

  test('event names match packages/contracts AD_EVENTS', () {
    expect(AdEvent.values.map((e) => e.wireName).toList(), [
      'first_open', 'sign_up', 'onboarding_complete', 'challenge_join',
      'streak_7', 'streak_30', 'reward_redeem', 'store_click', 'purchase',
    ]);
  });

  test('deep links route to known screens', () {
    expect(routeForDeepLink(Uri.parse('yaqeen://redeem')), '/challenge/redeem');
    expect(routeForDeepLink(Uri.parse('yaqeen://unknown')), '/home');
  });
}
