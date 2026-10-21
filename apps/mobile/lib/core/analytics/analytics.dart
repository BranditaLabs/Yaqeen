/// Marketing analytics with a hard privacy gate.
///
/// Mirrors `packages/contracts/src/events.ts` (AD_EVENTS). Worship activity —
/// reading, prayer, azkar, hifz, listening — is NEVER an ad event and there is
/// intentionally no API here to send one. Adding an event needs a privacy review.
enum AdEvent {
  firstOpen('first_open'),
  signUp('sign_up'),
  onboardingComplete('onboarding_complete'),
  challengeJoin('challenge_join'),
  streak7('streak_7'),
  streak30('streak_30'),
  rewardRedeem('reward_redeem'),
  storeClick('store_click'),
  purchase('purchase');

  const AdEvent(this.wireName);
  final String wireName;
}

/// One ad platform SDK (Firebase/Google Ads, Meta, TikTok). Implemented in
/// `lib/core/analytics/sinks/` once the SDK packages are added.
abstract interface class AdSink {
  String get name;
  Future<void> log(AdEvent event, Map<String, Object> params);
  Future<void> setEnabled(bool enabled);
}

class Analytics {
  Analytics({required List<AdSink> sinks, required bool Function() adsConsent, bool Function()? attAuthorized})
      : _sinks = sinks,
        _adsConsent = adsConsent,
        _attAuthorized = attAuthorized ?? (() => true);

  final List<AdSink> _sinks;
  final bool Function() _adsConsent;

  /// iOS App Tracking Transparency status. Without it, sinks must run in limited mode.
  final bool Function() _attAuthorized;

  bool get enabled => _adsConsent();

  /// Params are restricted to a small allowlist so nothing personal leaks by accident.
  static const allowedParams = {'value', 'currency', 'reward_id', 'day'};

  Future<void> log(AdEvent event, [Map<String, Object> params = const {}]) async {
    if (!_adsConsent()) return;
    final safe = {
      for (final e in params.entries)
        if (allowedParams.contains(e.key)) e.key: e.value,
      'att': _attAuthorized() ? 1 : 0,
    };
    await Future.wait(_sinks.map((s) => s.log(event, safe)));
  }

  /// Call when the user changes the `ads_measurement` consent.
  Future<void> onConsentChanged(bool granted) => Future.wait(_sinks.map((s) => s.setEnabled(granted)));
}

/// Default sink until SDKs are wired — logs in debug only.
class DebugAdSink implements AdSink {
  final List<String> logged = [];

  @override
  String get name => 'debug';

  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async => logged.add(event.wireName);

  @override
  Future<void> setEnabled(bool enabled) async {}
}
