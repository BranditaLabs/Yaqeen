import '../analytics.dart';
import 'sink_params.dart';

/// The slice of the Meta (Facebook) App Events SDK the Meta sink uses. The plugin adapter is
/// [PluginMetaAppEvents] (meta_app_events_plugin.dart); tests use a recording fake.
abstract interface class MetaAppEventsApi {
  /// Starts the SDK. Automatic initialisation is off in the native config, so before this call the
  /// SDK contacts no Meta server.
  Future<void> initializeSdk();
  Future<void> setAutoLogAppEventsEnabled(bool enabled);
  Future<void> setAdvertiserIdCollectionEnabled(bool enabled);

  /// Limited event and data usage: events serve measurement and conversions, not ad targeting.
  Future<void> setLimitEventAndDataUsage(bool limited);

  /// The app-launch signal Meta attributes installs with (sent by hand: automatic logging is off).
  Future<void> activateApp();
  Future<void> logEvent(String name, Map<String, Object> params);
  Future<void> logPurchase(double amount, String currency);
  Future<void> clearUserData();
}

/// Meta App Events. Receives only [AdEvent]s with allowlisted params, and an app launch per session
/// while consent is on. Never a user id or user data; the advertising id only with consent and,
/// on iOS, ATT.
class MetaAdSink implements AdSink {
  MetaAdSink(this._sdk);

  final MetaAppEventsApi _sdk;
  bool _initialized = false;
  bool _activated = false;
  bool _enabled = false;
  bool? _advertiserId;

  @override
  String get name => 'meta';

  /// Meta standard events where one fits, our wire name otherwise. `first_open` is not sent: the
  /// install is attributed from [MetaAppEventsApi.activateApp].
  static String? eventName(AdEvent e) => switch (e) {
        AdEvent.firstOpen => null,
        AdEvent.signUp => 'fb_mobile_complete_registration',
        AdEvent.onboardingComplete => 'fb_mobile_tutorial_completion',
        AdEvent.purchase => 'fb_mobile_purchase',
        _ => e.wireName,
      };

  @override
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false}) async {
    if (!enabled) {
      _enabled = false;
      // Never started in this launch: the SDK is asleep, there is nothing to switch off.
      if (!_initialized) return;
      await _setAdvertiserId(false);
      await _sdk.clearUserData();
      return;
    }
    if (!_initialized) {
      await _sdk.initializeSdk();
      _initialized = true;
    }
    await _sdk.setAutoLogAppEventsEnabled(false);
    await _sdk.setLimitEventAndDataUsage(true);
    await _setAdvertiserId(attAuthorized);
    _enabled = true;
    if (!_activated) {
      _activated = true;
      await _sdk.activateApp();
    }
  }

  Future<void> _setAdvertiserId(bool on) async {
    if (_advertiserId == on) return;
    await _sdk.setAdvertiserIdCollectionEnabled(on);
    _advertiserId = on;
  }

  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async {
    final att = attFrom(params);
    if (!_enabled) {
      await setEnabled(true, attAuthorized: att);
    } else {
      await _setAdvertiserId(att); // ATT answered or changed in Settings since the SDK started
    }
    final name = eventName(event);
    if (name == null) return;
    if (event == AdEvent.purchase) {
      final p = purchaseOf(params);
      if (p != null) return _sdk.logPurchase(p.value, p.currency);
      return _sdk.logEvent(name, const {});
    }
    await _sdk.logEvent(name, forwardableParams(params));
  }
}
