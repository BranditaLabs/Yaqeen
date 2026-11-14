import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/theme/tokens.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_count.dart';
import 'package:yaqeen/core/widgets/yq_layout.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/community/data/community_repository.dart';
import 'package:yaqeen/features/community/domain/community_models.dart';
import 'package:yaqeen/features/community/presentation/community_settings_screen.dart';
import 'package:yaqeen/features/community/presentation/leaderboard_screen.dart';
import 'package:yaqeen/features/community/presentation/tournament_screen.dart';
import 'package:yaqeen/features/community/presentation/tournaments_screen.dart';
import 'package:yaqeen/features/prayer/data/city_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/core/widgets/yq_avatar.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/core/widgets/yq_stage.dart';
import 'package:yaqeen/features/community/presentation/community_widgets.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'community_rig.dart';

Map<String, dynamic> profileJson({
  bool leagues = true,
  bool leaderboard = true,
  bool country = false,
  bool attested = true,
  String? countryCode = 'EG',
}) {
  final p = fixtureMap('me_profile.json');
  return {
    ...p,
    'league': null, // no week-result sheet in these tests
    'community': {
      'leagues': leagues,
      'leaderboard': leaderboard,
      'leaderboardCountry': country,
      'banned': false,
      'attestedAdult': attested,
      'country': countryCode,
    },
  };
}

List<Map<String, dynamic>> tournaments() => [for (final t in fixture('tournaments.json') as List) (t as Map).cast<String, dynamic>()];

Map<String, dynamic> preset(Map<String, dynamic> row) =>
    {...row, if ((row['avatar'] as Map)['kind'] == 'photo') 'avatar': {'kind': 'preset', 'id': 'f05'}};

Map<String, dynamic> standings({List<Map<String, dynamic>>? rows, String? next}) {
  final s = fixtureMap('standings.json');
  return {
    ...s,
    'rows': rows ?? [for (final r in s['rows'] as List) preset((r as Map).cast<String, dynamic>())],
    'nextCursor': next,
  };
}

Map<String, dynamic> board({String scope = 'global', bool joined = true, bool countryJoined = false}) {
  final b = fixtureMap('leaderboard.json');
  return {
    ...b,
    'scope': scope,
    'country': scope == 'country' ? 'EG' : null,
    'joined': joined,
    'countryJoined': countryJoined,
    'rows': [for (final r in b['rows'] as List) preset((r as Map).cast<String, dynamic>())],
  };
}

/// The gold podium marks drawn (ranks 1–3 of a closed period).
Finder goldMarks() => find.byWidgetPredicate((w) {
      final d = w is Container ? w.decoration : null;
      return d is BoxDecoration && d.border is Border && (d.border! as Border).top.color == YqColors.gold;
    });

