import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/storage/kv_store.dart';
import '../../onboarding/data/consent_repository.dart';
import '../domain/community_models.dart';

/// A read that may come from this phone's cache: [offline] when the network could not be reached
/// and [value] is the last view seen (the screen shows `YqOfflineBanner`).
class Fresh<T> {
  const Fresh(this.value, {this.offline = false});
  final T value;
  final bool offline;
}

/// A read the server refused with a community code (`feature_off`, `country_unknown`,
/// `country_too_small`, `community_banned`, `not_found`, …): the screen shows a typed state.
class CommunityException implements Exception {
  const CommunityException(this.failure);
  final CommunityFailure failure;

  @override
  String toString() => 'CommunityException(${failure.code})';
}

/// The app's [CommunityRepository].
final communityRepositoryProvider = Provider(
  (ref) => CommunityRepository(
    api: ref.watch(apiClientProvider),
    store: ref.watch(kvStoreProvider),
    outbox: ref.watch(outboxProvider),
    consents: ref.watch(consentRepositoryProvider),
  ),
);

/// The opt-in community (APP_SPEC §5.31, design §3.3/§6.6–6.10): leagues, tournaments, the level
/// board, blocks and reports.
///
/// * Every public list is the server's **nightly snapshot**; nothing here is live except the
///   caller's own totals, which the server sends for the caller only.
/// * Reads are cached in the KV store (`community.*`, wiped with the profile) so the last view can
///   be seen offline.
/// * Joining a tournament is a **direct** call (offline → [CommunityFailure.offline]); leaving is
///   direct when online and queued in the [Outbox] otherwise, and the cached views drop the caller
///   at once either way.
/// * League/leaderboard joins and leaves go through `meProfileProvider` (ProfileRepository);
///   [withoutQueuedLeave] keeps a stale queued leave from undoing such a join.
/// * An active tournament entry grants the server-side `community` consent (design §1.3): joins
///   and leaves here adopt it on this phone too.
class CommunityRepository {
  CommunityRepository({required this.api, required this.store, required this.outbox, this.consents});

  final ApiClient api;
  final KvStore store;
  final Outbox outbox;
  final ConsentRepository? consents;

  static const communityPath = '/v1/me/community';
  static String joinPath(String id) => '/v1/tournaments/$id/join';

  static const leagueKey = 'community.league.v1';
  static const historyKey = 'community.league.history.v1';

  /// The tournaments list plus the first standings page of each tournament opened
  /// (`{"list": [...], "standings": {id: page}}`).
  static const tournamentsKey = 'community.tournaments.v1';
  static const blocksKey = 'community.blocks.v1';
  static String leaderboardKey(LeaderboardScope scope) => 'community.leaderboard.${scope.name}.v1';

  /// Every key this repository writes (each one is also in `ProfileRepository.wipedKeys`).
  static List<String> get keys => [
        leagueKey,
        historyKey,
        tournamentsKey,
        blocksKey,
        for (final s in LeaderboardScope.values) leaderboardKey(s),
      ];

  /* ------------------------------------------------------------------ helpers */

  static CommunityFailure failureOf(ApiException e) {
    final byCode = CommunityFailure.fromCode(e.code);
    if (byCode != CommunityFailure.unknown) return byCode;
    return switch (e.status) {
      429 => CommunityFailure.rateLimited,
      404 => CommunityFailure.notFound,
      _ => CommunityFailure.unknown,
    };
  }

