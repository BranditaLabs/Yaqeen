import 'dart:convert';

import '../storage/kv_store.dart';

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
  Analytics({
    required List<AdSink> sinks,
    required bool Function() adsConsent,
    bool Function()? attAuthorized,
    KvStore? store,
    DateTime Function()? now,
  })  : _sinks = sinks,
        _adsConsent = adsConsent,
        _attAuthorized = attAuthorized ?? (() => true),
        _store = store,
        _now = now ?? DateTime.now;

  final List<AdSink> _sinks;
  final bool Function() _adsConsent;
  final KvStore? _store;
  final DateTime Function() _now;

  static const _queueKey = 'analytics.pending.v1';

  /// Install events that happen before the consent screen (spec §5.3, §6.3).
  static const queueable = {AdEvent.firstOpen, AdEvent.signUp};
  static const queueTtl = Duration(hours: 24);

  /// iOS App Tracking Transparency status. Without it, sinks must run in limited mode.
  final bool Function() _attAuthorized;

  bool get enabled => _adsConsent();

  /// Params are restricted to a small allowlist so nothing personal leaks by accident.
  static const allowedParams = {'value', 'currency', 'reward_id', 'day'};

  Future<void> log(AdEvent event, [Map<String, Object> params = const {}]) async {
    if (!_adsConsent()) return;
    await _send(event, params);
  }

  /// Like [log], but if consent hasn't been given yet the event waits (max 24 h) for the
  /// decision on the consent screen instead of being dropped. Rule: queue, don't send.
  Future<void> logOrQueue(AdEvent event, [Map<String, Object> params = const {}]) async {
    if (_adsConsent()) return _send(event, params);
    final store = _store;
    if (store == null || !queueable.contains(event)) return;
    final pending = await _pending();
    if (pending.any((p) => p.$1 == event)) return;
    await store.write(
      _queueKey,
      jsonEncode([
        for (final (e, at) in [...pending, (event, _now())]) {'e': e.wireName, 'at': at.toIso8601String()},
      ]),
    );
  }

  Future<List<(AdEvent, DateTime)>> _pending() async {
    final raw = await _store?.read(_queueKey);
    if (raw == null) return [];
    return [
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        if (AdEvent.values.where((e) => e.wireName == m['e']).firstOrNull case final e?) (e, DateTime.parse(m['at'] as String)),
    ];
  }

  Future<void> _send(AdEvent event, Map<String, Object> params) async {
    final safe = {
      for (final e in params.entries)
        if (allowedParams.contains(e.key)) e.key: e.value,
      'att': _attAuthorized() ? 1 : 0,
    };
    await Future.wait(_sinks.map((s) => s.log(event, safe)));
  }

  /// Call when the user changes the `ads_measurement` consent. Granting it sends the queued
  /// install events that are still fresh; declining drops them.
  Future<void> onConsentChanged(bool granted) async {
    await Future.wait(_sinks.map((s) => s.setEnabled(granted)));
    final pending = await _pending();
    await _store?.delete(_queueKey);
    if (!granted) return;
    for (final (event, at) in pending) {
      if (_now().difference(at) <= queueTtl) await _send(event, const {});
    }
  }
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