Future<void> pump(WidgetTester tester, CommunityRig rig, Widget screen, {String locale = 'ar', Map<String, dynamic>? profile}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await rig.kv.write(ProfileRepository.meKey, jsonEncode(profile ?? profileJson()));
  rig.routes.putIfAbsent('GET /v1/me/profile', () => (_) => jsonResponse(profile ?? profileJson()));
  // A router, so pushes from cards and rows resolve.
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(path: '/profile/tournaments/:id', builder: (_, s) => TournamentScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/profile/settings', builder: (_, __) => const Scaffold(body: Text('settings'))),
    ],
  );
  // cities.json decodes on an isolate: load it for real once, outside the fake clock.
  final cities = CityRepository();
  await tester.runAsync(cities.all);
  await tester.pumpWidget(
    harness(
      Router.withConfig(config: router),
      locale: locale,
      kv: rig.kv,
      overrides: [...rig.overrides, cityRepositoryProvider.overrideWithValue(cities)],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  group('tournaments', () {
    testWidgets('list: live by default, upcoming and ended tabs, days, participants, «أنت مشارك»', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/tournaments': (_) => jsonResponse(tournaments())});
      await pump(tester, rig, const TournamentsScreen());
      expect(find.text('خريف الخير'), findsOneWidget);
      expect(find.text('تنتهي بعد 11 يوماً'), findsOneWidget);
      expect(find.text('214 مشارك'), findsOneWidget);
      expect(find.text('أنت مشارك'), findsOneWidget);
      expect(find.text('رمضان 1448'), findsNothing);

      await tester.tap(find.text('قادمة'));
      await tester.pumpAndSettle();
      expect(find.text('رمضان 1448'), findsOneWidget);
      expect(find.text('تبدأ بعد 83 يوماً'), findsOneWidget);

      await tester.tap(find.text('انتهت').first);
      await tester.pumpAndSettle();
      expect(find.text('تحدّي المولد'), findsOneWidget);
    });

    testWidgets('list: empty copy when nothing is announced', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/tournaments': (_) => jsonResponse(const [])});
      await pump(tester, rig, const TournamentsScreen());
      expect(find.text('لا بطولات الآن. نُعلن عنها في مواسم مثل رمضان وذي الحجة.'), findsOneWidget);
    });

    testWidgets('join needs the acknowledgement and the attestation; then a direct POST', (tester) async {
      final live = {...tournaments()[1], 'joined': false, 'me': null};
      final id = live['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(live),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
        'POST /v1/tournaments/$id/join': (_) => jsonResponse(tournaments()[1]),
      },);
      await pump(tester, rig, TournamentScreen(id: id), profile: profileJson(attested: false));
      expect(find.text('الشارة: خريف الخير'), findsOneWidget);

      await tester.tap(find.text('انضم إلى البطولة'));
      await tester.pumpAndSettle();
      const ack = 'أوافق على ظهور اسمي وصورتي ومستواي ونقاطي في هذه البطولة.';
      const attest = 'عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري';
      expect(find.text(ack), findsOneWidget);
      expect(find.text(attest), findsOneWidget);
      await tester.tap(find.text('انضم').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ack));
      await tester.pump();
      await tester.tap(find.text('انضم').last);
      await tester.pumpAndSettle();
      expect(rig.calls.where((c) => c.startsWith('POST')), isEmpty); // still needs the attestation

      await tester.tap(find.text(attest));
      await tester.pump();
      await tester.tap(find.text('انضم').last);
      await tester.pumpAndSettle();
      expect(rig.bodies['POST /v1/tournaments/$id/join'], {'acknowledge': true, 'attestAdult': true});
      expect(await rig.queued(), isEmpty);
    });

    testWidgets('joined: rank + live points in the stage; leave asks, then leaves', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      final left = {...live, 'joined': false, 'me': null};
      var current = live;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(current),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
        'DELETE /v1/tournaments/$id/join': (_) => jsonResponse(current = left),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      // The rank's digits roll into place (one Text per digit; the number is its label).
      expect(find.byWidgetPredicate((w) => w is YqRollingNumber && w.value == 17), findsOneWidget);
      expect(find.text('640 نقطة في البطولة'), findsOneWidget);
      expect(find.text('يُحدَّث الترتيب كل ليلة.'), findsOneWidget);

      await tester.tap(find.text('مغادرة البطولة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غادر'));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('DELETE /v1/tournaments/$id/join'));
      expect(find.text('640 نقطة في البطولة'), findsNothing);
    });

    testWidgets('leave offline: queued, and hidden at once', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments': (_) => jsonResponse(tournaments()),
        'GET /v1/tournaments/$id': (_) => jsonResponse(live),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      rig.offlineAll = true;
      await tester.tap(find.text('مغادرة البطولة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غادر'));
      await tester.pumpAndSettle();
      expect((await rig.queued()).single.path, '/v1/tournaments/$id/join');
      expect(find.text('640 نقطة في البطولة'), findsNothing);
      expect(find.text('انضم إلى البطولة'), findsOneWidget);
    });

    testWidgets('standings page through the snapshot with the cursor', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(live),
        'GET /v1/tournaments/$id/standings': (req) => req.url.queryParameters['cursor'] == null
            ? jsonResponse(standings(next: '100:sara-1093'))
            : jsonResponse(standings(
                rows: [
                  {
                    'handle': 'yusuf-7781',
                    'name': 'يوسف',
                    'avatar': {'kind': 'preset', 'id': 'm02'},
                    'level': {'level': 2, 'progress': 0.3},
                    'points': 120,
                    'rank': 101,
                    'me': false,
                  },
                ],
              ),),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      expect(rig.calls, contains('GET /v1/tournaments/$id/standings?cursor=100%3Asara-1093'));
      expect(find.text('يوسف'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
    });

    testWidgets('a closed tournament: podium marks; «انتهت»', (tester) async {
      final ended = tournaments()[2];
      final id = ended['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(ended),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      expect(find.text('انتهت'), findsWidgets);
      expect(find.text('مغادرة البطولة'), findsNothing);
    });

    testWidgets('closed: gold podium marks; ended but not yet closed by the job: none', (tester) async {
      final ended = tournaments()[2];
      final id = ended['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(ended),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      expect(goldMarks(), findsNWidgets(3)); // ranks 1, 1, 3
    });

    testWidgets('ended but not yet closed by the job: provisional ranks, no gold', (tester) async {
      final provisional = {...tournaments()[2], 'closed': false};
      final id = provisional['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(provisional),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      expect(find.text('Sara'), findsOneWidget);
      expect(goldMarks(), findsNothing);
    });

    testWidgets('a failed standings page stops loading until «إعادة المحاولة»', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      var fail = true;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(live),
        'GET /v1/tournaments/$id/standings': (req) {
          if (req.url.queryParameters['cursor'] == null) return jsonResponse(standings(next: '100:sara-1093'));
          if (fail) return errorResponse(503, 'unavailable');
          return jsonResponse(standings(rows: [
            {
              'handle': 'yusuf-7781',
              'name': 'يوسف',
              'avatar': {'kind': 'preset', 'id': 'm02'},
              'level': {'level': 2, 'progress': 0.3},
              'points': 120,
              'rank': 101,
              'me': false,
            },
          ],),);
        },
      },);
      int pages() => rig.calls.where((c) => c.contains('standings?cursor=')).length;
      await pump(tester, rig, TournamentScreen(id: id));
      expect(pages(), 1);
      // Frames keep coming (scrolling at the bottom): no new request by itself.
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -40), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(pages(), 1);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(pages(), 2);
      expect(find.text('يوسف'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
    });

    testWidgets('cached standings paint first; the fresh page replaces them', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      final fresh = standings(rows: [
        {
          'handle': 'yusuf-7781',
          'name': 'يوسف',
          'avatar': {'kind': 'preset', 'id': 'm02'},
          'level': {'level': 2, 'progress': 0.3},
          'points': 900,
          'rank': 1,
          'me': false,
        },
      ],);
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(live),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(fresh),
      },);
      await rig.kv.write(
        CommunityRepository.tournamentsKey,
        jsonEncode({
          'list': [live],
          'standings': {id: standings()},
        }),
      );
      final gate = rig.gates['GET /v1/tournaments/$id/standings'] = Completer<void>();
      await pump(tester, rig, TournamentScreen(id: id));
      expect(find.text('عمر'), findsOneWidget); // cached, while the request waits
      expect(find.text('يوسف'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('يوسف'), findsOneWidget);
      expect(find.text('عمر'), findsNothing);
    });

    testWidgets('leave on a slow connection: hidden before the DELETE answers', (tester) async {
      final live = tournaments()[1];
      final id = live['id'] as String;
      final rig = CommunityRig(routes: {
        'GET /v1/tournaments/$id': (_) => jsonResponse(live), // the server has not seen the leave yet
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
        'DELETE /v1/tournaments/$id/join': (_) => jsonResponse({...live, 'joined': false, 'me': null}),
      },);
      await pump(tester, rig, TournamentScreen(id: id));
      final gate = rig.gates['DELETE /v1/tournaments/$id/join'] = Completer<void>();
      await tester.tap(find.text('مغادرة البطولة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('غادر'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(rig.calls, contains('DELETE /v1/tournaments/$id/join'));
      expect(find.text('640 نقطة في البطولة'), findsNothing);
      expect(find.text('مغادرة البطولة'), findsNothing);
      expect(find.text('انضم إلى البطولة'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('640 نقطة في البطولة'), findsNothing);
      expect(await rig.queued(), isEmpty);
    });

    testWidgets('English: Western digits', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/tournaments': (_) => jsonResponse(tournaments())});
      await pump(tester, rig, const TournamentsScreen(), locale: 'en');
      expect(find.text('Autumn of good'), findsOneWidget);
      expect(find.text('Ends in 11 days'), findsOneWidget);
      expect(find.text('214 taking part'), findsOneWidget);
      expect(find.textContaining(RegExp('[٠-٩]')), findsNothing);
    });
  });

  group('level board', () {
    testWidgets('world: rings and level names, no points; my rank pinned', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())});
      await pump(tester, rig, const LeaderboardScreen());
      expect(find.text('لوحة المستويات'), findsOneWidget);
      expect(find.text('ثابت'), findsOneWidget); // omar, level 4
      expect(find.text('منارة'), findsOneWidget); // sara, level 6
      expect(find.text('420'), findsNothing);
      expect(find.text('ترتيبك 4'), findsOneWidget);
      expect(find.text('مصر'), findsOneWidget); // the country tab, named from cities.json
    });

    testWidgets('world: before the first snapshot «يظهر ترتيبك بعد التحديث الليلي»', (tester) async {
      final b = board();
      b['me'] = {...(b['me'] as Map).cast<String, dynamic>(), 'rank': null};
      final rig = CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(b)});
      await pump(tester, rig, const LeaderboardScreen());
      expect(find.text('يظهر ترتيبك بعد التحديث الليلي'), findsOneWidget);
    });

    testWidgets('not joined: «أظهرني في اللوحة» → a direct PUT (already attested)', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (_) => jsonResponse(board(joined: false)),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson()['community']),
      },);
      await pump(tester, rig, const LeaderboardScreen(), profile: profileJson(leaderboard: false));
      expect(find.text('تظهر باسمك وصورتك ومستواك فقط.'), findsOneWidget);
      expect(find.text('ترتيبك 4'), findsNothing);
      await tester.tap(find.text('أظهرني في اللوحة'));
      await tester.pumpAndSettle();
      expect(rig.bodies['PUT /v1/me/community'], {'leaderboard': true, 'source': 'settings'});
    });

    testWidgets('country: no city → «اختر مدينتك…», without asking the server', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())});
      await pump(tester, rig, const LeaderboardScreen(), profile: profileJson(countryCode: null));
      await tester.tap(find.text('لوحة بلدي'));
      await tester.pumpAndSettle();
      expect(find.text('اختر مدينتك في إعدادات الصلاة لترى ترتيب بلدك.'), findsOneWidget);
      expect(rig.calls.where((c) => c.contains('scope=country')), isEmpty);
    });

    testWidgets('country: country_unknown from the server', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) =>
            req.url.queryParameters['scope'] == 'country' ? errorResponse(409, 'country_unknown') : jsonResponse(board()),
      },);
      await pump(tester, rig, const LeaderboardScreen());
      await tester.tap(find.text('مصر'));
      await tester.pumpAndSettle();
      expect(find.text('اختر مدينتك في إعدادات الصلاة لترى ترتيب بلدك.'), findsOneWidget);
    });

    testWidgets('country: too small → the note, and the opt-in that lets it grow', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) =>
            req.url.queryParameters['scope'] == 'country' ? errorResponse(409, 'country_too_small') : jsonResponse(board()),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson(country: true)['community']),
      },);
      await pump(tester, rig, const LeaderboardScreen());
      await tester.tap(find.text('مصر'));
      await tester.pumpAndSettle();
      expect(find.text('لوحة بلدك تظهر حين يشارك فيها 20 شخصاً على الأقل.'), findsOneWidget);
      expect(find.text('تظهر باسمك وصورتك ومستواك فقط، وتظهر في لوحة بلدك.'), findsOneWidget);
      await tester.tap(find.text('أظهرني في لوحة بلدي'));
      await tester.pumpAndSettle();
      // Already on the world board: only the country switch is sent.
      expect(rig.bodies['PUT /v1/me/community'], {'leaderboardCountry': true, 'source': 'settings'});
    });

    testWidgets('offline: the cached board with the offline banner', (tester) async {
      final rig = CommunityRig()..offlineAll = true;
      await rig.kv.write(CommunityRepository.leaderboardKey(LeaderboardScope.global), jsonEncode(board()));
      await pump(tester, rig, const LeaderboardScreen());
      expect(find.text('ترتيبك 4'), findsOneWidget);
      expect(find.text('عمر'), findsOneWidget);
      expect(tester.widget<YqOfflineBanner>(find.byType(YqOfflineBanner)).offline, isTrue);
      expect(find.text('أنت غير متصل · نعمل بما على جهازك'), findsOneWidget);
    });

    testWidgets('the cached board paints before the network answers', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())});
      await rig.kv.write(CommunityRepository.leaderboardKey(LeaderboardScope.global), jsonEncode(board()));
      final gate = rig.gates['GET /v1/leaderboard'] = Completer<void>();
      await pump(tester, rig, const LeaderboardScreen());
      expect(find.text('ترتيبك 4'), findsOneWidget); // from the cache, the request still waiting
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('ترتيبك 4'), findsOneWidget);
    });

    testWidgets('guest: the sign-in note, never the network', (tester) async {
      final rig = CommunityRig(signedIn: false, routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())});
      await pump(tester, rig, const LeaderboardScreen());
      expect(find.text('سجّل الدخول لتنضم إلى المنافسات'), findsOneWidget);
      expect(rig.calls.where((c) => c.startsWith('GET /v1/leaderboard')), isEmpty);
    });

    testWidgets('country tab not joined (world board on): «أظهرني في لوحة بلدي» → PUT {leaderboardCountry:true}', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) => jsonResponse(
              req.url.queryParameters['scope'] == 'country' ? board(scope: 'country', countryJoined: false) : board(),
            ),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson(country: true)['community']),
      },);
      await pump(tester, rig, const LeaderboardScreen());
      await tester.tap(find.text('مصر'));
      await tester.pumpAndSettle();
      expect(find.text('تظهر باسمك وصورتك ومستواك فقط، وتظهر في لوحة بلدك.'), findsOneWidget);
      await tester.tap(find.text('أظهرني في لوحة بلدي'));
      await tester.pumpAndSettle();
      expect(rig.bodies['PUT /v1/me/community'], {'leaderboardCountry': true, 'source': 'settings'});
    });

    testWidgets('country tab with the world board off: it offers the level board by name, never both at once', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) => jsonResponse(
              req.url.queryParameters['scope'] == 'country'
                  ? board(scope: 'country', joined: false, countryJoined: false)
                  : board(joined: false),
            ),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson()['community']),
      },);
      await pump(tester, rig, const LeaderboardScreen(), profile: profileJson(leaderboard: false));
      await tester.tap(find.text('مصر'));
      await tester.pumpAndSettle();
      expect(find.textContaining('شغّل «لوحة المستويات» أولاً لتظهر في لوحة بلدك.'), findsOneWidget);
      expect(find.text('أظهرني في لوحة بلدي'), findsNothing);
      await tester.tap(find.text('أظهرني في اللوحة'));
      await tester.pumpAndSettle();
      expect(rig.bodies['PUT /v1/me/community'], {'leaderboard': true, 'source': 'settings'});
    });

    testWidgets('country switch: the country board with my rank', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) => jsonResponse(
              req.url.queryParameters['scope'] == 'country' ? board(scope: 'country', countryJoined: true) : board(),
            ),
      },);
      await pump(tester, rig, const LeaderboardScreen(), profile: profileJson(country: true));
      await tester.tap(find.text('مصر'));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('GET /v1/leaderboard?scope=country'));
      expect(find.text('ترتيبك 4'), findsOneWidget);
    });

    testWidgets('switching boards keeps the screen: the segmented control and canvas are never remounted, no row glides', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (req) => jsonResponse(
              req.url.queryParameters['scope'] == 'country' ? board(scope: 'country', countryJoined: true) : board(),
            ),
      },);
      await pump(tester, rig, const LeaderboardScreen(), profile: profileJson(country: true));
      final segmented = tester.element(find.byType(YqSegmented<LeaderboardScope>));
      final canvas = tester.element(find.byType(YqCanvas));
      final gate = rig.gates['GET /v1/leaderboard'] = Completer<void>();
      await tester.tap(find.text('مصر'));
      await tester.pump(); // the country board is loading: only the board area shows the skeleton
      expect(find.byType(YqSkeleton), findsOneWidget);
      expect(tester.element(find.byType(YqSegmented<LeaderboardScope>)), same(segmented));
      expect(find.byType(YqSegmented<LeaderboardScope>), findsOneWidget); // never two screens cross-fading
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(YqSkeleton), findsNothing);
      expect(tester.element(find.byType(YqSegmented<LeaderboardScope>)), same(segmented));
      expect(tester.element(find.byType(YqCanvas)), same(canvas));
      // Back to the cached world board: a different list, so nothing slides in from the other one.
      await tester.tap(find.text('العالم'));
      await tester.pump();
      for (final shift in tester.widgetList<YqShiftIn>(find.byType(YqShiftIn))) {
        expect(shift.rows, 0);
      }
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(YqCanvas)), same(canvas));
    });
  });

  group('report and block', () {
    testWidgets('report a name: thanks toast; the daily limit: its own toast', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (_) => jsonResponse(board()),
        'POST /v1/community/reports': (_) => jsonResponse(null, 204),
      },);
      await pump(tester, rig, const LeaderboardScreen());
      await tester.longPress(find.text('عمر'));
      await tester.pumpAndSettle();
      expect(find.text('إبلاغ عن الاسم أو الصورة'), findsOneWidget);
      expect(find.text('حظر عمر'), findsOneWidget);
      expect(find.text('لن تراه ولن يراك في المنافسات.'), findsOneWidget);
      await tester.tap(find.text('اسم غير لائق'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.bodies['POST /v1/community/reports'], {'handle': 'omar-5521', 'reason': 'name'});
      expect(find.text('شكراً، سيراجعه فريق الدعم.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      rig.routes['POST /v1/community/reports'] = (_) => errorResponse(429, 'rate_limited');
      await tester.longPress(find.text('عمر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('سبب آخر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('بلغت حدّ البلاغات اليوم.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('block: the row disappears at once, «تم الحظر.»', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/leaderboard': (_) => jsonResponse(board()),
        'POST /v1/community/blocks': (_) => jsonResponse(fixture('blocks.json')),
      },);
      await pump(tester, rig, const LeaderboardScreen());
      await tester.longPress(find.text('عمر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حظر عمر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('تم الحظر.'), findsOneWidget);
      expect(find.text('عمر'), findsNothing);
      expect(rig.bodies['POST /v1/community/blocks'], {'handle': 'omar-5521'});
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('visibility settings', () {
    testWidgets('a switch per flag; off = a queued leave; the blocked list unblocks', (tester) async {
      final rig = CommunityRig(
        flags: {'leagues': false},
        routes: {
          'GET /v1/community/blocks': (_) => jsonResponse(fixture('blocks.json')),
          'GET /v1/tournaments': (_) => jsonResponse(tournaments()),
          'DELETE /v1/community/blocks/omar-5521': (_) => jsonResponse(null, 204),
          'PUT /v1/me/community': (_) => offline(),
        },
      );
      await pump(tester, rig, const CommunitySettingsScreen());
      expect(find.text('الظهور في المنافسات'), findsOneWidget);
      expect(find.text('الدوري الأسبوعي'), findsNothing); // flag off
      expect(find.text('لوحة المستويات'), findsOneWidget);
      expect(find.text('لوحة بلدي'), findsOneWidget);
      expect(find.text('بطولاتك الجارية'), findsOneWidget);
      expect(find.text('خريف الخير'), findsOneWidget);
      expect(find.text('المحظورون'), findsOneWidget);
      expect(find.text('عضو يقين'), findsOneWidget);

      await tester.tap(find.descendant(of: find.widgetWithText(YqListRow, 'لوحة المستويات'), matching: find.byType(YqSwitch)));
      await tester.pumpAndSettle();
      final q = await rig.queued();
      expect(q.single.path, '/v1/me/community');
      expect(q.single.body, containsPair('leaderboard', false));

      await tester.tap(find.text('إلغاء الحظر').last);
      await tester.pumpAndSettle();
      expect(rig.calls, contains('DELETE /v1/community/blocks/omar-5521'));
    });

    testWidgets('«لوحة بلدي» stays off until the level board is on: no call, no sheet', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/community/blocks': (_) => jsonResponse(const []),
        'GET /v1/tournaments': (_) => jsonResponse(const []),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson(country: true)['community']),
      },);
      await pump(tester, rig, const CommunitySettingsScreen(), profile: profileJson(leaderboard: false));
      expect(find.text('شغّل «لوحة المستويات» أولاً لتظهر في لوحة بلدك.'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.widgetWithText(YqListRow, 'لوحة بلدي'), matching: find.byType(YqSwitch)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(rig.calls.where((c) => c.startsWith('PUT')), isEmpty);
      expect(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'), findsNothing);
    });

    testWidgets('«لوحة بلدي» with the level board on: PUT {leaderboardCountry:true} only', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/community/blocks': (_) => jsonResponse(const []),
        'GET /v1/tournaments': (_) => jsonResponse(const []),
        'PUT /v1/me/community': (_) => jsonResponse(profileJson(country: true)['community']),
      },);
      await pump(tester, rig, const CommunitySettingsScreen());
      await tester.tap(find.descendant(of: find.widgetWithText(YqListRow, 'لوحة بلدي'), matching: find.byType(YqSwitch)));
      await tester.pumpAndSettle();
      expect(rig.bodies['PUT /v1/me/community'], {'leaderboardCountry': true, 'source': 'settings'});
    });

    testWidgets('turning a board on when not attested opens the sheet with the attestation', (tester) async {
      final rig = CommunityRig(routes: {
        'GET /v1/community/blocks': (_) => jsonResponse(const []),
        'GET /v1/tournaments': (_) => jsonResponse(const []),
      },);
      await pump(tester, rig, const CommunitySettingsScreen(), profile: profileJson(leaderboard: false, attested: false));
      expect(find.text('لم تحظر أحداً.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.widgetWithText(YqListRow, 'لوحة المستويات'), matching: find.byType(YqSwitch)));
      await tester.pumpAndSettle();
      expect(find.text('عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري'), findsOneWidget);
      expect(rig.calls.where((c) => c.startsWith('PUT')), isEmpty);
    });
  });

  group('motion', () {
    /// Reduce-motion for everything the router builds (MaterialApp reads it from the platform).
    void reduce(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    testWidgets('a live tournament card breathes for a few breaths, then rests (pumpAndSettle completes)', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/tournaments': (_) => jsonResponse(tournaments())});
      await pump(tester, rig, const TournamentsScreen()); // pump() ends on pumpAndSettle: the dot stops
      expect(find.byType(LivePill), findsOneWidget);
      expect(find.byType(YqBreathingDot), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      // Upcoming and ended cards carry no live dot.
      await tester.tap(find.text('قادمة'));
      await tester.pumpAndSettle();
      expect(find.byType(LivePill), findsNothing);
    });

    testWidgets('a joined live tournament: the rank rolls in, the live eyebrow breathes; reduce-motion: still', (tester) async {
      final live = tournaments().firstWhere((t) => t['phase'] == 'live');
      final id = live['id'] as String;
      final rig = CommunityRig(
        routes: {
          'GET /v1/tournaments/$id': (_) => jsonResponse(live),
          'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
        },
      );
      reduce(tester);
      await pump(tester, rig, TournamentScreen(id: id));
      expect(find.byType(LivePill), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byType(RankNumeral), findsOneWidget);
    });

    testWidgets('a closed podium rises in sequence on the standings', (tester) async {
      final ended = tournaments()[2];
      final id = ended['id'] as String;
      final rig = CommunityRig(
        routes: {
          'GET /v1/tournaments/$id': (_) => jsonResponse(ended),
          'GET /v1/tournaments/$id/standings': (_) => jsonResponse(standings()),
        },
      );
      await pump(tester, rig, TournamentScreen(id: id));
      final rising = tester.widgetList<YqSlideIn>(find.descendant(of: find.byType(CompetitorRow), matching: find.byType(YqSlideIn)));
      expect(rising.where((s) => s.play).length, inInclusiveRange(1, 3));
    });

    testWidgets('level board: my pinned rank slides up with my ring drawing in; reduce-motion: it is simply there', (tester) async {
      final rig = CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())});
      await pump(tester, rig, const LeaderboardScreen());
      final pinned = find.ancestor(of: find.text('ترتيبك 4'), matching: find.byType(YqSlideIn));
      expect(pinned, findsOneWidget);
      expect(tester.widget<YqSlideIn>(pinned).offset, const Offset(0, 1.2));
      final mine = find.descendant(of: pinned, matching: find.byType(YqLevelAvatar));
      expect(tester.widget<YqLevelAvatar>(mine).drawIn, isNotNull);
      await tester.pumpWidget(const SizedBox());

      reduce(tester);
      await pump(tester, CommunityRig(routes: {'GET /v1/leaderboard': (_) => jsonResponse(board())}), const LeaderboardScreen());
      expect(find.text('ترتيبك 4'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('ترتيبك 4'), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
