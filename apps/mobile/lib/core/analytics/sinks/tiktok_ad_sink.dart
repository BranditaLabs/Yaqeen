import '../analytics.dart';
import 'sink_params.dart';

/// The slice of a TikTok Business SDK bridge a TikTok sink would use.
///
/// **No implementation ships**, so [TikTokAdSink] is never registered (see `buildAdSinks`). TikTok
/// has no official Flutter plugin; the community wrapper we reviewed (`tiktok_events_sdk`) pulls the
/// Android SDK from JitPack, ships two diverging iOS source trees (CocoaPods vs Swift Package), and
/// shows its own ATT prompt and automatic install/launch/retention tracking unless each is switched
/// off. TikTok attribution goes through the server-side Events API instead (purchase conversions from
/// the Shopify webhook — docs/ANALYTICS_EVENTS.md). If an official plugin appears, implement this
/// interface with: tracking, automatic events and the SDK's ATT dialog off at init; tracking on only
/// via [setTrackingEnabled].
abstract interface class TikTokEventsApi {
  Future<void> initialize();
  Future<void> setTrackingEnabled(bool enabled);
  Future<void> logEvent(String name, Map<String, Object> params);
}

/// TikTok app events — ready for a bridge, not registered today.
class TikTokAdSink implements AdSink {
  TikTokAdSink(this._sdk);

  final TikTokEventsApi _sdk;
  bool _initialized = false;
  bool _enabled = false;

  @override
  String get name => 'tiktok';

  /// TikTok standard app events where one fits, our wire name otherwise.
  static String? eventName(AdEvent e) => switch (e) {
        AdEvent.firstOpen => null, // the SDK's own install event
        AdEvent.signUp => 'Registration',
        AdEvent.onboardingComplete => 'CompleteTutorial',
        AdEvent.purchase => 'Purchase',
        _ => e.wireName,
      };

  @override
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false}) async {
    if (!enabled) {
      _enabled = false;
      if (_initialized) await _sdk.setTrackingEnabled(false);
      return;
    }
    if (!_initialized) {
      await _sdk.initialize();
      _initialized = true;
    }
    await _sdk.setTrackingEnabled(true);
    _enabled = true;
  }

  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async {
    if (!_enabled) await setEnabled(true, attAuthorized: attFrom(params));
    final name = eventName(event);
    if (name == null) return;
    if (event == AdEvent.purchase) {
      final p = purchaseOf(params);
      return _sdk.logEvent(name, p == null ? const {} : {'value': p.value, 'currency': p.currency});
    }
    await _sdk.logEvent(name, forwardableParams(params));
  }
}
