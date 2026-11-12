import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/analytics/analytics.dart';
import 'package:yaqeen/core/analytics/sinks/ad_sinks.dart';
import 'package:yaqeen/core/analytics/sinks/google_ad_sink.dart';
import 'package:yaqeen/core/analytics/sinks/meta_ad_sink.dart';
import 'package:yaqeen/core/analytics/sinks/tiktok_ad_sink.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

/// Records every call the Google sink makes to "Firebase Analytics".
class FakeGoogle implements GoogleMeasurement {
  final calls = <String>[];
  final events = <(String, Map<String, Object>)>[];
  ({bool analytics, bool ad, bool userData, bool personalization})? consent;

  @override
  Future<void> setConsent({
    required bool analyticsStorage,
    required bool adStorage,
    required bool adUserData,
    required bool adPersonalization,
  }) async {
    calls.add('consent');
    consent = (analytics: analyticsStorage, ad: adStorage, userData: adUserData, personalization: adPersonalization);
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async => calls.add('collection:$enabled');

  @override
  Future<void> resetData() async => calls.add('reset');

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async {
    calls.add('log:$name');
    events.add((name, params));
  }
}

/// Records every call the Meta sink makes to "the Facebook SDK".
class FakeMeta implements MetaAppEventsApi {
  final calls = <String>[];
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> initializeSdk() async => calls.add('init');
  @override
  Future<void> setAutoLogAppEventsEnabled(bool enabled) async => calls.add('autolog:$enabled');
  @override
  Future<void> setAdvertiserIdCollectionEnabled(bool enabled) async => calls.add('adid:$enabled');
  @override
  Future<void> setLimitEventAndDataUsage(bool limited) async => calls.add('ldu:$limited');
  @override
  Future<void> activateApp() async => calls.add('activate');
  @override
  Future<void> logEvent(String name, Map<String, Object> params) async {
    calls.add('log:$name');
    events.add((name, params));
  }

  @override
  Future<void> logPurchase(double amount, String currency) async {
    calls.add('purchase');
    events.add(('fb_mobile_purchase', {'value': amount, 'currency': currency}));
  }

