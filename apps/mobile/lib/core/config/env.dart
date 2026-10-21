/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md):
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000 --dart-define=FLAVOR=dev
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000');
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const storeUrl = String.fromEnvironment('STORE_URL', defaultValue: 'https://www.yaqin-brand.com');

  static bool get isProd => flavor == 'prod';
}
