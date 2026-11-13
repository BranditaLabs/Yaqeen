import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/community/data/community_repository.dart';
import 'package:yaqeen/features/community/presentation/league_screen.dart';
import 'package:yaqeen/features/community/presentation/week_result_sheet.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/presentation/me_profile_controller.dart';

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
      });

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
    expect(find.text('يبدأون الأسبوع القادم في فضة'), findsOneWidget);
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
    expect(find.text('Start next week in Silver'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining(RegExp('[٠-٩]')), findsNothing);
  });

  testWidgets('off → join sheet (first name, attestation) → direct PUT /v1/me/community, not the Outbox', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(leagues: false, attested: false, name: 'أحمد محمود')),
      'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_off.json')),
      'GET /v1/leagues/history': (_) => jsonResponse(const []),
      'PUT /v1/me/community': (_) => jsonResponse(settingsAfterJoin()),
    });
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
    });
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
    });
    await pumpLeague(tester, rig);
    await tester.tap(find.text('انضم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انضم').last);
    await tester.pumpAndSettle();
    expect(find.text('أخفى فريق الدعم هذا الاسم. راسلنا لمراجعته.'), findsOneWidget);
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
    });
    await seedProfile(rig, {...profileJson(), 'league': null});
    await pumpLeague(tester, rig);
    expect(find.text('نحسب نتائج الأسبوع… عُد بعد قليل'), findsOneWidget);
  });

  testWidgets('banned: «أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.»', (tester) async {
    final rig = CommunityRig(routes: {
      'GET /v1/me/profile': (_) => jsonResponse(profileJson(banned: true)),
      'GET /v1/leagues/current': (_) => jsonResponse(leagueJoined()),
    });
    await seedProfile(rig, profileJson(banned: true));
    await pumpLeague(tester, rig);
    expect(find.text('أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.'), findsOneWidget);
    expect(find.text('أنت'), findsNothing);
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

    testWidgets('the league screen shows it on open', (tester) async {
      final rig = joinedRig();
      await seedProfile(rig, profileJson());
      await pumpLeague(tester, rig);
      expect(find.text('انتهى الأسبوع'), findsOneWidget);
    });
  });
}
