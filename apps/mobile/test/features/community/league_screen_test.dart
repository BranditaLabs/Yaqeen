import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/community/data/community_repository.dart';
import 'package:yaqeen/features/community/domain/community_models.dart';
import 'package:yaqeen/features/community/presentation/community_providers.dart';
import 'package:yaqeen/features/community/presentation/community_widgets.dart';
import 'package:yaqeen/features/community/presentation/league_screen.dart';
import 'package:yaqeen/features/community/presentation/week_result_sheet.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/presentation/me_profile_controller.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'community_rig.dart';

Map<String, dynamic> profileJson({bool leagues = true, bool attested = true, bool banned = false, String name = 'أحمد'}) {
  final p = fixtureMap('me_profile.json');
  return {
    ...p,
    'displayName': name,
    'community': {
      ...(p['community'] as Map).cast<String, dynamic>(),
      'leagues': leagues,
      'attestedAdult': attested,
      'banned': banned,
    },
    if (!leagues) 'league': null,
  };
}

Map<String, dynamic> settingsAfterJoin() => {
      'leagues': true,
      'leaderboard': false,
      'leaderboardCountry': false,
      'banned': false,
      'attestedAdult': true,
      'country': 'EG',
    };

const history = [
  {'startsOn': '2026-11-07', 'division': 2, 'rank': 2, 'size': 28, 'points': 510, 'outcome': 'up'},
];

Future<void> pumpLeague(WidgetTester tester, CommunityRig rig, {String locale = 'ar'}) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(const LeagueScreen(), locale: locale, kv: rig.kv, overrides: rig.overrides));
  await tester.pumpAndSettle();
}