  Future<Object?> _readJson(String key) async {
    final raw = await store.read(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(String key, Object? value) => store.write(key, jsonEncode(value));

  /// Network first; offline → [cached] (or rethrows [OfflineException] when there is none); a
  /// server code → [CommunityException].
  Future<Fresh<T>> _fetch<T>(Future<T> Function() network, Future<T?> Function() cached) async {
    try {
      return Fresh(await network());
    } on OfflineException {
      final c = await cached();
      if (c == null) rethrow;
      return Fresh(c, offline: true);
    } on ApiException catch (e) {
      throw CommunityException(failureOf(e));
    }
  }

  /* ------------------------------------------------------------------- league */

  Future<LeagueCurrent?> cachedLeague() async {
    final j = await _readJson(leagueKey);
    if (j is! Map) return null;
    try {
      return LeagueCurrent.fromJson(j.cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  /// GET /v1/leagues/current.
  Future<Fresh<LeagueCurrent>> leagueCurrent() => _fetch(() async {
        final j = (await api.get('/v1/leagues/current') as Map).cast<String, dynamic>();
        final league = LeagueCurrent.fromJson(j);
        await _writeJson(leagueKey, league.toJson());
        return league;
      }, cachedLeague,);

  /// After leaving (Outbox): the cached league says «off» at once.
  Future<void> markLeagueLeft() => _writeJson(leagueKey, const LeagueOff().toJson());

  Future<List<LeagueHistoryItem>?> _cachedHistory() async {
    final j = await _readJson(historyKey);
    if (j is! List) return null;
    return [for (final e in j) LeagueHistoryItem.fromJson((e as Map).cast<String, dynamic>())];
  }

  /// GET /v1/leagues/history (last 12 weeks).
  Future<Fresh<List<LeagueHistoryItem>>> leagueHistory() => _fetch(() async {
        final list = await api.get('/v1/leagues/history') as List;
        final items = [for (final e in list) LeagueHistoryItem.fromJson((e as Map).cast<String, dynamic>())];
        await _writeJson(historyKey, [for (final i in items) i.toJson()]);
        return items;
      }, _cachedHistory,);

  /* -------------------------------------------------------------- tournaments */

  Future<Map<String, dynamic>> _tournamentsCache() async {
    final j = await _readJson(tournamentsKey);
    return j is Map ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<Tournament>?> cachedTournaments() async {
    final c = await _tournamentsCache();
    if (c['list'] is! List) return null;
    return Tournament.listFrom(c['list']);
  }

  Future<void> _saveTournaments(List<Tournament> list) async {
    final c = await _tournamentsCache();
    c['list'] = [for (final t in list) t.toJson()];
    await _writeJson(tournamentsKey, c);
  }

  /// Replaces (or adds) one tournament in the cached list.
  Future<void> _saveTournament(Tournament t) async {
    final list = await cachedTournaments() ?? const <Tournament>[];
    final i = list.indexWhere((x) => x.id == t.id);
    await _saveTournaments(i < 0 ? [...list, t] : [...list.sublist(0, i), t, ...list.sublist(i + 1)]);
  }

  /// GET /v1/tournaments (published: live, upcoming, ended in the last 30 days).
  Future<Fresh<List<Tournament>>> tournaments() => _fetch(() async {
        final list = Tournament.listFrom(await api.get('/v1/tournaments'));
        await _saveTournaments(list);
        return list;
      }, cachedTournaments,);

  Future<Tournament?> _cachedTournament(String id) async {
    for (final t in await cachedTournaments() ?? const <Tournament>[]) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// GET /v1/tournaments/:id.
  Future<Fresh<Tournament>> tournament(String id) => _fetch(() async {
        final t = Tournament.fromJson((await api.get('/v1/tournaments/$id') as Map).cast<String, dynamic>());
        await _saveTournament(t);
        return t;
      }, () => _cachedTournament(id),);

  Future<TournamentStandings?> cachedStandings(String id) async {
    final s = (await _tournamentsCache())['standings'];
    final page = s is Map ? s[id] : null;
    return page is Map ? TournamentStandings.fromJson(page.cast<String, dynamic>()) : null;
  }

  /// GET /v1/tournaments/:id/standings?cursor= — snapshot pages of 100. The first page is cached.
  Future<Fresh<TournamentStandings>> standings(String id, {String? cursor}) => _fetch(() async {
        final j = (await api.get('/v1/tournaments/$id/standings', query: cursor == null ? null : {'cursor': cursor}) as Map)
            .cast<String, dynamic>();
        if (cursor == null) {
          final c = await _tournamentsCache();
          c['standings'] = {...(c['standings'] as Map? ?? const {}), id: j};
          await _writeJson(tournamentsKey, c);
        }
        return TournamentStandings.fromJson(j);
      }, () async => cursor == null ? cachedStandings(id) : null,);

  /// POST /v1/tournaments/:id/join `{acknowledge: true, attestAdult?}` — always direct.
  ///
  /// A leave of this tournament still waiting in the Outbox is taken out first (and put back if
  /// the join fails), so it can never flush after the join and silently remove the person.
  Future<Result<Tournament, CommunityFailure>> joinTournament(String id, {bool attestAdult = false}) async {
    final path = joinPath(id);
    final stale = [for (final i in await outbox.items()) if (i.method == 'DELETE' && i.path == path) i];
    if (stale.isNotEmpty) await outbox.removeWhere((i) => i.method == 'DELETE' && i.path == path);
    Future<void> restore() async {
      for (final i in stale) {
        await outbox.add(i);
      }
    }

    try {
      final j = await api.post(path, {'acknowledge': true, if (attestAdult) 'attestAdult': true});
      final t = Tournament.fromJson((j as Map).cast<String, dynamic>());
      await _saveTournament(t);
      // The entry grants the community consent on the server; mirror it here.
      await consents?.adopt(ConsentKind.community, true);
      return Ok(t);
    } on OfflineException {
      await restore();
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      await restore();
      return Err(failureOf(e));
    }
  }

  /// DELETE /v1/tournaments/:id/join — direct when online, queued otherwise. The cached tournament
  /// and its cached standings drop the caller at once. Returns the tournament as now shown.
  ///
  /// The `community` consent is re-adopted as the server recomputes it: still granted while
  /// [otherCompetitionsOn] (the league or a board, from the profile) or another active entry.
  Future<Tournament?> leaveTournament(String id, {bool otherCompetitionsOn = false}) async {
    final cached = await _cachedTournament(id);
    Tournament? shown = cached == null ? null : withoutMe(cached);
    if (shown != null) await _saveTournament(shown);
    await _dropMeFromStandings(id);
    final others = (await cachedTournaments() ?? const <Tournament>[])
        .any((t) => t.id != id && t.joined && !t.closed && t.phase != TournamentPhase.ended);
    await consents?.adopt(ConsentKind.community, otherCompetitionsOn || others);
    final path = joinPath(id);
    try {
      final j = await api.delete(path);
      if (j is Map) {
        shown = Tournament.fromJson(j.cast<String, dynamic>());
        await _saveTournament(shown);
      }
    } on OfflineException {
      await _queueLeave(path);
    } on ApiException catch (e) {
      if (!e.isPermanent || e.status == 401) await _queueLeave(path);
    }
    return shown;
  }

  /// Runs a competition join ([join], the direct PUT /v1/me/community) with the keys it turns on
  /// taken out of any community leave still waiting in the Outbox — otherwise that stale leave
  /// would flush after the join and turn the competition off again. The keys are put back when
  /// the join fails (the person stays left).
  Future<R> withoutQueuedLeave<R>({
    bool leagues = false,
    bool leaderboard = false,
    bool leaderboardCountry = false,
    required Future<R> Function() join,
    required bool Function(R result) succeeded,
  }) async {
    final keys = {if (leagues) 'leagues', if (leaderboard) 'leaderboard', if (leaderboardCountry) 'leaderboardCountry'};
    bool isLeave(OutboxItem i) => i.method == 'PUT' && i.path == communityPath;
    final queued = [for (final i in await outbox.items()) if (isLeave(i)) i];
    final touched = queued.where((i) => (i.body ?? const {}).keys.any(keys.contains)).toList();
    if (touched.isEmpty) return join();

    await outbox.removeWhere((i) => touched.any((t) => t.id == i.id));
    for (final i in touched) {
      final rest = {...?i.body}..removeWhere((k, _) => keys.contains(k));
      if (rest.keys.any((k) => k != 'source')) {
        await outbox.add(OutboxItem(id: i.id, method: i.method, path: i.path, body: rest, createdAt: i.createdAt));
      }
    }
    final r = await join();
    if (!succeeded(r)) {
      await outbox.removeWhere((i) => touched.any((t) => t.id == i.id));
      for (final i in touched) {
        await outbox.add(i);
      }
    }
    return r;
  }

  Future<void> _queueLeave(String path) async {
    await outbox.removeWhere((i) => i.method == 'DELETE' && i.path == path);
    await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'DELETE', path: path));
  }

  /// [t] as shown once the caller left it.
  static Tournament withoutMe(Tournament t) => Tournament.fromJson({
        ...t.toJson(),
        'joined': false,
        'me': null,
        'participants': t.joined && t.participants > 0 ? t.participants - 1 : t.participants,
      });

  Future<void> _dropMeFromStandings(String id) async {
    final c = await _tournamentsCache();
    final s = c['standings'];
    if (s is! Map || s[id] is! Map) return;
    final page = (s[id] as Map).cast<String, dynamic>();
    page['rows'] = [for (final r in (page['rows'] as List? ?? const [])) if ((r as Map)['me'] != true) r];
    page['me'] = null;
    c['standings'] = {...s, id: page};
    await _writeJson(tournamentsKey, c);
  }

  /* -------------------------------------------------------------- leaderboard */

  Future<LeaderboardView?> cachedLeaderboard(LeaderboardScope scope) async {
    final j = await _readJson(leaderboardKey(scope));
    return j is Map ? LeaderboardView.fromJson(j.cast<String, dynamic>()) : null;
  }

  /// GET /v1/leaderboard?scope= — top 100 + me (rings only). `country_unknown` /
  /// `country_too_small` come back as [CommunityException].
  Future<Fresh<LeaderboardView>> leaderboard(LeaderboardScope scope) => _fetch(() async {
        final j = (await api.get('/v1/leaderboard', query: {'scope': scope.name}) as Map).cast<String, dynamic>();
        final view = LeaderboardView.fromJson(j);
        await _writeJson(leaderboardKey(scope), view.toJson());
        return view;
      }, () => cachedLeaderboard(scope),);

  /* ------------------------------------------------------------------- safety */

  Future<List<BlockedUser>?> _cachedBlocks() async {
    final j = await _readJson(blocksKey);
    return j is List ? BlockedUser.listFrom(j) : null;
  }

  Future<void> _saveBlocks(List<BlockedUser> list) => _writeJson(blocksKey, [
        for (final b in list) {'handle': b.handle, 'name': b.name, 'avatar': b.avatar.toJson()},
      ]);

  /// GET /v1/community/blocks.
  Future<Fresh<List<BlockedUser>>> blocks() => _fetch(() async {
        final list = BlockedUser.listFrom(await api.get('/v1/community/blocks'));
        await _saveBlocks(list);
        return list;
      }, _cachedBlocks,);

  /// POST /v1/community/reports — 204; idempotent while open; 20 a day (`rate_limited`).
  Future<Result<void, CommunityFailure>> report(String handle, ReportReason reason) async {
    try {
      await api.post('/v1/community/reports', {'handle': handle, 'reason': reason.name});
      return const Ok(null);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      return Err(failureOf(e));
    }
  }

  /// POST /v1/community/blocks. On success the person leaves every cached list here too.
  Future<Result<void, CommunityFailure>> block(String handle) async {
    try {
      final j = await api.post('/v1/community/blocks', {'handle': handle});
      if (j is List) await _saveBlocks(BlockedUser.listFrom(j));
      await _dropFromCaches(handle);
      return const Ok(null);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      return Err(failureOf(e));
    }
  }

  /// DELETE /v1/community/blocks/:handle.
  Future<Result<void, CommunityFailure>> unblock(String handle) async {
    try {
      await api.delete('/v1/community/blocks/${Uri.encodeComponent(handle)}');
      final list = await _cachedBlocks();
      if (list != null) await _saveBlocks([for (final b in list) if (b.handle != handle) b]);
      return const Ok(null);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      return Err(failureOf(e));
    }
  }

  /// A blocked person disappears from the cached league, standings and boards (rank numbers keep
  /// their gaps — the server's ranks are never recomputed here).
  Future<void> _dropFromCaches(String handle) async {
    bool keep(Object? r) => r is Map && r['handle'] != handle;
    final league = await _readJson(leagueKey);
    if (league is Map && league['rows'] is List) {
      await _writeJson(leagueKey, {...league, 'rows': (league['rows'] as List).where(keep).toList()});
    }
    for (final s in LeaderboardScope.values) {
      final b = await _readJson(leaderboardKey(s));
      if (b is Map && b['rows'] is List) {
        await _writeJson(leaderboardKey(s), {...b, 'rows': (b['rows'] as List).where(keep).toList()});
      }
    }
    final c = await _tournamentsCache();
    final st = c['standings'];
    if (st is Map) {
      c['standings'] = {
        for (final e in st.entries)
          e.key: e.value is Map ? {...(e.value as Map), 'rows': ((e.value as Map)['rows'] as List? ?? const []).where(keep).toList()} : e.value,
      };
      await _writeJson(tournamentsKey, c);
    }
  }
}
