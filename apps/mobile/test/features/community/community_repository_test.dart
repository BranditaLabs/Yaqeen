import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/features/community/data/community_repository.dart';
import 'package:yaqeen/features/community/domain/community_models.dart';
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';

import 'community_rig.dart';

CommunityRepository repoOf(CommunityRig r) => CommunityRepository(api: r.api, store: r.kv, outbox: r.outbox);

void main() {
  group('reads: parse, cache, offline', () {
    test('league: parsed from the shared fixture, cached, then served offline with the flag', () async {
      final r = CommunityRig(routes: {'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_joined.json'))});
      final repo = repoOf(r);
      final fresh = await repo.leagueCurrent();
      expect(fresh.offline, isFalse);
      final j = fresh.value as LeagueJoined;
      expect(j.division, 3);
      expect(j.myLivePoints, 335);
      expect(j.rows.map((x) => x.rank), [1, 1, 3, 4, null]); // ties share a rank; 0 points → null
      expect(j.rows.where((x) => x.me).single.handle, 'ahmed-4821');
      expect(await r.kv.read(CommunityRepository.leagueKey), isNotNull);

      r.routes['GET /v1/leagues/current'] = (_) => offline();
      final cached = await repo.leagueCurrent();
      expect(cached.offline, isTrue);
      expect((cached.value as LeagueJoined).rows, hasLength(5));
    });

    test('closing and off states parse', () async {
      final r = CommunityRig(routes: {'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_closing.json'))});
      expect((await repoOf(r).leagueCurrent()).value, isA<LeagueClosing>());
      r.routes['GET /v1/leagues/current'] = (_) => jsonResponse(fixture('league_current_off.json'));
      expect((await repoOf(r).leagueCurrent()).value, isA<LeagueOff>());
    });

    test('offline with nothing cached: OfflineException (the screen shows its error state)', () async {
      final r = CommunityRig(routes: {'GET /v1/leagues/current': (_) => offline()});
      await expectLater(repoOf(r).leagueCurrent(), throwsA(isA<OfflineException>()));
    });

    test('a server code becomes a typed CommunityException', () async {
      final r = CommunityRig(routes: {
        'GET /v1/leagues/current': (_) => errorResponse(403, 'feature_off'),
        'GET /v1/leaderboard': (req) => req.url.queryParameters['scope'] == 'country'
            ? errorResponse(409, 'country_too_small')
            : errorResponse(409, 'country_unknown'),
      },);
      final repo = repoOf(r);
      await expectLater(
        repo.leagueCurrent(),
        throwsA(isA<CommunityException>().having((e) => e.failure, 'failure', CommunityFailure.featureOff)),
      );
      await expectLater(
        repo.leaderboard(LeaderboardScope.global),
        throwsA(isA<CommunityException>().having((e) => e.failure, 'failure', CommunityFailure.countryUnknown)),
      );
      await expectLater(
        repo.leaderboard(LeaderboardScope.country),
        throwsA(isA<CommunityException>().having((e) => e.failure, 'failure', CommunityFailure.countryTooSmall)),
      );
      expect(r.calls, contains('GET /v1/leaderboard?scope=country'));
    });

    test('every server code maps to its own failure; status fallbacks for 429/404', () {
      for (final f in CommunityFailure.serverCodes) {
        expect(CommunityRepository.failureOf(ApiException(400, f.code)), f);
      }
      expect(CommunityRepository.failureOf(ApiException(429, 'error')), CommunityFailure.rateLimited);
      expect(CommunityRepository.failureOf(ApiException(404, 'error')), CommunityFailure.notFound);
      expect(CommunityRepository.failureOf(ApiException(500, 'error')), CommunityFailure.unknown);
    });

    test('tournaments, one tournament, leaderboard and blocks are cached for offline viewing', () async {
      final list = fixture('tournaments.json') as List;
      final r = CommunityRig(routes: {
        'GET /v1/tournaments': (_) => jsonResponse(list),
        'GET /v1/leaderboard': (_) => jsonResponse(fixture('leaderboard.json')),
        'GET /v1/community/blocks': (_) => jsonResponse(fixture('blocks.json')),
        'GET /v1/tournaments/${(list[1] as Map)['id']}/standings': (_) => jsonResponse(fixture('standings.json')),
      },);
      final repo = repoOf(r);
      final ts = (await repo.tournaments()).value;
      expect(ts.map((x) => x.phase), [TournamentPhase.upcoming, TournamentPhase.live, TournamentPhase.ended]);
      final live = ts[1];
      final st = (await repo.standings(live.id)).value;
      expect(st.total, 214);
      expect(st.nextCursor, '100:omar-5521');
      expect(st.me!.rank, 17);
      final board = (await repo.leaderboard(LeaderboardScope.global)).value;
      expect(board.rows.every((x) => x.points == null), isTrue); // rings only
      expect((await repo.blocks()).value.map((b) => b.handle), ['member-x7k2p9', 'omar-5521']);

      r.offlineAll = true;
      expect((await repo.tournaments()).offline, isTrue);
      final one = await repo.tournament(live.id);
      expect(one.offline, isTrue);
      expect(one.value.me!.points, 640);
      expect((await repo.standings(live.id)).value.rows, hasLength(3));
      expect((await repo.leaderboard(LeaderboardScope.global)).offline, isTrue);
      expect((await repo.blocks()).value, hasLength(2));
      // Every key this repository writes is wiped with the profile.
      expect(ProfileRepository.wipedKeys, containsAll(CommunityRepository.keys));
    });

    test('standings pages: the cursor is sent, only the first page is cached', () async {
      final r = CommunityRig(routes: {'GET /v1/tournaments/t1/standings': (_) => jsonResponse(fixture('standings.json'))});
      final repo = repoOf(r);
      await repo.standings('t1');
      await repo.standings('t1', cursor: '100:omar-5521');
      expect(r.calls, ['GET /v1/tournaments/t1/standings', 'GET /v1/tournaments/t1/standings?cursor=100%3Aomar-5521']);
    });
  });

  group('tournament join and leave', () {
    final live = (fixture('tournaments.json') as List)[1] as Map<String, dynamic>;
    final id = live['id'] as String;

    test('join is a direct POST with acknowledge (+ attestAdult the first time), never the Outbox', () async {
      final r = CommunityRig(routes: {'POST /v1/tournaments/$id/join': (_) => jsonResponse(live)});
      final res = await repoOf(r).joinTournament(id, attestAdult: true);
      expect(res.isOk, isTrue);
      expect(r.bodies['POST /v1/tournaments/$id/join'], {'acknowledge': true, 'attestAdult': true});
      expect(await r.queued(), isEmpty);
    });

    test('join offline → offline failure; typed codes inline', () async {
      final r = CommunityRig(routes: {'POST /v1/tournaments/$id/join': (_) => offline()});
      expect((await repoOf(r).joinTournament(id)).errorOrNull, CommunityFailure.offline);
      expect(await r.queued(), isEmpty);
      for (final (status, code, f) in [
        (409, 'tournament_not_open', CommunityFailure.tournamentNotOpen),
        (400, 'ack_required', CommunityFailure.ackRequired),
        (400, 'attestation_required', CommunityFailure.attestationRequired),
        (403, 'community_banned', CommunityFailure.communityBanned),
        (400, 'name_required', CommunityFailure.nameRequired),
      ]) {
        r.routes['POST /v1/tournaments/$id/join'] = (_) => errorResponse(status, code);
        expect((await repoOf(r).joinTournament(id)).errorOrNull, f);
      }
    });

    test('leave offline: queued DELETE, and the cached tournament and standings drop the caller at once', () async {
      final r = CommunityRig(routes: {
        'GET /v1/tournaments': (_) => jsonResponse(fixture('tournaments.json')),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse({
              ...fixtureMap('standings.json'),
              'rows': [
                ...(fixtureMap('standings.json')['rows'] as List),
                (fixtureMap('standings.json')['me'] as Map),
              ],
            }),
        'DELETE /v1/tournaments/$id/join': (_) => offline(),
      },);
      final repo = repoOf(r);
      await repo.tournaments();
      await repo.standings(id);
      final shown = await repo.leaveTournament(id);
      expect(shown!.joined, isFalse);
      expect(shown.me, isNull);
      expect(shown.participants, 213);
      final q = await r.queued();
      expect(q.single.method, 'DELETE');
      expect(q.single.path, '/v1/tournaments/$id/join');

      r.offlineAll = true;
      expect((await repo.tournament(id)).value.joined, isFalse);
      final st = (await repo.standings(id)).value;
      expect(st.rows.where((x) => x.me), isEmpty);
      expect(st.me, isNull);
      // A second leave replaces the queued one.
      await repo.leaveTournament(id);
      expect(await r.queued(), hasLength(1));
    });

    test('leave offline, then join online, then flush: still joined (the stale DELETE is gone)', () async {
      final r = CommunityRig(routes: {
        'GET /v1/tournaments': (_) => jsonResponse(fixture('tournaments.json')),
        'DELETE /v1/tournaments/$id/join': (_) => offline(),
      },);
      final repo = repoOf(r);
      await repo.tournaments();
      await repo.leaveTournament(id);
      expect((await r.queued()).single.method, 'DELETE');

      r.routes['POST /v1/tournaments/$id/join'] = (_) => jsonResponse(live);
      r.routes['DELETE /v1/tournaments/$id/join'] = (_) => jsonResponse({...live, 'joined': false, 'me': null});
      expect((await repo.joinTournament(id)).isOk, isTrue);
      expect(await r.queued(), isEmpty);

      r.calls.clear();
      await r.outbox.flush((item) async => r.api.delete(item.path));
      expect(r.calls.where((c) => c.startsWith('DELETE')), isEmpty);
      expect((await repo.cachedTournaments())!.firstWhere((t) => t.id == id).joined, isTrue);
    });

    test('a failed join puts the queued leave back (the person stays left)', () async {
      final r = CommunityRig(routes: {'DELETE /v1/tournaments/$id/join': (_) => offline()});
      final repo = repoOf(r);
      await repo.leaveTournament(id);
      r.routes['POST /v1/tournaments/$id/join'] = (_) => errorResponse(409, 'tournament_not_open');
      expect((await repo.joinTournament(id)).errorOrNull, CommunityFailure.tournamentNotOpen);
      r.routes['POST /v1/tournaments/$id/join'] = (_) => offline();
      expect((await repo.joinTournament(id)).errorOrNull, CommunityFailure.offline);
      final q = await r.queued();
      expect(q.single.method, 'DELETE');
      expect(q.single.path, '/v1/tournaments/$id/join');
    });

    test('the community consent follows tournament entries on this phone', () async {
      final r = CommunityRig(routes: {
        'GET /v1/tournaments': (_) => jsonResponse([
              for (final t in fixture('tournaments.json') as List) {...(t as Map).cast<String, dynamic>(), 'joined': false, 'me': null},
            ]),
        'POST /v1/tournaments/$id/join': (_) => jsonResponse(live),
        'DELETE /v1/tournaments/$id/join': (_) => jsonResponse({...live, 'joined': false, 'me': null}),
      },);
      final consents = ConsentRepository(api: r.api, store: r.kv);
      final repo = CommunityRepository(api: r.api, store: r.kv, outbox: r.outbox, consents: consents);
      await repo.tournaments();
      expect(consents.granted(ConsentKind.community), isFalse);

      await repo.joinTournament(id);
      expect(consents.granted(ConsentKind.community), isTrue);

      // Still in the league (from the profile): the consent stays.
      await repo.leaveTournament(id, otherCompetitionsOn: true);
      expect(consents.granted(ConsentKind.community), isTrue);

      await repo.joinTournament(id);
      await repo.leaveTournament(id);
      expect(consents.granted(ConsentKind.community), isFalse);
    });

    test('leave online: one direct DELETE, nothing queued', () async {
      final r = CommunityRig(routes: {'DELETE /v1/tournaments/$id/join': (_) => jsonResponse({...live, 'joined': false, 'me': null})});
      final shown = await repoOf(r).leaveTournament(id);
      expect(shown!.joined, isFalse);
      expect(r.calls, ['DELETE /v1/tournaments/$id/join']);
      expect(await r.queued(), isEmpty);
    });
  });

  group('community joins vs a queued leave', () {
    const path = '/v1/me/community';

    Future<void> queueLeave(CommunityRig r, Map<String, dynamic> body) =>
        r.outbox.add(OutboxItem(id: 'leave-1', method: 'PUT', path: path, body: {...body, 'source': 'settings'}));

    test('a successful join takes its keys out of the queued leave; the rest stays queued', () async {
      final r = CommunityRig();
      await queueLeave(r, {'leagues': false, 'leaderboard': false, 'leaderboardCountry': false});
      final res = await repoOf(r).withoutQueuedLeave(leagues: true, join: () async => true, succeeded: (ok) => ok);
      expect(res, isTrue);
      final q = await r.queued();
      expect(q.single.body, {'leaderboard': false, 'leaderboardCountry': false, 'source': 'settings'});
    });

    test('a leave of only the joined key disappears; leave online then flush keeps the join', () async {
      final r = CommunityRig(routes: {'PUT $path': (_) => jsonResponse(const {})});
      await queueLeave(r, {'leagues': false});
      await repoOf(r).withoutQueuedLeave(leagues: true, join: () async => true, succeeded: (ok) => ok);
      expect(await r.queued(), isEmpty);
      await r.outbox.flush((item) async => r.api.put(item.path, item.body));
      expect(r.calls.where((c) => c.startsWith('PUT')), isEmpty);
    });

    test('a failed join puts the queued leave back unchanged', () async {
      final r = CommunityRig();
      await queueLeave(r, {'leagues': false, 'leaderboard': false, 'leaderboardCountry': false});
      await repoOf(r).withoutQueuedLeave(leaderboard: true, join: () async => false, succeeded: (ok) => ok);
      final q = await r.queued();
      expect(q.single.id, 'leave-1');
      expect(q.single.body, {'leagues': false, 'leaderboard': false, 'leaderboardCountry': false, 'source': 'settings'});
    });

    test('nothing queued for those keys: the join runs untouched', () async {
      final r = CommunityRig();
      await queueLeave(r, {'leagues': false});
      await repoOf(r).withoutQueuedLeave(leaderboard: true, join: () async => true, succeeded: (ok) => ok);
      expect((await r.queued()).single.body, {'leagues': false, 'source': 'settings'});
    });
  });

  group('report and block', () {
    test('report sends handle + reason; 429 → rate_limited', () async {
      final r = CommunityRig(routes: {'POST /v1/community/reports': (_) => jsonResponse(null, 204)});
      final repo = repoOf(r);
      expect((await repo.report('omar-5521', ReportReason.photo)).isOk, isTrue);
      expect(r.bodies['POST /v1/community/reports'], {'handle': 'omar-5521', 'reason': 'photo'});
      r.routes['POST /v1/community/reports'] = (_) => errorResponse(429, 'rate_limited');
      expect((await repo.report('omar-5521', ReportReason.name)).errorOrNull, CommunityFailure.rateLimited);
    });

    test('block removes the person from every cached list; unblock updates the cached blocks', () async {
      final r = CommunityRig(routes: {
        'GET /v1/leagues/current': (_) => jsonResponse(fixture('league_current_joined.json')),
        'GET /v1/leaderboard': (_) => jsonResponse(fixture('leaderboard.json')),
        'GET /v1/tournaments/t1/standings': (_) => jsonResponse(fixture('standings.json')),
        'POST /v1/community/blocks': (_) => jsonResponse(fixture('blocks.json')),
        'DELETE /v1/community/blocks/omar-5521': (_) => jsonResponse(null, 204),
      },);
      final repo = repoOf(r);
      await repo.leagueCurrent();
      await repo.leaderboard(LeaderboardScope.global);
      await repo.standings('t1');
      expect((await repo.block('omar-5521')).isOk, isTrue);
      expect(r.bodies['POST /v1/community/blocks'], {'handle': 'omar-5521'});

      r.offlineAll = true;
      final league = (await repo.leagueCurrent()).value as LeagueJoined;
      expect(league.rows.map((x) => x.handle), isNot(contains('omar-5521')));
      // Rank numbers keep their gaps (never recomputed on the phone).
      expect(league.rows.first.rank, 1);
      expect((await repo.leaderboard(LeaderboardScope.global)).value.rows.map((x) => x.handle), isNot(contains('omar-5521')));
      expect((await repo.standings('t1')).value.rows.map((x) => x.handle), isNot(contains('omar-5521')));

      r.offlineAll = false;
      expect((await repo.unblock('omar-5521')).isOk, isTrue);
      r.offlineAll = true;
      expect((await repo.blocks()).value.map((b) => b.handle), ['member-x7k2p9']);
    });

    test('block offline → offline failure, caches untouched', () async {
      final r = CommunityRig(routes: {'POST /v1/community/blocks': (_) => offline()});
      expect((await repoOf(r).block('omar-5521')).errorOrNull, CommunityFailure.offline);
    });
  });
}
