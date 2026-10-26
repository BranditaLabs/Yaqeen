/// Remote push (FCM / APNs via Firebase) — campaigns and reward nudges only.
/// The server applies quiet hours, prayer windows and daily caps (services/api
/// src/domain/guardrails.ts); the app only registers the token and routes taps.
abstract interface class PushService {
  /// Ask for permission (iOS prompt, Android 13+ POST_NOTIFICATIONS).
  Future<bool> requestPermission();

  /// Current FCM token, or null if unavailable.
  Future<String?> token();

  /// Emits a token whenever FCM rotates it — re-register with POST /v1/me/devices.
  Stream<String> get onTokenRefresh;

  /// Emits the deep link (e.g. "yaqeen://redeem") when the user taps a push.
  Stream<Uri> get onOpened;
}

class NoopPushService implements PushService {
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<Uri> get onOpened => const Stream.empty();
}

/// Deep-link targets (`yaqeen://<target>` and `https://yaqin-brand.com/app/<target>`, spec §4.2).
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
};

/// Maps a deep link to a router location. Unknown targets go home.
/// `yaqeen://tag/<code>` (the «activate in the app» button on a blank medal's page) opens the card
/// screen with the code ready to activate.
String routeForDeepLink(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'yaqeen' && uri.host == 'tag' && segments.isNotEmpty) {
    final code = segments.first.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    if (code.isNotEmpty && code.length <= 16) return '/profile/card?tag=$code';
  }
  final String key;
  if (uri.scheme == 'yaqeen') {
    key = uri.host.isNotEmpty ? uri.host : (segments.isNotEmpty ? segments.first : '');
  } else {
    // Universal link: https://yaqin-brand.com/app/<target>
    final i = segments.indexOf('app');
    key = i >= 0 && i + 1 < segments.length ? segments[i + 1] : '';
  }
  return deepLinkRoutes[key] ?? '/home';
}
