import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

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

/// One ad platform SDK (Firebase/Google Ads, Meta, TikTok) — `lib/core/analytics/sinks/`.
///
/// Sinks only ever see what [Analytics] hands them: an [AdEvent] and allowlisted params plus the
/// `att` flag (1/0). They are called only while `ads_measurement` is granted, must not touch their SDK
/// before [setEnabled] or [log], and must turn their SDK off on `setEnabled(false)`.
abstract interface class AdSink {
  String get name;
  Future<void> log(AdEvent event, Map<String, Object> params);

  /// [attAuthorized]: iOS App Tracking Transparency answered "allow" (always true on Android, which
  /// has no ATT). Without it the SDK must not collect the advertising identifier.
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false});
}

class Analytics {
  Analytics({
    required List<AdSink> sinks,
    required bool Function() adsConsent,
    Future<bool> Function()? attAuthorized,
    bool Function()? consentDecided,
    KvStore? store,
    DateTime Function()? now,
    this.sinkTimeout = const Duration(seconds: 5),
  })  : _sinks = sinks,
        _adsConsent = adsConsent,
        _attAuthorized = attAuthorized ?? (() async => false),
        _consentDecided = consentDecided ?? (() => true),
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

  /// iOS App Tracking Transparency status. Without it, sinks must run in limited mode (no IDFA).
  final Future<bool> Function() _attAuthorized;

  /// Whether the user has answered the consent screen. Before that no SDK is touched at all.
  final bool Function() _consentDecided;

  /// An SDK call that hangs or throws never blocks or breaks the screen that logged the event.
  final Duration sinkTimeout;

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
    if (_sinks.isEmpty) return;
    final safe = {
      for (final e in params.entries)
        if (allowedParams.contains(e.key)) e.key: e.value,
      'att': await _att() ? 1 : 0,
    };
    await _each('log ${event.wireName}', (s) => s.log(event, Map.unmodifiable(safe)));
  }

  Future<bool> _att() async {
    try {
      return await _attAuthorized().timeout(sinkTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<void> _each(String what, Future<void> Function(AdSink) run) => Future.wait(
        _sinks.map((s) async {
          try {
            await run(s).timeout(sinkTimeout);
          } catch (e) {
            debugPrint('YQ-ADS ${s.name} $what failed: $e');
          }
        }),
      );

  Future<void> _setSinks(bool granted) async {
    if (_sinks.isEmpty) return;
    final att = granted && await _att();
    await _each('setEnabled($granted)', (s) => s.setEnabled(granted, attAuthorized: att));
  }

  /// After the first frame on every launch: brings the SDKs in line with the stored consent (on with
  /// it, off without it). Does nothing before the consent screen has been answered.
  Future<void> start() async {
    if (!_consentDecided()) return;
    await _setSinks(_adsConsent());
  }

  /// Call when the user changes the `ads_measurement` consent (after the ATT prompt, so the SDKs
  /// start with its answer). Granting it sends the queued install events that are still fresh;
  /// declining drops them and turns every SDK off.
  Future<void> onConsentChanged(bool granted) async {
    await _setSinks(granted);
    final pending = await _pending();
    await _store?.delete(_queueKey);
    if (!granted) return;
    for (final (event, at) in pending) {
      if (_now().difference(at) <= queueTtl) await _send(event, const {});
    }
  }
}

/// In-memory sink for debug builds and tests: records what an ad SDK would have received.
class DebugAdSink implements AdSink {
  final List<String> logged = [];
  final List<Map<String, Object>> params = [];
  bool? enabled;
  bool? attAuthorized;

  @override
  String get name => 'debug';

  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async {
    logged.add(event.wireName);
    this.params.add(params);
  }

  @override
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false}) async {
    this.enabled = enabled;
    this.attAuthorized = attAuthorized;
  }
}
