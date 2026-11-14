import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/design/motion.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/network/connectivity.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/platform/photo_picker.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/tokens.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/core/widgets/yq_count.dart';
import 'package:yaqeen/core/widgets/yq_avatar.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';
import 'package:yaqeen/core/widgets/yq_layout.dart';
import 'package:yaqeen/core/widgets/yq_orb.dart';
import 'package:yaqeen/core/widgets/yq_button.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/card/presentation/journey_widgets.dart';
import 'package:yaqeen/features/challenge/domain/challenge_models.dart';
import 'package:yaqeen/features/challenge/presentation/challenge_controller.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/domain/level.dart';
import 'package:yaqeen/features/profile/domain/me_profile.dart';
import 'package:yaqeen/features/profile/presentation/badges_screen.dart';
import 'package:yaqeen/features/profile/presentation/badges_strip.dart';
import 'package:yaqeen/features/profile/presentation/edit_name_sheet.dart';
import 'package:yaqeen/features/profile/presentation/level_ladder_sheet.dart';
import 'package:yaqeen/features/profile/presentation/me_profile_controller.dart';
import 'package:yaqeen/features/profile/presentation/name_revert_toaster.dart';
import 'package:yaqeen/features/profile/presentation/profile_screen.dart';
import 'package:yaqeen/features/profile/presentation/profile_settings_screen.dart';

import 'package:yaqeen/l10n/gen/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

Map<String, dynamic> fixture(String name) =>
    (jsonDecode(File('test/fixtures/community/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> summary({int balance = 820}) => {
      'enrolled': true,
      'startedOn': '2026-09-04',
      'dayNumber': 47,
      'streak': 3,
      'balance': balance,
      'challengeLengthDays': 365,
      'today': {'date': '2026-10-20', 'dayNumber': 47, 'status': 'today', 'points': 0, 'completedTasks': <String>[], 'bonuses': <String>[]},
      'tasks': <Object>[],
    };

/// The challenge summary without the controller's network, timers and cache.
class _Challenge extends ChallengeController {
  _Challenge(this.value);
  final Future<ChallengeSummary> value;
  @override
  Future<ChallengeSummary> build() => value;
}

/// The first summary fails (offline, nothing cached); a retry gets it.
class _FlakyChallenge extends ChallengeController {
  static var builds = 0;
  @override
  Future<ChallengeSummary> build() async {
    builds++;
    if (builds == 1) throw const OfflineException();
    return ChallengeSummary.fromJson(summary());
  }
}

/// The first build fails outright (no value to show); a retry gets the profile.
class _FailingProfile extends MeProfileController {
  static var builds = 0;
  @override
  Future<MeProfile> build() async {
    builds++;
    if (builds == 1) throw const OfflineException();
    return MeProfile.fromJson(fixture('me_profile'));
  }
}

/// A profile that never arrives (a cold start without cache).
class _PendingProfile extends MeProfileController {
  @override
  Future<MeProfile> build() => Completer<MeProfile>().future;
}

class _Picker implements PhotoPicker {
  @override
  bool get available => true;
  @override
  Future<PickedPhoto?> pick(PhotoSource source) async => PickedPhoto(bytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]));
}

class _Offline implements ConnectivityMonitor {
  @override
  Future<bool> isOnline() async => false;
  @override
  Future<bool> isUnmetered() async => false;
  @override
  Stream<bool> get changes => const Stream.empty();
}

/// Gold tokens (ignoring alpha): achievement styling.
const _gold = [YqColors.gold, YqColors.goldText, YqColors.goldDeep, YqColors.goldLight, YqColors.gold300, YqColors.cream, YqColors.sand];
bool _isGold(Color? c) => c != null && _gold.any((g) => (g.toARGB32() & 0xFFFFFF) == (c.toARGB32() & 0xFFFFFF));

bool _goldWidget(Widget w) {
  if (w is Text) return _isGold(w.style?.color);
  if (w is YqOrb) return w.glow || _isGold(w.statusColor);
  if (w is LiquidGlass) return w.tone == GlassTone.gold;
  if (w is YqGroup) return w.gold;
  if (w is YqIconTile) return w.gold;
  if (w is YqIcon) return w.tone == YqIconTone.gold;
  if (w is Container && w.decoration is BoxDecoration) {
    final d = w.decoration! as BoxDecoration;
    return _isGold(d.color) || _isGold(d.border?.top.color) || (d.gradient?.colors.any(_isGold) ?? false);
  }
  return false;
}

