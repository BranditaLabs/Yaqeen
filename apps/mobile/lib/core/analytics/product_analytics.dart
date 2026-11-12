import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../network/api_client.dart';
import '../storage/kv_store.dart';

/// Product analytics («تحسين التطبيق») — mirrors `PRODUCT_EVENTS` in packages/contracts/src/events.ts.
///
/// Only with the `product_analytics` consent (off by default). Events go to our API only, keyed by a
/// random per-install id that is never the account and is replaced when consent is withdrawn.
/// Closed list with closed values: **no worship activity** — no surah, prayer, zikr, dua, task or
/// hifz step, and worship tabs aren't tracked. Adding an event or a value needs a privacy review.
enum ProductEvent {
  appOpen('app_open', {}),
  onboardingStep('onboarding_step', {
    'step': {'welcome', 'language', 'prayer', 'consent', 'goal', 'routine', 'download'},
  }),
  onboardingComplete('onboarding_complete', {}),
  signIn('sign_in', {
    'provider': {'google', 'apple', 'guest'},
  }),
  tabView('tab_view', {
    'tab': {'home', 'challenge', 'profile'},
  }),
  cardPublished('card_published', {}),
  cardShared('card_shared', {
    'channel': {'link', 'qr'},
  }),
  medalActivated('medal_activated', {
    'via': {'code', 'link'},
  }),
  redeemView('redeem_view', {}),
  rewardRedeem('reward_redeem', {}),
  storeClick('store_click', {
    'from': {'profile', 'redeem', 'card', 'medal'},
  }),
  notificationOpen('notification_open', {
    'kind': {'reminder', 'campaign', 'challenge'},
  }),
  settingsChange('settings_change', {
    'setting': {'language', 'reminders', 'privacy', 'routine'},
  }),
  updatePrompt('update_prompt', {
    'action': {'shown', 'update', 'later'},
  });

  const ProductEvent(this.wire, this.props);
  final String wire;
  final Map<String, Set<String>> props;

  bool allows(Map<String, String> p) => p.entries.every((e) => props[e.key]?.contains(e.value) ?? false);
}

class ProductAnalytics {
  ProductAnalytics({
    required this.api,
    required this.store,
    required this.consent,
    required this.platform,
    required this.appVersion,
    required this.locale,
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final ApiClient api;
  final KvStore store;
  final bool Function() consent;
  final String platform;
  /// Read lazily (a platform call) when a batch is sent, never on the start-up path.
  final Future<String> Function() appVersion;
  final String Function() locale;
  final DateTime Function() _now;
  final Random _random;

  static const _queueKey = 'analytics.product.queue.v1';
  static const _idKey = 'analytics.product.anon.v1';
  static const maxQueue = 200;
  static const batchSize = 50;
  static const flushAt = 20;

  List<Map<String, Object>>? _queue;
  Future<List<Map<String, Object>>>? _loading;
  final _once = <String>{};
  bool _flushing = false;
  Timer? _timer;

  /// Sends what's queued every [every] while the app runs (and on [flush] from lifecycle events).
  void start({Duration every = const Duration(minutes: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(flush()));
  }

  void stop() => _timer?.cancel();

  /// Records [event] when the user allowed it. Invalid props are dropped (and fail loudly in debug).
  Future<void> track(ProductEvent event, [Map<String, String> props = const {}]) async {
    if (!consent()) return;
    assert(event.allows(props), 'props $props not allowed for ${event.wire}');
    if (!event.allows(props)) return;
    final q = await _load();
    q.add({'name': event.wire, 'props': props, 'at': _now().toUtc().toIso8601String()});
    if (q.length > maxQueue) q.removeRange(0, q.length - maxQueue);
    await _save();
    if (q.length >= flushAt) unawaited(flush());
  }

  /// [track] at most once per app session for this event + props (screen views on rebuild).
  Future<void> trackOnce(ProductEvent event, [Map<String, String> props = const {}]) {
    final key = '${event.wire}:${jsonEncode(props)}';
    if (!_once.add(key)) return Future.value();
    return track(event, props);
  }

  /// Sends queued events in batches; keeps them on failure (offline) for the next try.
  Future<void> flush() async {
    if (_flushing || !consent()) return;
    _flushing = true;
    try {
      final q = await _load();
      while (q.isNotEmpty) {
        final batch = q.take(batchSize).toList();
        await api.post('/v1/me/events', {
          'anonId': await anonId(),
          'platform': platform,
          'appVersion': await appVersion(),
          'locale': locale(),
          'events': batch,
        });
        q.removeRange(0, batch.length);
        await _save();
      }
    } on Exception {
      // Offline or server busy: the queue stays and goes out on the next flush.
    } finally {
      _flushing = false;
    }
  }

  /// Consent changed: withdrawing it deletes the queue and the install id (a fresh one if granted again).
  Future<void> onConsentChanged(bool granted) async {
    if (granted) return;
    _queue = [];
    _loading = Future.value(_queue);
    _once.clear();
    await store.delete(_queueKey);
    await store.delete(_idKey);
  }

  Future<String> anonId() async {
    final existing = await store.read(_idKey);
    if (existing != null && existing.length == 36) return existing;
    final id = uuidV4(_random);
    await store.write(_idKey, id);
    return id;
  }

  /// One read shared by concurrent callers (several events at start-up must land in one queue).
  Future<List<Map<String, Object>>> _load() => _loading ??= _read();

  Future<List<Map<String, Object>>> _read() async {
    if (_queue != null) return _queue!;
    try {
      final raw = await store.read(_queueKey);
      _queue = raw == null ? [] : [for (final e in jsonDecode(raw) as List) (e as Map).cast<String, Object>()];
    } catch (_) {
      _queue = [];
    }
    return _queue!;
  }

  Future<void> _save() => store.write(_queueKey, jsonEncode(_queue));
}

/// RFC 4122 version 4 UUID from a secure random source.
String uuidV4(Random r) {
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Turns router locations into screen events: onboarding steps, the three non-worship tab roots and
/// the rewards page. Worship screens (Quran, prayer, azkar, duas, hifz, listen) are never tracked.
class RouteTracker {
  RouteTracker(this.analytics);
  final ProductAnalytics analytics;
  String? _last;

  void onLocation(String path) {
    if (path == _last) return;
    _last = path;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.length == 2 && seg[0] == 'onboarding' && ProductEvent.onboardingStep.allows({'step': seg[1]})) {
      unawaited(analytics.trackOnce(ProductEvent.onboardingStep, {'step': seg[1]}));
    } else if (seg.length == 1 && ProductEvent.tabView.allows({'tab': seg[0]})) {
      unawaited(analytics.track(ProductEvent.tabView, {'tab': seg[0]}));
    } else if (path == '/challenge/redeem') {
      unawaited(analytics.track(ProductEvent.redeemView));
    }
  }
}
