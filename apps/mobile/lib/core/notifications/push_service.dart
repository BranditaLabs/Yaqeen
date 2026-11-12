/// Remote push (FCM / APNs via Firebase) — campaigns and reward nudges only.
/// The server applies quiet hours, prayer windows and daily caps (services/api
/// src/domain/guardrails.ts); the app registers the token, routes taps and files arrivals in the
/// notification centre.
abstract interface class PushService {
  /// Ask for permission (iOS prompt, Android 13+ POST_NOTIFICATIONS).
  Future<bool> requestPermission();

  /// Current FCM token, or null if unavailable.
  Future<String?> token();

  /// Emits a token whenever FCM rotates it — re-register with POST /v1/me/devices.
  Stream<String> get onTokenRefresh;

  /// Emits when the user taps a push (including the one that launched the app).
  Stream<PushOpened> get onOpened;

  /// Pushes that arrive while the app is open — for the notification centre (spec §5.18).
  Stream<PushMessage> get onReceived;

  /// Pushes that arrived while the app was in the background or closed, or that were tapped; each
  /// is handed out once. The caller files them in the notification centre (ids dedupe).
  Future<List<PushMessage>> takeArrived();
}

/// A remote push as the notification centre keeps it. [category] is the optional `category` data
/// field (`challenge` · `offers`); without it the app files the push by its link.
class PushMessage {
  const PushMessage({required this.id, required this.title, required this.body, required this.at, this.link, this.campaignId, this.category});

  final String id;
  final String title;
  final String body;
  final DateTime at;
  final String? link;
  final String? campaignId;
  final String? category;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'b': body,
        'at': at.toUtc().toIso8601String(),
        'l': link,
        'cid': campaignId,
        'c': category,
      };

  factory PushMessage.fromJson(Map<String, dynamic> j) => PushMessage(
        id: j['id'] as String,
        title: j['t'] as String,
        body: j['b'] as String,
        at: DateTime.parse(j['at'] as String),
        link: j['l'] as String?,
        campaignId: j['cid'] as String?,
        category: j['c'] as String?,
      );

  /// From an FCM message's parts; null when there is nothing to show.
  static PushMessage? from({
    String? messageId,
    String? title,
    String? body,
    DateTime? sentTime,
    required Map<String, dynamic> data,
    required DateTime now,
  }) {
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    final t = str(title) ?? str(data['title']) ?? '';
    final b = str(body) ?? str(data['body']) ?? '';
    if (t.isEmpty && b.isEmpty) return null;
    final at = sentTime ?? now;
    return PushMessage(
      id: str(messageId) ?? '${at.millisecondsSinceEpoch}-${Object.hash(t, b)}',
      title: t,
      body: b,
      at: at,
      link: str(data['link']),
      campaignId: str(data['campaignId']),
      category: str(data['category']),
    );
  }
}

/// A tapped push: where it leads, and the campaign it came from (for the open count).
class PushOpened {
  const PushOpened(this.link, {this.campaignId});
  final Uri link;
  final String? campaignId;
}

class NoopPushService implements PushService {
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushOpened> get onOpened => const Stream.empty();
  @override
  Stream<PushMessage> get onReceived => const Stream.empty();
  @override
  Future<List<PushMessage>> takeArrived() async => const [];
}

/// Deep-link targets (`yaqeen://<target>` and `https://yaqeenarabia.com/app/<target>`, spec §4.2).
const deepLinkRoutes = {
  'home': '/home',
  'quran': '/quran',
  'prayer': '/prayer',
  'challenge': '/challenge',
  'calendar': '/challenge/calendar',
  'redeem': '/challenge/redeem',
  'azkar': '/home/azkar',
  'duas': '/home/duas',
  'inbox': '/home/inbox',
  'hifz': '/quran/hifz',
  'qibla': '/prayer/qibla',
  'store': '/challenge/redeem',
  'card': '/profile/card',
  'ramadan': '/prayer/ramadan',
  'khatma': '/quran/khatma',
};

/// Maps a deep link to a router location. Unknown targets go home.
/// `yaqeen://tag/<code>` (the «activate in the app» button on a blank medal's page) opens the card
/// screen with the code ready to activate. `yaqeen://encode/<token>` (admin › «ترميز بالهاتف», staff
/// only) opens the encoding screen; it is never a campaign target and has no tab or menu entry.
String routeForDeepLink(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'yaqeen' && uri.host == 'encode') {
    final token = segments.length == 1 ? segments.first : '';
    return RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ? '/encode/$token' : '/home';
  }
  if (uri.scheme == 'yaqeen' && uri.host == 'tag' && segments.isNotEmpty) {
    final code = segments.first.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    if (code.isNotEmpty && code.length <= 16) return '/profile/card?tag=$code';
  }
  final String key;
  if (uri.scheme == 'yaqeen') {
    key = uri.host.isNotEmpty ? uri.host : (segments.isNotEmpty ? segments.first : '');
  } else {
    // Universal link: https://yaqeenarabia.com/app/<target>
    final i = segments.indexOf('app');
    key = i >= 0 && i + 1 < segments.length ? segments[i + 1] : '';
  }
  return deepLinkRoutes[key] ?? '/home';
}
