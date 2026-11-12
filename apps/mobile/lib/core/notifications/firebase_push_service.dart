import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/firebase_app.dart';
import 'push_service.dart';
import 'push_spool.dart';

/// Where pushes that arrive in the background wait for the app (see [PushSpool]).
final pushSpool = PushSpool(() async => File('${(await getApplicationSupportDirectory()).path}/push_inbox.jsonl'));

PushMessage? _messageOf(RemoteMessage msg) => PushMessage.from(
      messageId: msg.messageId,
      title: msg.notification?.title,
      body: msg.notification?.body,
      sentTime: msg.sentTime,
      data: msg.data,
      now: DateTime.now(),
    );

/// Runs in FCM's background isolate (app in the background or closed): the OS already shows the
/// notification; this only keeps it for the notification centre.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage msg) async {
  final m = _messageOf(msg);
  if (m != null) await pushSpool.append(m);
}

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
  /// [showInForeground] posts a push that arrives while the app is open (Android only: the OS
  /// doesn't show those; iOS does, see `setForegroundNotificationPresentationOptions`).
  FirebasePushService({this.showInForeground});

  final Future<void> Function(PushMessage m)? showInForeground;
  Future<FirebaseMessaging>? _ready;
  final _opened = StreamController<PushOpened>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final _received = StreamController<PushMessage>.broadcast();
  final _arrived = <PushMessage>[];

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
    FirebaseMessaging.onMessage.listen(_receive);
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    // ignore: deprecated_member_use
    m.onTokenRefresh.listen(_tokens.add);
    final initial = await m.getInitialMessage();
    if (initial != null) scheduleMicrotask(() => _open(initial));
    return m;
  }

  void _receive(RemoteMessage msg) {
    final m = _messageOf(msg);
    if (m == null) return;
    _received.add(m);
    if (Platform.isAndroid) showInForeground?.call(m).catchError((Object _) {}).ignore();
  }

  void _open(RemoteMessage msg) {
    // iOS doesn't wake the app for a plain notification push, so a tapped one may be news to it.
    final m = _messageOf(msg);
    if (m != null) _arrived.add(m);
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

  @override
  Stream<PushMessage> get onReceived => _received.stream;

  @override
  Future<List<PushMessage>> takeArrived() async {
    final out = [..._arrived];
    _arrived.clear();
    try {
      out.addAll(await pushSpool.take());
    } catch (_) {
      // Unreadable spool: those pushes were still shown by the OS.
    }
    return out;
  }
}
