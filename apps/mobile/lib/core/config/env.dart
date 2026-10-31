/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md):
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000 --dart-define=FLAVOR=dev
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000');
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const storeUrl = String.fromEnvironment('STORE_URL', defaultValue: 'https://www.yaqin-brand.com');

  /// The Yaqeen website (privacy policy, terms, help) — served by the API on the cards host.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://api.yaqin-brand.com');

  /// A website page in the user's language, e.g. `site('privacy', 'ar')`.
  static Uri site(String page, String locale) => Uri.parse('$siteUrl/$page?lang=$locale');

  /// OAuth client id of the API (Google "server client id"); the ID token's audience. Default: the
  /// Web client of Firebase project `yaqeen-eg` (public, ships in every build).
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '215304787392-2papc2vde7pj9j6uh7u6pgdsokff8gen.apps.googleusercontent.com',
  );

  /// Sign in with Apple on Android uses the web flow: Services ID + the API's redirect endpoint.
  static const appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID', defaultValue: 'com.yaqinbrand.yaqeen.signin');
  static const appleRedirectUri =
      String.fromEnvironment('APPLE_REDIRECT_URI', defaultValue: 'https://api.yaqin-brand.com/v1/auth/apple/callback');

  /// Where the per-page KFGQPC QCF V2 mushaf fonts (`p{page}.ttf`) are downloaded from. Default:
  /// Quran.com's public CDN (spec §10); set it to our CDN once we mirror the 604 files.
  static const mushafFontBaseUrl =
      String.fromEnvironment('MUSHAF_FONT_BASE_URL', defaultValue: 'https://static.qurancdn.com/fonts/quran/hafs/v2/ttf/');

  /// Sentry DSN for crash/error reports; empty = reporting off (dev, tests).
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Ad measurement SDKs (lib/core/analytics/sinks). Each one is registered only when its build-time
  /// values are present, and even then stays off until the user grants `ads_measurement`.
  ///
  /// Google Ads through Firebase Analytics (project `yaqeen-eg`): `true` once Google Analytics is
  /// enabled on the Firebase project and linked to Google Ads.
  static const firebaseAnalytics = bool.fromEnvironment('FIREBASE_ANALYTICS');

  /// Meta App Events. The same values must reach the native config: Android reads these dart-defines
  /// in `android/app/build.gradle.kts`; iOS reads `FACEBOOK_APP_ID` / `FACEBOOK_CLIENT_TOKEN` from
  /// `ios/Flutter/Secrets.xcconfig` (docs/RELEASE_MOBILE.md).
  static const facebookAppId = String.fromEnvironment('FACEBOOK_APP_ID');
  static const facebookClientToken = String.fromEnvironment('FACEBOOK_CLIENT_TOKEN');

  static bool get isProd => flavor == 'prod';
}
