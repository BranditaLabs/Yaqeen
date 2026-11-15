import 'dart:async';

import '../network/api_client.dart';
import '../storage/kv_store.dart';
import 'push_service.dart';

/// Keeps the server's device row for this install current (POST /v1/me/devices), so campaign and
/// reward pushes can reach it. Registering is not consent: the server's dispatcher sends only what
/// the user's consents and the prayer guardrails allow. A token is re-sent only when it or the
/// account changes; failures (offline) retry on the next start, resume or sign-in.
class PushRegistrar {
  PushRegistrar({required this.api, required this.push, required this.store, required this.platform, required this.appVersion});

  final ApiClient api;
  final PushService push;
  final KvStore store;

  /// `ios` or `android` (contracts `Platform`).
  final String platform;
  final Future<String> Function() appVersion;

  static const _key = 'push.registered.v1';
  String? _userId;
  StreamSubscription<String>? _refresh;

  /// Registers for [userId] (null = signed out: nothing to send to).
  Future<void> sync(String? userId) async {
    _userId = userId;
    if (userId == null) return;
    _refresh ??= push.onTokenRefresh.listen((t) => _send(t).ignore());
    final token = await push.token();
    if (token != null) await _send(token);
  }

  Future<void> _send(String token) async {
    final user = _userId;
    if (user == null) return;
    final version = await appVersion();
    final stamp = '$user|$token|$version';
    if (await store.read(_key) == stamp) return;
    await api.post('/v1/me/devices', {'platform': platform, 'fcmToken': token, 'appVersion': version});
    await store.write(_key, stamp);
  }

  /// Counts the open for the campaign a tapped push came from (idempotent on the server).
  Future<void> opened(PushOpened o) async {
    final id = o.campaignId;
    if (id == null || _userId == null) return;
    await api.post('/v1/me/campaigns/$id/opened');
  }

  void dispose() => _refresh?.cancel();
}
