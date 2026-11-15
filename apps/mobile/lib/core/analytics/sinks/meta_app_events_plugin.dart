import 'package:facebook_app_events/facebook_app_events.dart';

import 'meta_ad_sink.dart';

/// [MetaAppEventsApi] on the facebook_app_events plugin. App id and client token come from the
/// native config (AndroidManifest placeholders / Info.plist), filled from the build's secrets.
class PluginMetaAppEvents implements MetaAppEventsApi {
  final _fb = FacebookAppEvents();

  @override
  Future<void> initializeSdk() => _fb.initializeSdk();

  @override
  Future<void> setAutoLogAppEventsEnabled(bool enabled) => _fb.setAutoLogAppEventsEnabled(enabled);

  @override
  Future<void> setAdvertiserIdCollectionEnabled(bool enabled) => _fb.setAdvertiserIdCollectionEnabled(enabled);

  @override
  Future<void> setLimitEventAndDataUsage(bool limited) => _fb.setLimitEventAndDataUsage(limited);

  @override
  Future<void> activateApp() => _fb.activateApp();

  @override
  Future<void> logEvent(String name, Map<String, Object> params) => _fb.logEvent(name: name, parameters: params.isEmpty ? null : params);

  @override
  Future<void> logPurchase(double amount, String currency) => _fb.logPurchase(amount: amount, currency: currency);

  @override
  Future<void> clearUserData() => _fb.clearUserData();
}
