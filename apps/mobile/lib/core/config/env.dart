/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md):
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000 --dart-define=FLAVOR=dev
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000');
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const storeUrl = String.fromEnvironment('STORE_URL', defaultValue: 'https://www.yaqin-brand.com');

  /// OAuth client id of the API (Google "server client id"); the ID token's audience.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Sign in with Apple on Android uses the web flow: Services ID + the API's redirect endpoint.
  static const appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID', defaultValue: 'com.yaqinbrand.yaqeen.signin');
  static const appleRedirectUri =
      String.fromEnvironment('APPLE_REDIRECT_URI', defaultValue: 'https://api.yaqin-brand.com/v1/auth/apple/callback');

  static bool get isProd => flavor == 'prod';
}
