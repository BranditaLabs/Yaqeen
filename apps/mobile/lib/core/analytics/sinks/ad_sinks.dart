import '../../config/env.dart';
import '../analytics.dart';
import 'google_ad_sink.dart';
import 'meta_ad_sink.dart';
import 'tiktok_ad_sink.dart';

/// Which ad SDKs this build carries values for (dart-defines, lib/core/config/env.dart).
class AdSinkConfig {
  const AdSinkConfig({this.firebaseAnalytics = false, this.facebookAppId = '', this.facebookClientToken = ''});

  factory AdSinkConfig.fromEnvironment() => const AdSinkConfig(
        firebaseAnalytics: Env.firebaseAnalytics,
        facebookAppId: Env.facebookAppId,
        facebookClientToken: Env.facebookClientToken,
      );

  final bool firebaseAnalytics;
  final String facebookAppId;
  final String facebookClientToken;

  bool get google => firebaseAnalytics;
  bool get meta => facebookAppId.trim().isNotEmpty && facebookClientToken.trim().isNotEmpty;
}

/// The sinks to register. An SDK without its build values is not registered, so its plugin is never
/// called and the SDK never starts. The factories run only for registered sinks, and no sink touches
/// its SDK before `Analytics.start` / `onConsentChanged` / a consented `log`.
///
/// TikTok: registered only with a [tiktok] bridge, which no build passes today (see [TikTokEventsApi]).
/// [debug] adds the in-memory [DebugAdSink] (debug builds only).
List<AdSink> buildAdSinks(
  AdSinkConfig config, {
  required bool debug,
  required GoogleMeasurement Function() google,
  required MetaAppEventsApi Function() meta,
  TikTokEventsApi Function()? tiktok,
}) =>
    [
      if (config.google) GoogleAdSink(google()),
      if (config.meta) MetaAdSink(meta()),
      if (tiktok != null) TikTokAdSink(tiktok()),
      if (debug) DebugAdSink(),
    ];
