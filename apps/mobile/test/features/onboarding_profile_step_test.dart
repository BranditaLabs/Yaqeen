import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/design/living_sky.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/platform/photo_picker.dart';
import 'package:yaqeen/core/platform/social_auth.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/settings/settings_controller.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/theme.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_avatar.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/onboarding/presentation/profile_step.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';
import 'package:yaqeen/core/theme/tokens.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/features/onboarding/presentation/profile_step_motion.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// A picker that is available (a phone with a photo library) and returns nothing.
class _AvailablePicker implements PhotoPicker {
  @override
  bool get available => true;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async => PickedPhoto(bytes: Uint8List(0));
}

final _leaguesOn = RemoteConfig(features: {...RemoteConfig.defaultFeatures}..[Flags.leagues] = true);

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });

  late MemoryKvStore kv;
  late MemoryKvStore secure;
  late Directory dir;
  late List<String> calls;
  late List<Object?> bodies;
  late Future<http.Response> Function(http.Request) handler;
  late FakeDeviceServices device;

  setUp(() {
    YqGlassConfig.enableBlur = false;
    kv = MemoryKvStore();
    secure = MemoryKvStore();
    dir = Directory.systemTemp.createTempSync('yq_ob_profile');
    calls = [];
    bodies = [];
    handler = (_) async => http.Response('', 503);
    device = FakeDeviceServices();
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  const guest = Session(provider: SignInProvider.guest, userId: 'g1');
  const google = Session(provider: SignInProvider.google, userId: 'u1', displayName: 'Ahmed Hamdy');

  Widget app({
    Session session = guest,
    RemoteConfig? config,
    PhotoPicker picker = const NoopPhotoPicker(),
    String locale = 'ar',
    SocialAuth? social,
  }) {
    final router = GoRouter(
      initialLocation: '/onboarding/profile',
      routes: [
        GoRoute(path: '/onboarding/routine', builder: (_, __) => const Scaffold(body: Text('ROUTINE'))),
        GoRoute(path: '/onboarding/profile', builder: (_, __) => const ProfileStep()),
        GoRoute(path: '/onboarding/download', builder: (_, __) => const Scaffold(body: Text('DOWNLOAD'))),
      ],
    );
    return ProviderScope(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(secure),
        skyClockProvider.overrideWithValue(fixedSkyClock),
        clockProvider.overrideWithValue(fixedSkyClock),
        initialSettingsProvider.overrideWithValue(AppSettings(place: Place.cairo, locale: locale, onboardingStep: 6)),
        initialSessionProvider.overrideWithValue(session),
        initialConfigProvider.overrideWithValue(config ?? _leaguesOn),
        photoPickerProvider.overrideWithValue(picker),
        deviceServicesProvider.overrideWithValue(device),
        filesDirProvider.overrideWithValue(() async => dir),
        if (social != null) socialAuthProvider.overrideWithValue(social),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            baseUrl: 'https://api.test',
            tokens: ref.watch(tokenStoreProvider),
            client: MockClient((req) async {
              calls.add('${req.method} ${req.url.path}');
              bodies.add(req.body.isEmpty ? null : jsonDecode(req.body));
              return handler(req);
            }),
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: YqTheme.light(),
          locale: Locale(ref.watch(settingsProvider.select((s) => s.locale))),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // presets decoded (or the wait capped)
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }

  Finder toggle(String label) =>
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label && w.properties.toggled != null);
  bool toggled(WidgetTester tester, String label) => tester.widget<Semantics>(toggle(label)).properties.toggled!;

  const joinLabel = 'انضم إلى الدوري الأسبوعي';
  const attestLabel = 'عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري';

  testWidgets('guest: a preset and a name are saved on the phone, nothing reaches /v1/me/profile', (tester) async {
    await open(tester, app());
    expect(find.text('ملفّك في يقين'), findsOneWidget);
    expect(find.text('الخطوة 6 من 6'), findsNothing); // the stepper speaks through semantics
    expect(find.bySemanticsLabel('الخطوة 6 من 6'), findsOneWidget);
    expect(find.text('06 / 06'), findsOneWidget);
    expect(find.text('بداية الطريق'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('عمامة'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  سارة  ');
    await tester.pump();
    // The live preview under the ring, and the person's row in the miniature league.
    expect(find.text('سارة'), findsNWidgets(2));
    await tester.tap(find.text('متابعة'));
    await settle(tester);

    expect(find.text('DOWNLOAD'), findsOneWidget);
    final saved = jsonDecode(kv.data[ProfileRepository.meKey]!) as Map;
    expect(saved['displayName'], 'سارة');
    expect(saved['avatar'], {'kind': 'preset', 'id': 'm03'});
    expect(jsonDecode(kv.data[ProfileRepository.dirtyKey]!), containsPair('name', true));
    expect(jsonDecode(kv.data[ProfileRepository.dirtyKey]!), containsPair('avatar', true));
    expect(calls.where((c) => c.contains('/v1/me/profile') || c.contains('/v1/me/community')), isEmpty);
    expect(kv.data['settings.v1'], contains('"onboardingRoute":"/onboarding/download"'));
  });

  testWidgets('filter: men and women each show their 8 presets', (tester) async {
    await open(tester, app());
    expect(find.bySemanticsLabel('حجاب كحلي'), findsOneWidget);
    await tester.tap(find.text('رجال'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('عمامة'), findsOneWidget);
    expect(find.bySemanticsLabel('حجاب كحلي'), findsNothing);
    await tester.tap(find.text('نساء'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('عمامة'), findsNothing);
    expect(find.bySemanticsLabel('حجاب كحلي'), findsOneWidget);
  });

  testWidgets('guest: the league switch is off; tapping it asks to sign in and stays off on «لاحقاً»', (tester) async {
    await open(tester, app());
    expect(toggled(tester, joinLabel), isFalse);
    expect(find.text('يرى المشاركون اسمك وصورتك ومستواك ونقاط الأسبوع فقط.'), findsOneWidget);
    expect(find.text('لا يرى أحد صلواتك ولا أذكارك ولا مهامك. تغادر متى شئت.'), findsOneWidget);
    await tester.tap(toggle(joinLabel));
    await tester.pumpAndSettle();
    expect(find.text('سجّل الدخول لتنضم إلى الدوري'), findsOneWidget);
    await tester.tap(find.text('لاحقاً'));
    await tester.pumpAndSettle();
    expect(toggled(tester, joinLabel), isFalse);
    expect(toggle(attestLabel), findsNothing);
    expect(calls.where((c) => c.contains('/v1/me/') || c.contains('/v1/auth/')), isEmpty);
  });

  testWidgets('guest who signs in from the switch: the field takes the first name and the join sends it', (tester) async {
    await TokenStore(secure).save(access: 'g-a', refresh: 'g-r');
    handler = (req) async {
      if (req.method == 'POST' && req.url.path == '/v1/auth/link') {
        return json({
          'accessToken': 'a2',
          'refreshToken': 'r2',
          'user': {'id': 'g1', 'displayName': 'Ahmed Hamdy'},
        });
      }
      if (req.method == 'PUT' && req.url.path == '/v1/me/community') {
        return json({'leagues': true, 'leaderboard': false, 'leaderboardCountry': false, 'banned': false, 'attestedAdult': true});
      }
      if (req.method == 'GET' && req.url.path == '/v1/me/profile') return http.Response('', 503);
      return http.Response('', 204);
    };
    await open(tester, app(social: FakeSocialAuth(credential: const SocialCredential(idToken: 'id'))));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

    await tester.tap(toggle(joinLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المتابعة باستخدام Google'));
    await settle(tester);
    await settle(tester);

    expect(toggled(tester, joinLabel), isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Ahmed'); // never 'Ahmed Hamdy'
    await tester.tap(toggle(attestLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await settle(tester);

    expect(find.text('DOWNLOAD'), findsOneWidget);
    final put = calls.indexOf('PUT /v1/me/community');
    expect(put, isNot(-1));
    expect((bodies[put]! as Map)['displayName'], 'Ahmed');
  });

  testWidgets('joining with an empty name asks for one and sends nothing', (tester) async {
    await TokenStore(secure).save(access: 'a1', refresh: 'r1');
    await open(tester, app(session: google));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(toggle(joinLabel));
    await tester.pumpAndSettle();
    await tester.tap(toggle(attestLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await settle(tester);

    expect(find.text('اكتب الاسم الظاهر.'), findsOneWidget);
    expect(calls.where((c) => c == 'PUT /v1/me/community'), isEmpty);
    expect(find.text('DOWNLOAD'), findsNothing);
  });

  testWidgets('signed in: the first name is prefilled; joining needs the attestation and is a direct PUT', (tester) async {
    await TokenStore(secure).save(access: 'a1', refresh: 'r1');
    handler = (req) async {
      if (req.method == 'PUT' && req.url.path == '/v1/me/community') {
        return json({'leagues': true, 'leaderboard': false, 'leaderboardCountry': false, 'banned': false, 'attestedAdult': true});
      }
      if (req.method == 'PATCH' && req.url.path == '/v1/me/profile') return json(<String, dynamic>{});
      return http.Response('', 503); // the background profile refresh keeps the cache
    };
    await open(tester, app(session: google));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Ahmed'); // never the full account name

    await tester.tap(toggle(joinLabel));
    await tester.pumpAndSettle();
    expect(toggled(tester, joinLabel), isTrue);
    expect(toggle(attestLabel), findsOneWidget);

    // Without the attestation nothing is sent.
    await tester.tap(find.text('متابعة'));
    await settle(tester);
    expect(find.text('أكّد عمرك للانضمام.'), findsOneWidget);
    expect(calls.where((c) => c == 'PUT /v1/me/community'), isEmpty);
    expect(find.text('DOWNLOAD'), findsNothing);

    await tester.tap(toggle(attestLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await settle(tester);

    expect(find.text('DOWNLOAD'), findsOneWidget);
    final put = calls.indexOf('PUT /v1/me/community');
    expect(put, isNot(-1));
    expect(bodies[put], {'leagues': true, 'displayName': 'Ahmed', 'attestAdult': true, 'source': 'onboarding'});
    // The join went straight out: nothing for it waits in the Outbox.
    expect((await Outbox(kv).items()).where((i) => i.path == '/v1/me/community'), isEmpty);
    expect(kv.data['consents.v1'], contains('"community":true'));
  });

  testWidgets("the preview is where everyone starts, never a returning account's live level", (tester) async {
    await TokenStore(secure).save(access: 'a1', refresh: 'r1');
    await kv.write(ProfileRepository.meKey, File('test/fixtures/community/me_profile.json').readAsStringSync()); // level 3
    await open(tester, app(session: google));

    final preview = tester.widget<YqLevelAvatar>(find.byType(YqLevelAvatar));
    expect(preview.level, 1);
    expect(preview.progress, 0);
    expect(preview.achieved, isFalse);
    expect(preview.levelName, 'بداية الطريق');
    expect(find.text('بداية الطريق'), findsOneWidget);
    expect(find.text('مواظب'), findsNothing);
  });

  testWidgets('offline join: says a connection is needed, turns the switch off, and lets the person continue', (tester) async {
    await TokenStore(secure).save(access: 'a1', refresh: 'r1');
    handler = (_) async => throw http.ClientException('offline');
    await open(tester, app(session: google));
    await tester.tap(toggle(joinLabel));
    await tester.pumpAndSettle();
    await tester.tap(toggle(attestLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة'));
    await settle(tester);

    expect(find.text('تحتاج اتصالاً للانضمام'), findsOneWidget);
    expect(toggled(tester, joinLabel), isFalse);
    expect(find.text('DOWNLOAD'), findsNothing);

    await tester.tap(find.text('متابعة'));
    await settle(tester);
    expect(find.text('DOWNLOAD'), findsOneWidget);
  });

  testWidgets('skip keeps the defaults and resumes at download', (tester) async {
    await open(tester, app());
    await tester.tap(find.text('تخطٍّ'));
    await settle(tester);
    expect(find.text('DOWNLOAD'), findsOneWidget);
    expect(kv.data['settings.v1'], contains('"onboardingRoute":"/onboarding/download"'));
    expect(kv.data['settings.v1'], contains('"onboardingStep":7'));
    expect(kv.data[ProfileRepository.meKey], isNull);
  });

  testWidgets('back (chevron and system back) returns to the routine step', (tester) async {
    await open(tester, app());
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTINE'), findsOneWidget);
    expect(kv.data['settings.v1'], contains('"onboardingRoute":"/onboarding/routine"'));

    await tester.pumpWidget(const SizedBox());
    await open(tester, app());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ROUTINE'), findsOneWidget);
  });

  testWidgets('«من صورك» shows only when a photo picker is available', (tester) async {
    await open(tester, app());
    expect(find.bySemanticsLabel('من صورك'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, app(picker: _AvailablePicker()));
    expect(find.bySemanticsLabel('من صورك'), findsOneWidget);
  });

  testWidgets('league flag off: no switch and no weekly line', (tester) async {
    await open(tester, app(config: const RemoteConfig()));
    expect(toggle(joinLabel), findsNothing);
    expect(find.text('دوري أسبوعي في مجموعات من نحو 30: الأعلى يصعد قسماً.'), findsNothing);
    expect(find.text('بطولات موسمية مثل رمضان وذي الحجة، وجوائزها شارات.'), findsOneWidget);
  });

  // Regenerated on Linux only (.github/workflows/goldens.yml), never on Windows/macOS.
  for (final locale in ['ar', 'en']) {
    testWidgets('onboarding profile golden ($locale)', (tester) async {
      debugDisableShadows = false;
      try {
        tester.view.physicalSize = const Size(390 * 3, 1900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(locale: locale, picker: _AvailablePicker()));
        await tester.pump();
        // Let the preset art decode (real time), then pick one and type a name.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(locale == 'ar' ? 'حجاب سماوي' : 'Sky hijab'));
        await tester.enterText(find.byType(TextField), locale == 'ar' ? 'سارة' : 'Sara');
        FocusManager.instance.primaryFocus?.unfocus(); // no caret in the picture
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pumpAndSettle();
        await expectLater(find.byType(Scaffold).first, matchesGoldenFile('../goldens/onboarding_profile_$locale.png'));
      } finally {
        debugDisableShadows = true;
      }
    });
  }

  group('motion (how it works)', () {
    String numeral(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('levels-demo-numeral'))).data!;
    Color dot(WidgetTester tester, int i) =>
        (tester.widget<AnimatedContainer>(find.byKey(ValueKey('levels-demo-dot-$i'))).decoration! as BoxDecoration).color!;

    testWidgets('the ring fills through the levels once, then rests on level 1; presets pop in; the league slides in', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(session: google));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // presets decoded (or the wait capped)
      expect(find.byType(PresetCascade), findsWidgets);
      expect(find.byType(LevelsDemo), findsOneWidget);
      // Mid-fill the numeral has climbed past the first level.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 900));
      expect(int.parse(numeral(tester)), greaterThan(1));
      await tester.pumpAndSettle(); // it plays once and stops
      expect(numeral(tester), '1');
      expect(dot(tester, 0), YqColors.lapis);
      expect(dot(tester, 5), YqColors.line);
      expect(find.byType(MiniLeagueCard), findsOneWidget);

      // Switching the league on lights the person's own row with one sheen; the row is the same
      // element, so its tint and «أنت» ease in rather than snap.
      const sheen = ValueKey('mini-league-sheen');
      expect(tester.widget<YqSheen>(find.byKey(sheen)).play, isFalse);
      final row = tester.element(find.descendant(of: find.byKey(sheen), matching: find.byType(AnimatedContainer)).first);
      await tester.tap(toggle(joinLabel));
      await tester.pump();
      expect(tester.widget<YqSheen>(find.byKey(sheen)).play, isTrue);
      expect(tester.element(find.descendant(of: find.byKey(sheen), matching: find.byType(AnimatedContainer)).first), same(row));
      await tester.pump(const Duration(milliseconds: 100));
      final you = tester.widget<FadeTransition>(
        find.descendant(
          of: find.descendant(of: find.byKey(sheen), matching: find.byType(AnimatedOpacity)),
          matching: find.byType(FadeTransition),
        ).first,
      );
      expect(you.opacity.value, inExclusiveRange(0.45, 1.0)); // «أنت» on its way, not snapped
      await tester.pumpAndSettle();
    });

    testWidgets('reduce-motion: every illustration at rest from the first frame, and it settles', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester, app(session: google));
      expect(numeral(tester), '1');
      expect(dot(tester, 0), YqColors.lapis);
      expect(find.byType(MiniLeagueCard), findsOneWidget);
      final card = tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('mini-league-sheen')), matching: find.byType(Opacity)).first);
      expect(card.opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