  @override
  Future<void> clearUserData() async => calls.add('clear');
}

class FakeTikTok implements TikTokEventsApi {
  final calls = <String>[];
  @override
  Future<void> initialize() async => calls.add('init');
  @override
  Future<void> setTrackingEnabled(bool enabled) async => calls.add('tracking:$enabled');
  @override
  Future<void> logEvent(String name, Map<String, Object> params) async => calls.add('log:$name');
}

class ThrowingSink implements AdSink {
  @override
  String get name => 'broken';
  @override
  Future<void> log(AdEvent event, Map<String, Object> params) async => throw StateError('sdk down');
  @override
  Future<void> setEnabled(bool enabled, {bool attAuthorized = false}) => Completer<void>().future; // hangs
}

void main() {
  late FakeGoogle google;
  late FakeMeta meta;
  late bool consent;
  late bool decided;
  late bool att;

  Analytics analytics({List<AdSink>? extra}) => Analytics(
        sinks: [GoogleAdSink(google), MetaAdSink(meta), ...?extra],
        adsConsent: () => consent,
        consentDecided: () => decided,
        attAuthorized: () async => att,
        store: MemoryKvStore(),
        sinkTimeout: const Duration(milliseconds: 50),
      );

  setUp(() {
    google = FakeGoogle();
    meta = FakeMeta();
    consent = false;
    decided = false;
    att = false;
  });

  test('without ads_measurement no SDK is touched — not even initialised', () async {
    final a = analytics();
    await a.start(); // consent screen not answered yet
    for (final e in AdEvent.values) {
      await a.log(e, {'value': 1});
    }
    await a.logOrQueue(AdEvent.firstOpen);
    expect(google.calls, isEmpty);
    expect(meta.calls, isEmpty);

    decided = true; // answered "no": Google is told to stay off; Meta was never started, so stays asleep
    await a.start();
    expect(google.calls, ['collection:false', 'consent', 'reset']);
    expect(meta.calls, isEmpty);
  });

  test('sinks only ever receive AdEvent names and allowlisted params', () async {
    consent = true;
    decided = true;
    att = true;
    final a = analytics();
    const leaky = {
      'surah': 2,
      'prayer': 'fajr',
      'azkar': 'morning',
      'email': 'a@b.c',
      'user_id': 'u1',
      'reward_id': 'r1',
      'day': 7,
      'value': 120,
      'currency': 'EGP',
    };
    for (final e in AdEvent.values) {
      await a.log(e, leaky);
    }

    final googleNames = {for (final e in AdEvent.values) GoogleAdSink.eventName(e)}..remove(null);
    final metaNames = {for (final e in AdEvent.values) MetaAdSink.eventName(e)}..remove(null);
    for (final (name, params) in google.events) {
      expect(googleNames, contains(name));
      expect(Analytics.allowedParams.containsAll(params.keys), isTrue, reason: '$name $params');
    }
    for (final (name, params) in meta.events) {
      expect(metaNames, contains(name));
      expect(Analytics.allowedParams.containsAll(params.keys), isTrue, reason: '$name $params');
    }
    // Every event but first_open went out (reserved in Firebase; Meta attributes installs from activateApp).
    const googleSent = [
      'sign_up',
      'tutorial_complete',
      'challenge_join',
      'streak_7',
      'streak_30',
      'reward_redeem',
      'store_click',
      'purchase',
    ];
    expect(google.events.map((e) => e.$1), googleSent);
    expect(meta.events.length, AdEvent.values.length - 1);
    // Purchase uses the standard value + currency (value as a number), nothing else.
    expect(google.events.last.$2, {'value': 120.0, 'currency': 'EGP'});
    expect(meta.events.last.$2, {'value': 120.0, 'currency': 'EGP'});
    expect(google.events.firstWhere((e) => e.$1 == 'reward_redeem').$2, {'reward_id': 'r1', 'day': 7, 'value': 120, 'currency': 'EGP'});
  });

  test('purchase without a currency carries no value', () async {
    consent = true;
    decided = true;
    await analytics().log(AdEvent.purchase, {'value': 10});
    expect(google.events.single.$2, isEmpty);
    expect(meta.events.single.$1, 'fb_mobile_purchase');
    expect(meta.events.single.$2, isEmpty);
  });

  test('granting consent starts each SDK in measurement-only mode, with the ATT answer', () async {
    decided = true;
    consent = true;
    att = false; // iOS: "Ask App Not to Track"
    final a = analytics();
    await a.onConsentChanged(true);

    expect(google.calls, ['consent', 'collection:true']);
    expect(google.consent, (analytics: true, ad: true, userData: true, personalization: false));
    expect(meta.calls, ['init', 'autolog:false', 'ldu:true', 'adid:false', 'activate']);

    // ATT allowed later (Settings): the advertiser id follows on the next event; init/activate run once.
    att = true;
    await a.log(AdEvent.storeClick);
    expect(meta.calls.skip(5), ['adid:true', 'log:store_click']);
    await a.start();
    expect(meta.calls.where((c) => c == 'init' || c == 'activate'), ['init', 'activate']);
  });

  test('withdrawing consent switches every SDK off and drops the queue', () async {
    decided = true;
    consent = true;
    att = true;
    final a = analytics();
    await a.start();
    google.calls.clear();
    meta.calls.clear();

    consent = false;
    await a.onConsentChanged(false);
    expect(google.calls, ['collection:false', 'consent', 'reset']);
    expect(google.consent, (analytics: false, ad: false, userData: false, personalization: false));
    expect(meta.calls, ['adid:false', 'clear']);

    await a.log(AdEvent.signUp);
    expect(google.events, isEmpty);
    expect(meta.events, isEmpty);
  });

  test('the att flag reaches sinks and is never forwarded as a param', () async {
    decided = true;
    consent = true;
    final debug = DebugAdSink();
    final a = analytics(extra: [debug]);
    await a.log(AdEvent.challengeJoin);
    att = true;
    await a.log(AdEvent.challengeJoin);
    expect(debug.params.map((p) => p['att']), [0, 1]);
    expect(google.events.every((e) => !e.$2.containsKey('att')), isTrue);
    expect(meta.events.every((e) => !e.$2.containsKey('att')), isTrue);
  });

  test('a broken or hanging SDK never breaks the screen that logged', () async {
    decided = true;
    consent = true;
    final a = analytics(extra: [ThrowingSink()]);
    await a.onConsentChanged(true); // ThrowingSink.setEnabled hangs → timed out
    await a.log(AdEvent.signUp); // ThrowingSink.log throws → swallowed
    expect(google.events.map((e) => e.$1), ['sign_up']);
  });

  group('registration', () {
    var googleMade = 0;
    var metaMade = 0;
    List<AdSink> build(AdSinkConfig c, {bool debug = false, TikTokEventsApi Function()? tiktok}) => buildAdSinks(
          c,
          debug: debug,
          google: () {
            googleMade++;
            return FakeGoogle();
          },
          meta: () {
            metaMade++;
            return FakeMeta();
          },
          tiktok: tiktok,
        );

    setUp(() {
      googleMade = 0;
      metaMade = 0;
    });

    test('no build values: no SDK sink, no plugin created; debug builds keep the debug sink', () {
      expect(build(const AdSinkConfig()), isEmpty);
      expect(build(const AdSinkConfig(), debug: true).map((s) => s.name), ['debug']);
      expect(googleMade + metaMade, 0);
    });

    test('Meta needs both the app id and the client token', () {
      expect(build(const AdSinkConfig(facebookAppId: '123')), isEmpty);
      expect(build(const AdSinkConfig(facebookClientToken: 'abc')), isEmpty);
      expect(build(const AdSinkConfig(facebookAppId: ' ', facebookClientToken: 'abc')), isEmpty);
      expect(metaMade, 0);
      expect(build(const AdSinkConfig(facebookAppId: '123', facebookClientToken: 'abc')).map((s) => s.name), ['meta']);
    });

    test('Google only when Firebase Analytics is switched on for the build', () {
      expect(build(const AdSinkConfig(firebaseAnalytics: true)).map((s) => s.name), ['google']);
      expect(googleMade, 1);
    });

    test('TikTok is not registered without a bridge (none ships)', () {
      const all = AdSinkConfig(firebaseAnalytics: true, facebookAppId: '1', facebookClientToken: 't');
      expect(build(all).map((s) => s.name), ['google', 'meta']);
      final tt = FakeTikTok();
      expect(build(all, tiktok: () => tt).map((s) => s.name), ['google', 'meta', 'tiktok']);
      expect(tt.calls, isEmpty); // constructing a sink never touches its SDK
    });

    test('the build has no ad SDK values by default', () {
      final c = AdSinkConfig.fromEnvironment();
      expect(c.google, isFalse);
      expect(c.meta, isFalse);
    });
  });

  test('TikTok sink (when a bridge exists) follows the same gate', () async {
    final tt = FakeTikTok();
    final sink = TikTokAdSink(tt);
    await sink.setEnabled(false);
    expect(tt.calls, isEmpty);
    await sink.log(AdEvent.signUp, {'att': 0, 'email': 'x'});
    await sink.setEnabled(false);
    expect(tt.calls, ['init', 'tracking:true', 'log:Registration', 'tracking:false']);
  });
}