/// Seeds the cached profile (the week-result sheet and the banned state read it without waiting).
Future<void> seedProfile(CommunityRig rig, Map<String, dynamic> profile) =>
    rig.kv.write(ProfileRepository.meKey, jsonEncode(profile));

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  CommunityRig joinedRig({Map<String, dynamic>? profile}) => CommunityRig(routes: {
        'GET /v1/me/profile': (_) => jsonResponse(profile ?? profileJson()),
        'GET /v1/leagues/current': (_) => jsonResponse(leagueJoined()),
        'GET /v1/leagues/history': (_) => jsonResponse(history),
      },);

  testWidgets('joined: stage, zones, «أنت», «—» for null/0, snapshot line, sincerity and privacy', (tester) async {
    final rig = joinedRig();
    await seedProfile(rig, {...profileJson(), 'league': null}); // no week-result sheet here
    await pumpLeague(tester, rig);

    expect(find.text('الدوري الأسبوعي'), findsOneWidget);
    expect(find.text('ينتهي بعد 3 أيام'), findsOneWidget);
    expect(find.text('ذهب'), findsWidgets); // eyebrow (monochrome)
    expect(find.text('4'), findsWidgets); // my snapshot rank
    expect(find.text('335 نقطة هذا الأسبوع'), findsOneWidget); // live, self only
    expect(find.text('يصعدون إلى زمرّد'), findsOneWidget);
    // Five rows of a group of 30: nobody shown is placed past 25 (laila's 0 points share place 5),
    // so no one is shown moving down — the zone follows the rank, not the list length.
    expect(find.text('يبدأون الأسبوع القادم في فضة'), findsNothing);
    expect(find.text('أنت'), findsOneWidget);
    expect(find.text('عضو يقين'), findsOneWidget); // support-hidden name
    expect(find.text('—'), findsNWidgets(2)); // laila: rank null, 0 points
    expect(find.text('420'), findsNWidgets(2)); // the tie shows the same points…
    expect(find.text('1'), findsNWidgets(2)); // …and shares rank 1
    expect(find.text('يُحدَّث الترتيب كل ليلة.'), findsOneWidget);
    expect(find.text('الأسابيع السابقة'), findsOneWidget);
    expect(find.text('تنافسٌ لطيف على الخير. لا نقاط إضافية هنا، والشارات تذكارٌ فقط.'), findsOneWidget);
    expect(find.text('يرى المشاركون اسمك وصورتك ومستواك ونقاط الفترة فقط، لا صلواتك ولا أذكارك ولا مهامك.'), findsOneWidget);
    expect(find.text('شروط المنافسات'), findsOneWidget);
  });

  testWidgets('the terms link opens the website terms at #community', (tester) async {
    final rig = joinedRig();
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig);
    await tester.tap(find.text('شروط المنافسات'));
    await tester.pump();
    expect(rig.device.opened.single.toString(), 'https://yaqeenarabia.com/terms?lang=ar#community');
  });

  testWidgets('English: Western digits and the same layout', (tester) async {
    final rig = joinedRig();
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig, locale: 'en');
    expect(find.text('Weekly league'), findsOneWidget);
    expect(find.text('Ends in 3 days'), findsOneWidget);
    expect(find.text('335 points this week'), findsOneWidget);
    expect(find.text('Moving up to Emerald'), findsOneWidget);
    expect(find.text('Start next week in Silver'), findsNothing); // see the Arabic test
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining(RegExp('[٠-٩]')), findsNothing);
  });

  testWidgets('off → join sheet (first name, attestation) → direct PUT /v1/me/community, not the Outbox', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(leagues: false, attested: false, name: 'أحمد محمود')),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'GET /v1/leagues/history': (_) => jsonResponse(const []),
      'PUT /v1/me/community': (_) => jsonResponse(settingsAfterJoin()),
    },);
    await pumpLeague(tester, rig);
    expect(find.text('انضم إلى الدوري الأسبوعي'), findsOneWidget);

    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    // The sheet: first name only, attestation required before «انضم».
    expect(find.text('الاسم الظاهر'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'أحمد'), findsOneWidget);
    expect(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'), findsOneWidget);
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(rig.calls.where((c) => c.startsWith('PUT')), isEmpty); // disabled until attested

    await tester.tap(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'));
    await tester.pump();
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(rig.calls, contains('PUT /v1/me/community'));
    expect(rig.bodies['PUT /v1/me/community'], {'leagues': true, 'displayName': 'أحمد', 'attestAdult': true, 'source': 'settings'});
    expect(await rig.queued(), isEmpty);
  });

  testWidgets('offline join: «تحتاج اتصالاً للانضمام» inline, nothing queued', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(leagues: false)),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'PUT /v1/me/community': (_) => offline(),
    },);
    await pumpLeague(tester, rig);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    // Already attested: no switch, «انضم» enabled at once.
    expect(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'), findsNothing);
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(find.text('تحتاج اتصالاً للانضمام'), findsOneWidget);
    expect(await rig.queued(), isEmpty);
  });

  testWidgets('a typed join failure shows inline (name locked)', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(leagues: false)),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'PUT /v1/me/community': (_) => errorResponse(409, 'name_locked'),
    },);
    await pumpLeague(tester, rig);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(find.text('أخفى فريق الدعم هذا الاسم. راسلنا لمراجعته.'), findsOneWidget);
  });

  testWidgets('a name hidden by support: «عضو يقين» read-only, and the join sends no name', (tester) async {
    final hidden = {...profileJson(leagues: false, attested: false, name: 'أحمد محمود'), 'nameHidden': true};
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(hidden),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'GET /v1/leagues/history': (_) => jsonResponse(const []),
      'PUT /v1/me/community': (req) =>
          jsonDecode(req.body) is Map && (jsonDecode(req.body) as Map).containsKey('displayName')
              ? errorResponse(409, 'name_locked')
              : jsonResponse(settingsAfterJoin()),
    },);
    await seedProfile(rig, hidden);
    await pumpLeague(tester, rig);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('عضو يقين'), findsOneWidget);
    await tester.tap(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'));
    await tester.pump();
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(rig.bodies['PUT /v1/me/community'], {'leagues': true, 'attestAdult': true, 'source': 'settings'});
    expect(find.text('أخفى فريق الدعم هذا الاسم. راسلنا لمراجعته.'), findsNothing);
    expect(find.text('عضو يقين'), findsNothing); // the sheet closed
  });

  testWidgets('the shown name unchanged: the join does not resend it', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(leagues: false)),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'GET /v1/leagues/history': (_) => jsonResponse(const []),
      'PUT /v1/me/community': (_) => jsonResponse(settingsAfterJoin()),
    },);
    await pumpLeague(tester, rig);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(rig.bodies['PUT /v1/me/community'], {'leagues': true, 'source': 'settings'});
  });

  testWidgets('leave: confirm → queued PUT {leagues:false} and the league is gone at once', (tester) async {
    final rig = joinedRig();
    await seedProfile(rig, {...profileJson(), 'league': null});
    rig.routes['PUT /v1/me/community'] = (_) => offline();
    await pumpLeague(tester, rig);
    await tester.tap(find.text('مغادرة الدوري'));
    await tester.pumpAndSettle();
    expect(find.text('ستختفي من ترتيب هذا الأسبوع فوراً، ويمكنك العودة متى شئت.'), findsOneWidget);
    await tester.tap(find.text('غادر'));
    await tester.pumpAndSettle();

    final q = await rig.queued();
    expect(q.single.method, 'PUT');
    expect(q.single.path, '/v1/me/community');
    expect(q.single.body, containsPair('leagues', false));
    // The server still answers «joined» (the leave has not reached it): hidden here anyway.
    expect(find.text('أنت'), findsNothing);
    expect(find.text('انضم إلى الدوري الأسبوعي'), findsOneWidget);
  });

  testWidgets('guest: «سجّل الدخول لتنضم إلى المنافسات» → the sign-in sheet; no network', (tester) async {
    final rig = CommunityRig(signedIn: false);
    await pumpLeague(tester, rig);
    expect(find.text('سجّل الدخول لتنضم إلى المنافسات'), findsOneWidget);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    expect(find.text('المتابعة باستخدام Google'), findsOneWidget);
    expect(rig.calls.where((c) => c.contains('/v1/leagues') || c.contains('/v1/me/')), isEmpty);
  });

  testWidgets('closing: «نحسب نتائج الأسبوع… عُد بعد قليل»', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson()),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_closing.json')),
    },);
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig);
    expect(find.text('نحسب نتائج الأسبوع… عُد بعد قليل'), findsOneWidget);
  });

  testWidgets('banned: «أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.»', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(banned: true)),
      'GET /v1/leagues/current': (_) => jsonResponse(leagueJoined()),
    },);
    await seedProfile(rig, profileJson(banned: true));
    await pumpLeague(tester, rig);
    expect(find.text('أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.'), findsOneWidget);
    // No standings (the week-result sheet's podium may still say «أنت» for last week).
    expect(find.byType(CompetitorRow), findsNothing);
  });

  testWidgets('offline: the cached league with the offline banner', (tester) async {
    final rig = CommunityRig(routes: {'GET /v1/leagues/current': (_) => offline(), 'GET /v1/me/profile': (_) => offline()});
    await seedProfile(rig, {...profileJson(), 'league': null});
    await rig.kv.write(CommunityRepository.leagueKey, jsonEncode(leagueJoined()));
    await pumpLeague(tester, rig);
    expect(find.text('أنت غير متصل · نعمل بما على جهازك'), findsOneWidget);
    expect(find.text('أنت'), findsOneWidget);
    expect(find.text('يُحدَّث الترتيب كل ليلة.'), findsOneWidget);
  });

  testWidgets('offline with nothing cached: the error state with retry', (tester) async {
    final rig = CommunityRig(routes: {'GET /v1/leagues/current': (_) => offline(), 'GET /v1/me/profile': (_) => offline()});
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('flag off (deep link): the empty state, no network', (tester) async {
    final rig = CommunityRig(flags: {'leagues': false});
    await seedProfile(rig, profileJson());
    await pumpLeague(tester, rig);
    expect(find.text('هذه المنافسة غير متاحة الآن.'), findsOneWidget);
    expect(rig.calls.where((c) => c.contains('leagues')), isEmpty);
  });

  testWidgets('long-press another row → the report sheet; never on my own row', (tester) async {
    final rig = joinedRig();
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig);
    await tester.longPress(find.text('أحمد'));
    await tester.pumpAndSettle();
    expect(find.text('إبلاغ عن الاسم أو الصورة'), findsNothing);
    await tester.longPress(find.text('عمر'));
    await tester.pumpAndSettle();
    expect(find.text('إبلاغ عن الاسم أو الصورة'), findsOneWidget);
  });

  group('zones follow the rank (design §3.5 outcomeFor)', () {
    Map<String, dynamic> person(int i, int? rank) => {
          'handle': 'p-$i',
          'name': 'p$i',
          'avatar': {'kind': 'preset', 'id': 'm03'},
          'level': {'level': 1, 'progress': 0.1},
          'points': rank == null ? 0 : 1000 - rank,
          'rank': rank,
          'me': false,
        };
    Map<String, dynamic> leagueJson(List<int?> ranks, {int size = 30, int promote = 5, int demote = 5}) => {
          ...leagueJoined(),
          'size': size,
          'promoteZone': promote,
          'demoteZone': demote,
          'rows': [for (var i = 0; i < ranks.length; i++) person(i + 1, ranks[i])],
        };
    LeagueJoined leagueOf(List<int?> ranks, {int size = 30, int promote = 5, int demote = 5}) =>
        LeagueCurrent.fromJson(leagueJson(ranks, size: size, promote: promote, demote: demote)) as LeagueJoined;
    int downFrom(LeagueJoined l) => demoteFrom(l, l.rows, up: l.rows.where((r) => r.rank != null && r.rank! <= l.promoteZone).length);

    test('fewer rows than the group (people left or are blocked): only places past size − demote', () {
      final l = leagueOf([for (var r = 1; r <= 28; r++) r]); // size 30, 28 shown
      expect(downFrom(l), 25); // rank 26 onwards; ranks 24–25 stay
    });

    test('a tie straddling the demote boundary stays (the kinder side)', () {
      final l = leagueOf([1, 2, 3, 4, 4, 6], size: 6, promote: 2, demote: 2);
      expect(downFrom(l), 5); // only rank 6; both rank-4 rows stay
      expect(downFrom(leagueOf([1, 2, 3, 4, 5, 5], size: 6, promote: 2, demote: 2)), 4); // a tie past it all moves
    });

    test('0 points share the place after the last ranked tie', () {
      // 20 ranked + 10 at 0: they share place 21 (≤ 25) — nobody moves down.
      final many = leagueOf([for (var r = 1; r <= 20; r++) r, for (var i = 0; i < 10; i++) null]);
      expect(downFrom(many), many.rows.length);
      // 26 ranked + 4 at 0: place 27 > 25 — ranks 26+ and the 0-point rows move down.
      final few = leagueOf([for (var r = 1; r <= 26; r++) r, for (var i = 0; i < 4; i++) null]);
      expect(downFrom(few), 25);
      // Before the first snapshot every rank is null: place 1, nobody moves.
      final none = leagueOf([for (var i = 0; i < 30; i++) null]);
      expect(downFrom(none), 30);
    });

    test('a zone of 0 and the promote zone are never crossed', () {
      expect(downFrom(leagueOf([1, 2, 3, 4, 5, 6], size: 6, promote: 2, demote: 0)), 6);
      final small = leagueOf([1, 1, 1], size: 3, promote: 1, demote: 1);
      expect(downFrom(small), 3); // all tied first: in the promote zone, so never down
    });

    Future<void> pumpZones(WidgetTester tester, Map<String, dynamic> league) async {
      final rig = CommunityRig(routes: {
        'GET /v1/me/profile': (_) => jsonResponse(profileJson()),
        'GET /v1/leagues/current': (_) => jsonResponse(league),
        'GET /v1/leagues/history': (_) => jsonResponse(const []),
      },);
      await seedProfile(rig, {...profileJson(), 'league': null});
      tester.view.physicalSize = const Size(390 * 3, 4200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(const LeagueScreen(), kv: rig.kv, overrides: rig.overrides));
      await tester.pumpAndSettle();
    }

    double y(WidgetTester tester, String text) => tester.getCenter(find.text(text)).dy;

    testWidgets('widget: 28 rows of 30 — the demote label sits between ranks 25 and 26', (tester) async {
      await pumpZones(tester, leagueJson([for (var r = 1; r <= 28; r++) r]));
      const down = 'يبدأون الأسبوع القادم في فضة';
      expect(find.text(down), findsOneWidget);
      expect(y(tester, down), greaterThan(y(tester, 'p25')));
      expect(y(tester, down), lessThan(y(tester, 'p26')));
    });

    testWidgets('widget: a blocked row near the bottom does not move the label', (tester) async {
      await pumpZones(tester, leagueJson([for (var r = 1; r <= 30; r++) r]));
      final container = ProviderScope.containerOf(tester.element(find.byType(LeagueScreen)));
      container.read(hiddenHandlesProvider.notifier).hide('p-27');
      await tester.pumpAndSettle();
      const down = 'يبدأون الأسبوع القادم في فضة';
      expect(find.text('p27'), findsNothing);
      expect(find.text(down), findsOneWidget);
      expect(y(tester, down), greaterThan(y(tester, 'p25')));
      expect(y(tester, down), lessThan(y(tester, 'p26')));
    });

    testWidgets('widget: before the first snapshot (every rank null) no zone label at all', (tester) async {
      await pumpZones(tester, leagueJson([for (var i = 0; i < 30; i++) null]));
      expect(find.text('يبدأون الأسبوع القادم في فضة'), findsNothing);
      expect(find.textContaining('يصعدون إلى'), findsNothing);
      expect(find.text('p30'), findsOneWidget);
    });

    testWidgets('widget: a tie at the boundary is not split', (tester) async {
      await pumpZones(tester, leagueJson([1, 2, 3, 4, 4, 6], size: 6, promote: 2, demote: 2));
      const down = 'يبدأون الأسبوع القادم في فضة';
      expect(y(tester, down), greaterThan(y(tester, 'p5'))); // both rank-4 rows above the label
      expect(y(tester, down), lessThan(y(tester, 'p6')));
    });
  });

  testWidgets('a server error after the cached league keeps the view, with a toast', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/leagues/current': (_) => errorResponse(500, 'internal'),
      'GET /v1/leagues/history': (_) => jsonResponse(history),
      'GET /v1/me/profile': (_) => offline(),
    },);
    await seedProfile(rig, {...profileJson(), 'league': null});
    await rig.kv.write(CommunityRepository.leagueKey, jsonEncode(leagueJoined()));
    await pumpLeague(tester, rig);
    expect(find.text('أنت'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsNothing);
    expect(find.text('تعذّر التحميل. تحقق من الاتصال.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('feature_off still replaces a cached league', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/leagues/current': (_) => errorResponse(403, 'feature_off'),
      'GET /v1/me/profile': (_) => offline(),
    },);
    await seedProfile(rig, {...profileJson(), 'league': null});
    await rig.kv.write(CommunityRepository.leagueKey, jsonEncode(leagueJoined()));
    await pumpLeague(tester, rig);
    expect(find.text('هذه المنافسة غير متاحة الآن.'), findsOneWidget);
    expect(find.text('أنت'), findsNothing);
  });

  group('week result', () {
    Future<bool?> openHost(WidgetTester tester, CommunityRig rig) async {
      bool? shown;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(meProfileProvider);
                return TextButton(onPressed: () async => shown = await maybeShowWeekResult(context, ref), child: const Text('go'));
              },
            ),
          ),
          kv: rig.kv,
          overrides: rig.overrides,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return shown;
    }

    testWidgets('shown once per week from the cached profile, with the earned badge', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      await seedProfile(rig, profileJson());
      expect(await openHost(tester, rig), isTrue);
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
      expect(find.text('صعدت إلى ذهب'), findsOneWidget);
      expect(find.text('بين الثلاثة الأوائل'), findsOneWidget);
      expect(await rig.kv.read(seenWeekKey), '2026-11-07');
      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();

      expect(await openHost(tester, rig), isFalse);
      expect(find.text('انتهى الأسبوع'), findsNothing);
    });

    testWidgets('no sheet when the person left that week (outcome null)', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      final p = profileJson();
      final league = (p['league'] as Map).cast<String, dynamic>();
      await seedProfile(rig, {
        ...p,
        'league': {
          ...league,
          'lastWeek': {...(league['lastWeek'] as Map).cast<String, dynamic>(), 'outcome': null, 'badge': null},
        },
      });
      expect(await openHost(tester, rig), isFalse);
      expect(find.text('انتهى الأسبوع'), findsNothing);
    });

    testWidgets('stay and down read gently', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      final p = profileJson();
      final league = (p['league'] as Map).cast<String, dynamic>();
      await seedProfile(rig, {
        ...p,
        'league': {
          ...league,
          'division': 1,
          'divisionAr': 'برونز',
          'divisionEn': 'Bronze',
          'lastWeek': {'startsOn': '2026-11-07', 'division': 2, 'newDivision': 1, 'rank': 27, 'outcome': 'down', 'badge': null},
        },
      });
      expect(await openHost(tester, rig), isTrue);
      expect(find.text('تبدأ هذا الأسبوع في برونز'), findsOneWidget);
    });

    testWidgets('two callers at once (Home and the league): one sheet', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      await seedProfile(rig, profileJson());
      List<bool>? results;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(meProfileProvider);
                return TextButton(
                  onPressed: () async =>
                      results = await Future.wait([maybeShowWeekResult(context, ref), maybeShowWeekResult(context, ref)]),
                  child: const Text('go'),
                );
              },
            ),
          ),
          kv: rig.kv,
          overrides: rig.overrides,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(results, [true, false]);
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
    });

    testWidgets('a caller gone before the sheet: the week stays unseen for the next one', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      await seedProfile(rig, profileJson());
      BuildContext? inner;
      WidgetRef? outer;
      var showInner = true;
      late StateSetter setOuter;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(meProfileProvider);
                outer = ref;
                return StatefulBuilder(
                  builder: (context, set) {
                    setOuter = set;
                    return showInner
                        ? Builder(
                            builder: (c) {
                              inner = c;
                              return const SizedBox();
                            },
                          )
                        : const SizedBox();
                  },
                );
              },
            ),
          ),
          kv: rig.kv,
          overrides: rig.overrides,
        ),
      );
      await tester.pumpAndSettle();
      setOuter(() => showInner = false);
      await tester.pump();
      expect(inner!.mounted, isFalse);
      final shown = maybeShowWeekResult(inner!, outer!);
      await tester.pumpAndSettle();
      expect(await shown, isFalse);
      expect(await rig.kv.read(seenWeekKey), isNull);
      expect(find.text('انتهى الأسبوع'), findsNothing);
    });

    testWidgets('the league screen shows it on open', (tester) async {
      final rig = joinedRig();
      await seedProfile(rig, profileJson());
      await pumpLeague(tester, rig);
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
    });
  });

  group('motion', () {
    Widget still(Widget child) => Builder(
          builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child),
        );

    PublicCompetitor person(String handle, int rank, {bool me = false}) => PublicCompetitor(
          handle: handle,
          name: 'name-$handle',
          avatar: const InitialAvatar(),
          level: const PublicLevelRing(level: 2, progress: 0.5),
          points: 500 - rank,
          rank: rank,
          me: me,
        );

    test('RankMotion: a new order gives each moved row its distance, once; the first order none', () {
      final m = RankMotion()..update(['a', 'b', 'c']);
      expect(m.takeMove('a'), 0);
      m.update(['c', 'a', 'b']);
      expect(m.takeMove('c'), 2); // climbed two rows
      expect(m.takeMove('a'), -1);
      expect(m.takeMove('a'), 0); // consumed
    });

    testWidgets('a row that moved between snapshots glides from its old place; the own row sheens once', (tester) async {
      Widget list(List<PublicCompetitor> rows) => harness(
            RankMotionScope(
              handles: [for (final r in rows) r.handle],
              child: Scaffold(body: Column(children: [for (final r in rows) CompetitorRow(key: ValueKey(r.handle), competitor: r)])),
            ),
          );
      final a = person('a', 1);
      final me = person('me', 2, me: true);
      await tester.pumpWidget(list([a, me]));
      expect(tester.widget<YqSheen>(find.descendant(of: find.byKey(const ValueKey('me')), matching: find.byType(YqSheen))).play, isTrue);
      expect(tester.widget<YqSheen>(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byType(YqSheen))).play, isFalse);
      await tester.pumpAndSettle();

      await tester.pumpWidget(list([person('me', 1, me: true), person('a', 2)]));
      final shifts = {
        for (final h in ['me', 'a'])
          h: tester.widget<YqShiftIn>(find.descendant(of: find.byKey(ValueKey(h)), matching: find.byType(YqShiftIn))).rows,
      };
      expect(shifts, {'me': 1, 'a': -1});
      // The row's slot moved at once; what is drawn in it glides up from the old place.
      final slot = tester.getTopLeft(find.byKey(const ValueKey('me'))).dy;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.text('name-me')).dy, greaterThan(slot + 10)); // still on its way up
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('name-me')).dy, lessThan(tester.getTopLeft(find.text('name-a')).dy));
    });

    testWidgets('a closed podium rises 1, 2, 3 in sequence, once', (tester) async {
      final rows = [person('a', 1), person('b', 2), person('c', 3), person('d', 4)];
      await tester.pumpWidget(
        harness(
          RankMotionScope(
            handles: [for (final r in rows) r.handle],
            child: Scaffold(
              body: Column(children: [for (final r in rows) CompetitorRow(key: ValueKey(r.handle), competitor: r, podium: true)]),
            ),
          ),
        ),
      );
      final slides = [
        for (final h in ['a', 'b', 'c', 'd'])
          tester.widget<YqSlideIn>(find.descendant(of: find.byKey(ValueKey(h)), matching: find.byType(YqSlideIn))),
      ];
      expect([for (final s in slides) s.play], [true, true, true, false]);
      expect([for (final s in slides.take(3)) s.delay], [Duration.zero, CompetitorRow.podiumStep, CompetitorRow.podiumStep * 2]);
      await tester.pumpAndSettle();
    });

    testWidgets('the joined league under reduce-motion: final numbers, drawn zone lines, and it settles', (tester) async {
      final rig = CommunityRig(
        routes: {
          'GET /v1/leagues/current': (_) => jsonResponse(leagueJoined()),
          'GET /v1/me/profile': (_) => jsonResponse(profileJson()),
        },
      );
      await rig.kv.write(seenWeekKey, '2026-11-07'); // no week sheet in the way
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(still(const LeagueScreen()), kv: rig.kv, overrides: rig.overrides));
      await tester.pumpAndSettle();
      expect(find.text('335 نقطة هذا الأسبوع'), findsOneWidget);
      expect(find.text('أنت'), findsOneWidget);
      expect(find.byType(YqDrawLine), findsWidgets);
      for (final line in tester.widgetList<FractionallySizedBox>(
        find.descendant(of: find.byType(YqDrawLine), matching: find.byType(FractionallySizedBox)),
      )) {
        expect(line.widthFactor, 1);
      }
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('week result: the outcome glyph settles, a top-three finish rises on the podium', (tester) async {
      const last = LeagueLastWeek(startsOn: '2026-11-07', division: 2, newDivision: 3, rank: 2, outcome: LeagueOutcome.up, badge: null);
      await tester.pumpWidget(harness(const Scaffold(body: WeekResultSheet(lastWeek: last))));
      expect(find.byKey(const ValueKey('outcome-up')), findsOneWidget);
      expect(find.byType(WeekPodium), findsOneWidget);
      expect(find.text('أنت'), findsOneWidget);
      expect(find.bySemanticsLabel('أنهيت الأسبوع في المركز 2'), findsOneWidget);
      await tester.pumpAndSettle();

      // Fourth place: no podium. Reduce-motion: the glyph is simply there.
      const fourth = LeagueLastWeek(startsOn: '2026-11-07', division: 2, newDivision: 2, rank: 4, outcome: LeagueOutcome.stay, badge: null);
      await tester.pumpWidget(harness(still(const Scaffold(body: WeekResultSheet(lastWeek: fourth)))));
      expect(find.byType(WeekPodium), findsNothing);
      expect(find.byKey(const ValueKey('outcome-stay')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the week result opens on the spring and settles', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/me/profile': (_) => offline()});
      await seedProfile(rig, profileJson());
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(meProfileProvider);
                return TextButton(onPressed: () => maybeShowWeekResult(context, ref), child: const Text('go'));
              },
            ),
          ),
          kv: rig.kv,
          overrides: rig.overrides,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(OutcomeGlyph), findsOneWidget);
    });
  });
}