void main() {
  late Directory files;
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
    files = Directory.systemTemp.createTempSync('yq-profile');
  });
  tearDownAll(() {
    try {
      files.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  void size(WidgetTester tester, [double h = 2400]) {
    tester.view.physicalSize = Size(390 * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester, [int rounds = 4]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /* ------------------------------------------------------------------ rigs */

  const guest = Session(provider: SignInProvider.guest, pendingServer: true);
  const account = Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد');

  late List<http.Request> requests;
  late MemoryKvStore kv;

  /// A signed-in rig: [profile] is both the cache and what the server answers.
  Future<List<Override>> signedIn({
    Map<String, dynamic>? profile,
    bool cache = true,
    Future<http.Response?> Function(http.Request)? handler,
    RemoteConfig? config,
    Future<ChallengeSummary>? challenge,
    ChallengeController Function()? challengeController,
    PhotoPicker? picker,
    ConnectivityMonitor? connectivity,
    Session session = account,
  }) async {
    requests = [];
    final me = profile ?? fixture('me_profile');
    if (cache) await kv.write(ProfileRepository.meKey, jsonEncode(me));
    final secure = MemoryKvStore();
    await secure.write('auth.access', 'token');
    return [
      initialSessionProvider.overrideWithValue(session),
      tokenStoreProvider.overrideWithValue(TokenStore(secure)),
      filesDirProvider.overrideWithValue(() async => files),
      apiClientProvider.overrideWith(
        (ref) => ApiClient(
          baseUrl: 'https://api.test',
          tokens: ref.watch(tokenStoreProvider),
          client: MockClient((req) async {
            requests.add(req);
            if (connectivity is _Offline) throw http.ClientException('offline');
            final custom = await handler?.call(req);
            if (custom != null) return custom;
            final p = req.url.path;
            if (p == '/v1/me/profile' && req.method == 'GET') return json(me);
            if (p == '/v1/me/journey') {
              return json({
                'lifetimePoints': 3200,
                'level': me['level'],
                'events': [
                  {'kind': 'challenge_day', 'date': '2026-09-30', 'value': 30},
                  {'kind': 'joined', 'date': '2026-08-31', 'value': null},
                ],
              });
            }
            if (p == '/v1/me/public-profile') {
              return json({'published': false, 'handle': 'ahmed', 'displayName': 'أحمد', 'url': 'https://id.test/u/ahmed', 'views': 0});
            }
            return json(
              {
                'error': {'code': 'not_found'},
              },
              404,
            );
          }),
        ),
      ),
      challengeControllerProvider
          .overrideWith(challengeController ?? () => _Challenge(challenge ?? Future.value(ChallengeSummary.fromJson(summary())))),
      downloadsBytesProvider.overrideWith((ref) async => 0),
      if (config != null) initialConfigProvider.overrideWithValue(config),
      if (picker != null) photoPickerProvider.overrideWithValue(picker),
      if (connectivity != null) connectivityProvider.overrideWithValue(connectivity),
    ];
  }

  setUp(() => kv = MemoryKvStore());

  RemoteConfig flags(Map<String, bool> on) => RemoteConfig(features: {...RemoteConfig.defaultFeatures, ...on});

  Future<void> pumpProfile(WidgetTester tester, List<Override> overrides, {String locale = 'ar'}) async {
    // NameRevertToaster stands in for the app shell, which announces refused names on every tab.
    await tester.pumpWidget(
      harness(const NameRevertToaster(child: Scaffold(body: ProfileScreen())), overrides: overrides, kv: kv, locale: locale),
    );
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3)); // toasts and one-shot timers
  }

  /* ----------------------------------------------------------------- guest */

  testWidgets('guest: ring at 0, the sign-in note and ink pill, no account rows on the tab', (tester) async {
    size(tester);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        kv: kv,
        overrides: [
          initialSessionProvider.overrideWithValue(guest),
          downloadsBytesProvider.overrideWith((ref) async => 0),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ضيف'), findsOneWidget);
    expect(find.text('المستوى 1 · بداية الطريق'), findsOneWidget);
    expect(find.text('مستواك ورحلتك يُحفظان حين تسجّل الدخول'), findsOneWidget);
    expect(find.text('سجّل الدخول لحفظ نقاطك'), findsOneWidget);
    // Orbs: Level · Language (no rewards for guests) · Downloads (leagues off).
    expect(find.text('المستوى'), findsOneWidget);
    expect(find.text('500 للمستوى التالي'), findsOneWidget);
    expect(find.text('لغة التطبيق'), findsOneWidget);
    expect(find.text('الرصيد'), findsNothing);
    expect(find.text('التنزيلات دون اتصال'), findsOneWidget);
    // Settings moved to /profile/settings; guests have no badges, journey or rewards here.
    expect(find.text('حذف الحساب'), findsNothing);
    expect(find.text('الخصوصية والموافقات'), findsNothing);
    expect(find.text('الشارات'), findsNothing);
    expect(find.byTooltip('الإعدادات'), findsOneWidget);
    expect(find.text('بطاقة يقين'), findsOneWidget);
  });

  /* ------------------------------------------------------------- signed in */

  testWidgets('signed in: avatar in the level ring, caption with handle, Level · Points · League orbs', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(config: flags({Flags.leagues: true})));
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('تغيير الصورة')), findsOneWidget);
    // Level orb: 5000 − 3200 to the next level.
    expect(find.text('1,800 للمستوى التالي'), findsOneWidget);
    // Points orb: the balance; a tap flips to this week (self only).
    expect(find.text('الرصيد'), findsOneWidget);
    expect(find.text('820 نقطة'), findsOneWidget);
    await tester.tap(find.text('الرصيد'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('هذا الأسبوع'), findsOneWidget);
    expect(find.text('145 نقطة'), findsOneWidget);
    // League orb: division and snapshot rank.
    expect(find.text('ذهب'), findsOneWidget);
    expect(find.text('4 من 30'), findsOneWidget);
    // Competition group per flag; the visibility row for accounts.
    expect(find.text('المنافسة'), findsOneWidget);
    expect(find.text('الدوري الأسبوعي'), findsOneWidget);
    expect(find.text('البطولات'), findsNothing);
    expect(find.text('الظهور في المنافسات'), findsOneWidget);
    // Rewards group and the card row.
    expect(find.text('سجل النقاط'), findsOneWidget);
    expect(find.text('غير منشورة'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('loading: shaped skeletons, and the orb set never swaps while data arrives', (tester) async {
    size(tester);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        kv: kv,
        overrides: [...await signedIn(cache: false), meProfileProvider.overrideWith(_PendingProfile.new)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('profile-stage-skeleton')), findsOneWidget);
    expect(find.byType(YqSkeletonOrbs), findsOneWidget);
    expect(find.byType(YqOrb), findsNothing);
    await dispose(tester);

    // The profile is cached but the balance is still on its way: the Points orb holds its place.
    final challenge = Completer<ChallengeSummary>();
    await tester.pumpWidget(
      harness(const Scaffold(body: ProfileScreen()), kv: kv, overrides: await signedIn(challenge: challenge.future)),
    );
    await settle(tester, 2);
    expect(find.text('الرصيد'), findsOneWidget);
    expect(find.byKey(const ValueKey('points-loading')), findsOneWidget);
    expect(find.text('لغة التطبيق'), findsNothing);
    final titles = [for (final o in tester.widgetList<YqOrb>(find.byType(YqOrb))) o.title];
    challenge.complete(ChallengeSummary.fromJson(summary()));
    await settle(tester, 2);
    expect([for (final o in tester.widgetList<YqOrb>(find.byType(YqOrb))) o.title], titles);
    expect(find.text('820 نقطة'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('offline: the cached profile with the offline banner', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(connectivity: _Offline()));
    expect(find.text('أنت غير متصل · نعمل بما على جهازك'), findsOneWidget);
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('reduce-motion: the end state at once (ring, numbers, flip) and everything settles', (tester) async {
    size(tester);
    await kv.write(ProfileRepository.lastSeenLevelKey, '2'); // a level-up is owed too
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const NameRevertToaster(child: Scaffold(body: ProfileScreen())),
          ),
        ),
        overrides: await signedIn(config: flags({Flags.leagues: true})),
        kv: kv,
      ),
    );
    await settle(tester);
    // The toast comes at once (no light to wait for); numbers are plain text, not rolling.
    expect(find.text('بلغت مستوى مواظب'), findsOneWidget);
    expect(find.text('1,800 للمستوى التالي'), findsOneWidget);
    expect(find.text('820'), findsOneWidget);
    expect(find.byType(YqRollingNumber), findsWidgets);
    expect(find.byType(Transform).evaluate().where((e) => e.widget is Transform && (e.widget as Transform).transform.storage[11] != 0), isEmpty);
    await tester.tap(find.text('الرصيد'));
    await tester.pump();
    expect(find.text('هذا الأسبوع'), findsOneWidget); // flipped without turning
    expect(find.text('145'), findsOneWidget);
    await tester.pumpAndSettle(); // no ticker left running
    await dispose(tester);
  });

  testWidgets('level-up: the glint and «بلغت مستوى…» play once, then the level is marked seen', (tester) async {
    size(tester);
    await kv.write(ProfileRepository.lastSeenLevelKey, '2');
    await pumpProfile(tester, await signedIn());
    // The light sweeps round the ring first; the quiet toast follows it.
    expect(tester.widget<YqLevelAvatar>(find.byKey(const ValueKey('profile-avatar'))).achieved, isTrue);
    await tester.pump(Motion.glint);
    expect(find.text('بلغت مستوى مواظب'), findsOneWidget);
    expect(await kv.read(ProfileRepository.lastSeenLevelKey), '3');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('بلغت مستوى مواظب'), findsNothing);
    await settle(tester);
    expect(find.text('بلغت مستوى مواظب'), findsNothing);
    await dispose(tester);
  });

  testWidgets('gold appears only in the badges strip', (tester) async {
    size(tester, 3000);
    await pumpProfile(tester, await signedIn(config: flags({Flags.leagues: true, Flags.tournaments: true, Flags.leaderboard: true})));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(BadgesStrip), findsOneWidget);
    expect(find.byType(BadgeMedal), findsNWidgets(3));
    bool inside(Element e, Type t) {
      var found = false;
      e.visitAncestorElements((a) => !(found = a.widget.runtimeType == t));
      return found;
    }

    final gold = find.byWidgetPredicate(_goldWidget).evaluate().toList();
    final inStrip = gold.where((e) => inside(e, BadgesStrip)).toList();
    // Level-reached rail dots are achievement too; the journey has none here.
    final elsewhere = gold.where((e) => !inside(e, BadgesStrip) && !inside(e, JourneyRail)).map((e) => e.widget).toList();
    expect(inStrip, isNotEmpty);
    expect(elsewhere, isEmpty);
    await dispose(tester);
  });

  testWidgets('360 pt at 1.3× text: the stage, orbs and body lay out without overflow', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpProfile(tester, await signedIn(config: flags({Flags.leagues: true, Flags.tournaments: true, Flags.leaderboard: true})));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    // Every tappable on the stage keeps a 44-pt target.
    for (final f in [find.bySemanticsLabel(RegExp('تغيير الصورة')), find.bySemanticsLabel('أحمد، اسمك'), find.byTooltip('الإعدادات')]) {
      final s = tester.getSize(f.first);
      expect(s.height, greaterThanOrEqualTo(44));
    }
    await dispose(tester);
  });

  // The rebuilt tab, as reviewed. Goldens are generated on Linux only (.github/workflows/goldens.yml).
  for (final locale in ['ar', 'en']) {
    testWidgets('profile golden ($locale)', (tester) async {
      size(tester, 2000);
      await pumpProfile(tester, await signedIn(config: flags({Flags.leagues: true})), locale: locale);
      await tester.pump(const Duration(seconds: 3));
      await expectLater(find.byType(Scaffold).first, matchesGoldenFile('../goldens/profile_$locale.png'));
      await dispose(tester);
    });
  }

  /* ---------------------------------------------------------------- avatar */

  testWidgets('avatar sheet: a preset is saved on the phone at once and its PATCH queued', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(handler: (req) async => req.method == 'PATCH' ? json({'error': {}}, 503) : null));
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    expect(find.text('صورتك'), findsOneWidget);
    expect(find.bySemanticsLabel('عمامة، محدّدة'), findsOneWidget); // m03, the current preset
    await tester.tap(find.text('نساء'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('عمامة، محدّدة'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel('حجاب كحلي'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    final saved = jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map;
    expect(saved['avatar'], {'kind': 'preset', 'id': 'f01'});
    final queued = (await Outbox(kv).items()).where((i) => i.method == 'PATCH' && i.path == '/v1/me/profile').toList();
    final sent = requests.where((r) => r.method == 'PATCH' && r.url.path == '/v1/me/profile').toList();
    expect(
      [for (final q in queued) q.body?['avatar'], for (final r in sent) (jsonDecode(r.body) as Map)['avatar']],
      anyElement(equals({'kind': 'preset', 'id': 'f01'})),
    );
    expect(find.text('صورتك'), findsNothing); // the sheet closed
    await dispose(tester);
  });

  testWidgets('avatar sheet: remove photo returns to the initial (DELETE sent)', (tester) async {
    size(tester);
    final photo = fixture('me_profile_photo');
    await pumpProfile(
      tester,
      await signedIn(profile: photo, handler: (req) async => req.method == 'DELETE' ? json({'kind': 'initial'}) : null),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    // Sara is not visible anywhere: no attestation needed.
    expect(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('إزالة الصورة'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(requests.where((r) => r.method == 'DELETE' && r.url.path == '/v1/me/avatar/photo'), hasLength(1));
    final saved = jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map;
    expect((saved['avatar'] as Map)['kind'], 'initial');
    expect(find.text('إزالة الصورة'), findsNothing);
    await dispose(tester);
  });

  testWidgets('avatar sheet: the age switch shows only when a visible photo is unattested, and calls POST /v1/me/attestation',
      (tester) async {
    size(tester);
    final photo = fixture('me_profile_photo');
    final visible = {
      ...photo,
      'community': {...(photo['community'] as Map), 'leagues': true},
    };
    await pumpProfile(
      tester,
      await signedIn(
        profile: visible,
        handler: (req) async =>
            req.url.path == '/v1/me/attestation' ? json({...(visible['community'] as Map), 'attestedAdult': true}) : null,
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    expect(find.text('يرى الآخرون صورة من المجموعة حتى تؤكد عمرك.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('avatar-attest')), matching: find.byType(YqSwitch)));
    await settle(tester);
    expect(requests.where((r) => r.method == 'POST' && r.url.path == '/v1/me/attestation'), hasLength(1));
    expect(find.byKey(const ValueKey('avatar-attest')), findsNothing); // attested: nothing more to ask
    await dispose(tester);

    // A preset is never shown as a photo: no switch.
    kv = MemoryKvStore();
    await pumpProfile(tester, await signedIn(profile: {...fixture('me_profile'), 'community': visible['community']}));
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('avatar-attest')), findsNothing);
    await dispose(tester);
  });

  testWidgets('avatar sheet: a photo hidden by support explains itself and disables photo actions', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(profile: {...fixture('me_profile'), 'photoHidden': true}, picker: _Picker()));
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    expect(find.text('أخفى فريق الدعم صورتك. اختر صورة من المجموعة.'), findsOneWidget);
    await tester.tap(find.text('من الألبوم'));
    await settle(tester, 2);
    expect(find.text('صورتك'), findsOneWidget); // still open: the action is disabled
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    await dispose(tester);
  });

  testWidgets('avatar sheet: too many uploads → «رفعت صوراً كثيرة…», previous picture kept', (tester) async {
    size(tester);
    await pumpProfile(
      tester,
      await signedIn(
        picker: _Picker(),
        handler: (req) async => req.method == 'PUT' && req.url.path == '/v1/me/avatar/photo'
            ? json(
                {
                  'error': {'code': 'rate_limited'},
                },
                429,
              )
            : null,
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    await tester.tap(find.text('من الألبوم'));
    // The photo is written to this phone, then uploaded: real file IO, so let it run.
    bool put() => requests.any((r) => r.method == 'PUT');
    for (var i = 0; i < 60 && !put(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requests.where((r) => r.method == 'PUT' && r.url.path == '/v1/me/avatar/photo'), hasLength(1));
    expect(find.text('رفعت صوراً كثيرة. حاول بعد ساعة.'), findsOneWidget);
    final saved = jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map;
    expect(saved['avatar'], {'kind': 'preset', 'id': 'm03'});
    await dispose(tester);
  });

  /* ------------------------------------------------------------------ name */

  test('display names mirror contracts DisplayName', () {
    expect(isValidDisplayName('أحمد'), isTrue);
    expect(isValidDisplayName('  Sara  '), isTrue);
    expect(isValidDisplayName(''), isFalse);
    expect(isValidDisplayName('   '), isFalse);
    expect(isValidDisplayName('a' * 41), isFalse);
    expect(isValidDisplayName('see www.spam.test'), isFalse);
    expect(isValidDisplayName('https://x.test'), isFalse);
    expect(isValidDisplayName('Ah\u202Emed'), isFalse);
    expect(isValidDisplayName('Ah\u200Bmed'), isFalse);
  });

  testWidgets('name sheet: invalid names are refused, a valid one is saved locally', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn());
    await tester.tap(find.bySemanticsLabel('أحمد، اسمك'));
    await settle(tester, 2);
    expect(find.text('من 1 إلى 40 حرفاً'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'www.spam.test');
    await tester.pump();
    expect(find.text('اكتب اسماً من 1 إلى 40 حرفاً بلا روابط أو رموز.'), findsOneWidget);
    await tester.tap(find.text('حفظ'));
    await settle(tester, 2);
    expect((jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map)['displayName'], 'أحمد');
    await tester.enterText(find.byType(TextField), 'أحمد علي');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await settle(tester);
    expect((jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map)['displayName'], 'أحمد علي');
    expect(find.text('أحمد علي'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('name hidden by support: «عضو يقين» with a lock, and the sheet is locked', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(profile: {...fixture('me_profile'), 'nameHidden': true}));
    expect(find.text('عضو يقين'), findsOneWidget);
    await tester.tap(find.text('عضو يقين'));
    await settle(tester, 2);
    expect(find.text('أخفى فريق الدعم هذا الاسم. راسلنا لمراجعته.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await dispose(tester);
  });

  /* -------------------------------------------------------------- settings */

  testWidgets('settings: account, app, about and account actions live on /profile/settings', (tester) async {
    size(tester);
    await tester.pumpWidget(
      harness(
        const ProfileSettingsScreen(),
        kv: kv,
        overrides: await signedIn(config: flags({Flags.leaderboard: true})),
      ),
    );
    await settle(tester);
    for (final row in ['الإعدادات', 'اسمك', 'صورتك', 'الظهور في المنافسات', 'الخصوصية والموافقات', 'التنزيلات دون اتصال', 'عن يقين']) {
      expect(find.text(row), findsWidgets, reason: row);
    }
    expect(find.text('حذف الحساب'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    // Delete is an ink row: the error colour waits for the final confirm.
    expect(tester.widget<YqListRow>(find.widgetWithText(YqListRow, 'حذف الحساب')).titleColor, isNull);
    await dispose(tester);
  });

  testWidgets('settings: guests see no destructive rows; «عن يقين» opens the website in the app language', (tester) async {
    size(tester);
    final device = FakeDeviceServices();
    await tester.pumpWidget(
      harness(
        const ProfileSettingsScreen(),
        kv: kv,
        overrides: [
          initialSessionProvider.overrideWithValue(guest),
          deviceServicesProvider.overrideWithValue(device),
          downloadsBytesProvider.overrideWith((ref) async => 0),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الخصوصية والموافقات'), findsOneWidget);
    expect(find.text('حذف الحساب'), findsNothing);
    expect(find.text('الظهور في المنافسات'), findsNothing);
    await tester.tap(find.text('عن يقين'));
    await tester.pump();
    expect(device.opened.single.toString(), 'https://yaqeenarabia.com/?lang=ar');
  });

  /* ---------------------------------------------------------------- badges */

  testWidgets('badges screen: count, sections and earned medals only', (tester) async {
    size(tester, 2600);
    final badges = jsonDecode(File('test/fixtures/community/badges.json').readAsStringSync());
    await tester.pumpWidget(
      harness(
        const BadgesScreen(),
        kv: kv,
        overrides: await signedIn(handler: (req) async => req.url.path == '/v1/me/badges' ? json(badges) : null),
      ),
    );
    await settle(tester);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('شارة'), findsOneWidget);
    expect(find.text('الدوري'), findsOneWidget);
    expect(find.text('البطولات'), findsOneWidget);
    expect(find.text('المسيرة'), findsOneWidget);
    expect(find.byType(BadgeMedal), findsNWidgets(9));
    expect(find.text('بين الثلاثة الأوائل'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('badges screen: a failed load offers a retry', (tester) async {
    size(tester);
    await tester.pumpWidget(harness(const BadgesScreen(), kv: kv, overrides: await signedIn()));
    await settle(tester);
    expect(find.text('تعذّر تحميل الشارات.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    // The stage ends on «—», not an endless shimmer.
    expect(find.byType(YqSkeleton), findsNothing);
    expect(find.text('—'), findsOneWidget);
    await dispose(tester);
  });
  /* ---------------------------------------------------------- error states */

  testWidgets('cold start without a profile: the error state, and its retry brings the tab', (tester) async {
    size(tester);
    _FailingProfile.builds = 0;
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        kv: kv,
        overrides: [...await signedIn(), meProfileProvider.overrideWith(_FailingProfile.new)],
      ),
    );
    await settle(tester);
    expect(find.byType(YqErrorState), findsOneWidget);
    expect(find.byType(YqOrb), findsNothing);
    await tester.tap(find.text('إعادة المحاولة'));
    await settle(tester);
    expect(find.byType(YqErrorState), findsNothing);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('signed in with nothing cached: no level-1 placeholder; a failed fetch ends on the retry', (tester) async {
    size(tester);
    var down = true;
    await pumpProfile(
      tester,
      await signedIn(
        cache: false,
        handler: (req) async => down && req.url.path == '/v1/me/profile' ? json({'error': {}}, 503) : null,
      ),
    );
    await settle(tester);
    expect(find.text('المستوى 1 · بداية الطريق'), findsNothing);
    expect(find.byType(YqErrorState), findsOneWidget);
    down = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await settle(tester, 6);
    expect(find.byType(YqErrorState), findsNothing);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('pull-to-refresh that fails: a toast, and the cached profile stays', (tester) async {
    size(tester);
    await pumpProfile(
      tester,
      await signedIn(handler: (req) async => req.url.path == '/v1/me/profile' ? json({'error': {}}, 503) : null),
    );
    final gets = requests.where((r) => r.method == 'GET' && r.url.path == '/v1/me/profile').length;
    unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.where((r) => r.method == 'GET' && r.url.path == '/v1/me/profile').length, greaterThan(gets));
    expect(find.text('تعذّر التحميل. تحقق من الاتصال.'), findsOneWidget);
    expect(find.text('أحمد'), findsOneWidget);
    expect(find.text('المستوى 3 · مواظب · @ahmed-4821'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('points orb: a failed summary shows «—» and a tap retries (no endless shimmer)', (tester) async {
    size(tester);
    _FlakyChallenge.builds = 0;
    await pumpProfile(tester, await signedIn(challengeController: _FlakyChallenge.new));
    await tester.pump(const Duration(seconds: 1)); // the cross-fade from the first-load shimmer ends
    expect(find.byKey(const ValueKey('points-loading')), findsNothing);
    expect(find.byKey(const ValueKey('points-failed')), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    await tester.tap(find.text('الرصيد'));
    await settle(tester);
    expect(find.byKey(const ValueKey('points-failed')), findsNothing);
    expect(find.text('820 نقطة'), findsOneWidget);
    expect(find.text('الرصيد'), findsOneWidget); // the retry did not flip to this week
    await dispose(tester);
  });

  /* ------------------------------------------------------- badges and ladder */

  testWidgets('badges strip: nothing earned yet says so, without «الكل»', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(profile: {...fixture('me_profile'), 'recentBadges': <Object>[], 'badgesCount': 0}));
    expect(find.text('الشارات'), findsOneWidget);
    expect(find.text('تظهر شاراتك هنا حين تكسبها.'), findsOneWidget);
    expect(find.text('الكل'), findsNothing);
    expect(find.byType(BadgeMedal), findsNothing);
    await dispose(tester);
  });

  testWidgets('badges strip: «الكل» opens /profile/badges', (tester) async {
    final me = MeProfile.fromJson(fixture('me_profile'));
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(body: BadgesStrip(badges: me.recentBadges, count: me.badgesCount))),
        GoRoute(path: '/profile/badges', builder: (_, __) => const Scaffold(body: Text('all-badges'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kvStoreProvider.overrideWithValue(MemoryKvStore())],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BadgeMedal), findsNWidgets(3));
    await tester.tap(find.text('الكل'));
    await tester.pumpAndSettle();
    expect(find.text('all-badges'), findsOneWidget);
  });

  testWidgets('badges: a medal catches its light once on this phone, then never again', (tester) async {
    final me = MeProfile.fromJson(fixture('me_profile'));
    final store = MemoryKvStore();
    Future<void> show() async {
      await tester.pumpWidget(
        harness(Scaffold(body: BadgesStrip(badges: me.recentBadges, count: me.badgesCount)), kv: store),
      );
      await tester.pump();
      await tester.pump();
    }

    await show();
    final medals = tester.widgetList<BadgeMedal>(find.byType(BadgeMedal)).toList();
    expect(medals, hasLength(3));
    expect(medals.every((m) => m.sweep), isTrue);
    expect([for (final m in medals) m.sweepDelay], [Duration.zero, BadgeMedal.sweepStep, BadgeMedal.sweepStep * 2]);
    await tester.pumpAndSettle(); // one pass each, then rest
    expect(store.data[ProfileRepository.badgesSweptKey], isNotNull);
    expect(ProfileRepository.wipedKeys, contains(ProfileRepository.badgesSweptKey));

    await tester.pumpWidget(const SizedBox());
    await show();
    expect(tester.widgetList<BadgeMedal>(find.byType(BadgeMedal)).any((m) => m.sweep), isFalse);
  });

  testWidgets('badges: the strip then «الكل» in one run: the second list does not sweep the same medals again', (tester) async {
    final me = MeProfile.fromJson(fixture('me_profile'));
    final store = MemoryKvStore();
    // The same harness each time keeps one ProviderScope (one app run).
    Future<void> show(Key key) async {
      await tester.pumpWidget(
        harness(Scaffold(body: BadgesStrip(key: key, badges: me.recentBadges, count: me.badgesCount)), kv: store),
      );
      await tester.pump();
      await tester.pump();
    }

    await show(const ValueKey('profile-strip'));
    expect(tester.widgetList<BadgeMedal>(find.byType(BadgeMedal)).every((m) => m.sweep), isTrue);
    await tester.pumpAndSettle();
    await show(const ValueKey('another-list')); // a new list screen, same run
    expect(tester.widgetList<BadgeMedal>(find.byType(BadgeMedal)).any((m) => m.sweep), isFalse);
    expect(tester.widgetList<YqSheen>(find.byType(YqSheen)).any((s) => s.play), isFalse);
  });

  testWidgets('badges: a medal rebuilt in a lazy list (scrolled away and back) keeps its light spent', (tester) async {
    final me = MeProfile.fromJson(fixture('me_profile'));
    final memo = MotionMemo();
    final badge = me.recentBadges.first;
    Future<void> medal(Key key) async {
      await tester.pumpWidget(harness(YqMotionMemo(memo: memo, child: Center(child: BadgeMedal(key: key, badge: badge, sweep: true)))));
      await tester.pump();
    }

    await medal(const ValueKey('first-build'));
    expect(tester.widget<YqSheen>(find.byType(YqSheen)).play, isTrue);
    await tester.pumpAndSettle();
    await medal(const ValueKey('rebuilt')); // a new element, as a lazy list builds it again
    expect(tester.widget<YqSheen>(find.byType(YqSheen)).play, isFalse);
  });

  testWidgets('level ladder: six levels, the current one in lapis, gold dots on the reached, the note', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn());
    await tester.tap(find.text('المستوى'));
    await settle(tester, 2);
    final ladder = find.byType(LevelLadder);
    expect(ladder, findsOneWidget);
    for (final l in cardLevels) {
      expect(find.descendant(of: ladder, matching: find.text(l.$2)), findsOneWidget, reason: l.$2);
    }
    expect(find.descendant(of: ladder, matching: find.byKey(const ValueKey('ladder-reached'))), findsNWidgets(3));
    expect(tester.widget<Text>(find.descendant(of: ladder, matching: find.text('مواظب'))).style?.color, YqColors.lapis);
    expect(tester.widget<Text>(find.descendant(of: ladder, matching: find.text(cardLevels.last.$2))).style?.color, YqColors.ink);
    expect(find.text('المستوى يُحسب من كل النقاط التي كسبتها، ولا ينقص حين تستبدلها.'), findsOneWidget);
    await dispose(tester);
  });

  /* ------------------------------------------------- avatar and name, more */

  testWidgets('avatar sheet: a photo too large → «الصورة كبيرة جداً…», previous picture kept', (tester) async {
    size(tester);
    await pumpProfile(
      tester,
      await signedIn(
        picker: _Picker(),
        handler: (req) async => req.method == 'PUT' && req.url.path == '/v1/me/avatar/photo'
            ? json(
                {
                  'error': {'code': 'FST_ERR_CTP_BODY_TOO_LARGE'},
                },
                413,
              )
            : null,
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await settle(tester, 2);
    await tester.tap(find.text('من الألبوم'));
    bool put() => requests.any((r) => r.method == 'PUT');
    for (var i = 0; i < 60 && !put(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('الصورة كبيرة جداً. اختر صورة أصغر.'), findsOneWidget);
    final saved = jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map;
    expect(saved['avatar'], {'kind': 'preset', 'id': 'm03'});
    await dispose(tester);
  });

  testWidgets('avatar sheet: guests are told the picture stays on this phone', (tester) async {
    size(tester);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        kv: kv,
        overrides: [
          initialSessionProvider.overrideWithValue(guest),
          downloadsBytesProvider.overrideWith((ref) async => 0),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('تغيير الصورة')));
    await tester.pumpAndSettle();
    expect(find.text('تبقى صورتك على هذا الجهاز حتى تسجّل الدخول.'), findsOneWidget);
    expect(find.text('لا يرى صورتك غيرك إلا في بطاقتك أو في المنافسات التي تنضم إليها.'), findsNothing);
    expect(find.byKey(const ValueKey('avatar-attest')), findsNothing);
  });

  testWidgets('name sheet: starts from the sign-in name the stage shows when the profile has none', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(profile: {...fixture('me_profile'), 'displayName': null}));
    expect(find.text('أحمد'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('أحمد، اسمك'));
    await settle(tester, 2);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'أحمد');
    expect(tester.widget<YqButton>(find.byType(YqButton)).onPressed, isNotNull);
    await dispose(tester);
  });

  testWidgets('name refused on replay (invalid_name): the server name comes back with a toast', (tester) async {
    size(tester);
    await pumpProfile(
      tester,
      await signedIn(
        handler: (req) async => req.method == 'PATCH' && req.url.path == '/v1/me/profile'
            ? json(
                {
                  'error': {'code': 'invalid_name'},
                },
                400,
              )
            : null,
      ),
    );
    await tester.tap(find.bySemanticsLabel('أحمد، اسمك'));
    await settle(tester, 2);
    await tester.enterText(find.byType(TextField), 'اسم مرفوض');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.where((r) => r.method == 'PATCH' && r.url.path == '/v1/me/profile'), hasLength(1));
    expect(find.text('لم يُقبل الاسم، فأعدناه كما كان.'), findsOneWidget);
    expect(find.text('اسم مرفوض'), findsNothing);
    expect(find.text('أحمد'), findsOneWidget);
    expect((jsonDecode((await kv.read(ProfileRepository.meKey))!) as Map)['displayName'], 'أحمد');
    expect(await Outbox(kv).items(), isEmpty);
    await dispose(tester);
  });

  testWidgets('English screen-reader labels join their parts without the Arabic comma', (tester) async {
    size(tester);
    await pumpProfile(tester, await signedIn(config: flags({Flags.leagues: true})), locale: 'en');
    expect(find.bySemanticsLabel('أحمد, Your name'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('،')), findsNothing);
    await dispose(tester);
  });
}
