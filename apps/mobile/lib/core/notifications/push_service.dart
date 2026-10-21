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

/// Maps `yaqeen://<target>` to a router location. Unknown targets go home.
String routeForDeepLink(Uri uri) {
  const map = {
    'home': '/home',
    'quran': '/quran',
    'prayer': '/prayer',
    'challenge': '/challenge',
    // Calendar / azkar / hifz get their own sub-routes when those screens land.
    'calendar': '/challenge',
    'redeem': '/challenge/redeem',
    'azkar': '/home',
    'hifz': '/quran',
    'store': '/challenge/redeem',
  };
  final key = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
  return map[key] ?? '/home';
}
