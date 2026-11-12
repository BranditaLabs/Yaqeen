import '../analytics.dart';
import 'sink_params.dart';

/// The slice of Firebase Analytics the Google sink uses. The plugin adapter is
/// [FirebaseGoogleMeasurement] (firebase_measurement.dart); tests use a recording fake.
abstract interface class GoogleMeasurement {
  /// Google consent mode v2.
  Future<void> setConsent({
    required bool analyticsStorage,
    required bool adStorage,
    required bool adUserData,
    required bool adPersonalization,
  });

  /// Collection is off by default in the native config and only switched on here.
  Future<void> setCollectionEnabled(bool enabled);

  /// Clears the analytics data and app-instance id kept on the device.
  Future<void> resetData();

  Future<void> logEvent(String name, Map<String, Object> params);
}

/// Google Ads conversions through Firebase Analytics (GA4 linked to Google Ads).
///
/// Receives only [AdEvent]s with allowlisted params. No user id, no user properties, no screen
/// views (automatic screen reporting is off natively). Ad personalisation stays denied: the user
/// agreed to measurement, not to personalised ads.
class GoogleAdSink implements AdSink {
  GoogleAdSink(this._sdk);

  final GoogleMeasurement _sdk;
  bool _enabled = false;

  @override
  String get name => 'google';

  /// GA4 names: recommended events where one fits, our wire name otherwise. `first_open` is reserved
  /// by Firebase and logged by the SDK itself, so ours is not sent.
  static String? eventName(AdEvent e) => switch (e) {
        AdEvent.firstOpen => null,
        AdEvent.signUp => 'sign_up',
        AdEvent.onboardingComplete => 'tutorial_complete',
        AdEvent.purchase => 'purchase',
        _ => e.wireName,
      };

  @override
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false}) async {
    if (enabled) {
      // The SDK reads the IDFA itself only when ATT allows it; consent mode covers the rest.
      await _sdk.setConsent(analyticsStorage: true, adStorage: true, adUserData: true, adPersonalization: false);
      await _sdk.setCollectionEnabled(true);
    } else {
      await _sdk.setCollectionEnabled(false);
      await _sdk.setConsent(analyticsStorage: false, adStorage: false, adUserData: false, adPersonalization: false);
      await _sdk.resetData();
    }
    _enabled = enabled;
  }

  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async {
    // Analytics calls log only with consent; the first event of a launch may come before start().
    if (!_enabled) await setEnabled(true, attAuthorized: attFrom(params));
    final name = eventName(event);
    if (name == null) return;
    if (event == AdEvent.purchase) {
      final p = purchaseOf(params);
      await _sdk.logEvent(name, p == null ? const {} : {'value': p.value, 'currency': p.currency});
      return;
    }
    await _sdk.logEvent(name, forwardableParams(params));
  }
}
