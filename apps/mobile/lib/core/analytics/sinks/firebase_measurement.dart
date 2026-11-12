import 'package:firebase_analytics/firebase_analytics.dart';

import '../../platform/firebase_app.dart';
import 'google_ad_sink.dart';

/// [GoogleMeasurement] on the firebase_analytics plugin. Firebase starts on first use (shared with
/// push), never before the first frame.
class FirebaseGoogleMeasurement implements GoogleMeasurement {
  Future<FirebaseAnalytics> _analytics() async => FirebaseAnalytics.instanceFor(app: await FirebaseAppStarter.ensure());

  @override
  Future<void> setConsent({
    required bool analyticsStorage,
    required bool adStorage,
    required bool adUserData,
    required bool adPersonalization,
  }) async =>
      (await _analytics()).setConsent(
        analyticsStorageConsentGranted: analyticsStorage,
        adStorageConsentGranted: adStorage,
        adUserDataConsentGranted: adUserData,
        adPersonalizationSignalsConsentGranted: adPersonalization,
      );

  @override
  Future<void> setCollectionEnabled(bool enabled) async => (await _analytics()).setAnalyticsCollectionEnabled(enabled);

  @override
  Future<void> resetData() async => (await _analytics()).resetAnalyticsData();

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      (await _analytics()).logEvent(name: name, parameters: params.isEmpty ? null : params);
}
