import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../platform/firebase_app.dart';
import 'push_service.dart';

/// FCM adapter for [PushService]. Firebase starts lazily on first use (after the first frame), so
/// it never sits on the start-up path; a failure is retried on the next call.
///
/// Only messaging is used here. (Firebase Analytics is a separate ad sink, off by default and on only
/// with `ads_measurement` — core/analytics/sinks.) The server decides who receives what: consents,
/// quiet hours, prayer windows.
///
/// Tokens: `getToken`/`onTokenRefresh` are deprecated in favour of `register()`/`onRegistered`, which
/// yield an installation id; the API sends with firebase-admin to registration tokens, so we stay on
/// tokens until the sender moves to installation ids.
class FirebasePushService implements PushService {
  Future<FirebaseMessaging>? _ready;
  final _opened = StreamController<PushOpened>.broadcast();
  final _tokens = StreamController<String>.broadcast();

  Future<FirebaseMessaging> _messaging() => _ready ??= _setUp().catchError((Object e) {
        _ready = null;
        throw e;
      });

  Future<FirebaseMessaging> _setUp() async {
    await FirebaseAppStarter.ensure();
    final m = FirebaseMessaging.instance;
    // iOS: show campaign pushes that arrive while the app is open, like the OS does in the background.
    await m.setForegroundNotificationPresentationOptions(alert: true, sound: true);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    // ignore: deprecated_member_use
    m.onTokenRefresh.listen(_tokens.add);
    final initial = await m.getInitialMessage();
    if (initial != null) scheduleMicrotask(() => _open(initial));
    return m;
  }

  void _open(RemoteMessage msg) {
    final link = msg.data['link'];
    if (link is! String || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    final campaign = msg.data['campaignId'];
    _opened.add(PushOpened(uri, campaignId: campaign is String && campaign.isNotEmpty ? campaign : null));
  }

  /// Starts Firebase so a push that launched the app is routed. Safe to call more than once.
  Future<void> start() => _messaging();

  @override
  Future<bool> requestPermission() async {
    final s = await (await _messaging()).requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  // ignore: deprecated_member_use
  Future<String?> token() async => (await _messaging()).getToken();

  @override
  Stream<String> get onTokenRefresh => _tokens.stream;

  @override
  Stream<PushOpened> get onOpened => _opened.stream;
}
