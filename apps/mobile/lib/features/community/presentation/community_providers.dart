import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/presentation/session_controller.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';

/// Controllers for the community screens: every read paints the cached view first (when there is
/// one), then the fresh one; offline it stays on the cache with `Fresh.offline` (the banner).
/// A server code (`feature_off`, `country_unknown`, …) arrives as a [CommunityException] error.
Stream<Fresh<T>> _cachedThenFresh<T>(Future<T?> Function() cached, Future<Fresh<T>> Function() fresh) async* {
  final c = await cached();
  if (c != null) yield Fresh(c);
  yield await fresh();
}

/// GET /v1/leagues/current. Guests never reach the network.
final leagueProvider = StreamProvider.autoDispose<Fresh<LeagueCurrent>>((ref) async* {
  if (!ref.watch(sessionProvider).canEarnPoints) {
    yield const Fresh(LeagueOff());
    return;
  }
  final repo = ref.watch(communityRepositoryProvider);
  yield* _cachedThenFresh(repo.cachedLeague, repo.leagueCurrent);
});

/// GET /v1/leagues/history (last 12 weeks).
final leagueHistoryProvider = FutureProvider.autoDispose<Fresh<List<LeagueHistoryItem>>>((ref) {
  if (!ref.watch(sessionProvider).canEarnPoints) return const Fresh(<LeagueHistoryItem>[]);
  return ref.watch(communityRepositoryProvider).leagueHistory();
});

/// Tournaments left on this phone during this session: shown without the caller at once, before
/// (and regardless of) the network — a fresh read racing the DELETE can never bring them back.
/// A new join takes the id out again.
class LeftTournaments extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};
  void remove(String id) => state = {...state}..remove(id);
}

final leftTournamentsProvider = NotifierProvider<LeftTournaments, Set<String>>(LeftTournaments.new);

Fresh<Tournament> _applyLeft(Fresh<Tournament> f, Set<String> left) =>
    left.contains(f.value.id) && f.value.joined ? Fresh(CommunityRepository.withoutMe(f.value), offline: f.offline) : f;

/// GET /v1/tournaments.
final tournamentsProvider = StreamProvider.autoDispose<Fresh<List<Tournament>>>((ref) async* {
  final repo = ref.watch(communityRepositoryProvider);
  final left = ref.watch(leftTournamentsProvider);
  Fresh<List<Tournament>> apply(Fresh<List<Tournament>> f) => left.isEmpty
      ? f
      : Fresh([for (final t in f.value) _applyLeft(Fresh(t), left).value], offline: f.offline);
  if (!ref.watch(sessionProvider).canEarnPoints) {
    yield Fresh(await repo.cachedTournaments() ?? const <Tournament>[]);
    return;
  }
  yield* _cachedThenFresh(repo.cachedTournaments, repo.tournaments).map(apply);
});

/// GET /v1/tournaments/:id.
final tournamentProvider = StreamProvider.autoDispose.family<Fresh<Tournament>, String>((ref, id) async* {
  final repo = ref.watch(communityRepositoryProvider);
  final left = ref.watch(leftTournamentsProvider);
  final cached = (await repo.cachedTournaments())?.where((t) => t.id == id).firstOrNull;
  if (cached != null) yield _applyLeft(Fresh(cached), left);
  yield _applyLeft(await repo.tournament(id), left);
});

/// GET /v1/leaderboard?scope=. The cached board paints first; `country_unknown` and
/// `country_too_small` come only from the fresh read (as [CommunityException]).
final leaderboardProvider = StreamProvider.autoDispose.family<Fresh<LeaderboardView>, LeaderboardScope>((ref, scope) async* {
  // Guests never reach the network: an empty board (the screen shows the sign-in state).
  if (!ref.watch(sessionProvider).canEarnPoints) {
    yield Fresh(LeaderboardView(scope: scope, country: null, snapshotDay: null, joined: false, countryJoined: false, rows: const [], me: null));
    return;
  }
  final repo = ref.watch(communityRepositoryProvider);
  yield* _cachedThenFresh(() => repo.cachedLeaderboard(scope), () => repo.leaderboard(scope));
});

/// GET /v1/community/blocks.
final blocksProvider = FutureProvider.autoDispose<Fresh<List<BlockedUser>>>((ref) {
  if (!ref.watch(sessionProvider).canEarnPoints) return const Fresh(<BlockedUser>[]);
  return ref.watch(communityRepositoryProvider).blocks();
});

/* ------------------------------------------------------------------ standings */

/// The standings pages loaded so far (snapshot ranks, 100 a page).
class StandingsPage {
  const StandingsPage({
    required this.rows,
    required this.total,
    required this.snapshotDay,
    required this.me,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadFailed = false,
    this.offline = false,
  });

  factory StandingsPage.of(TournamentStandings s, {bool offline = false, bool withCursor = true}) => StandingsPage(
        rows: s.rows,
        total: s.total,
        snapshotDay: s.snapshotDay,
        me: s.me,
        nextCursor: offline || !withCursor ? null : s.nextCursor,
        offline: offline,
      );

  final List<PublicCompetitor> rows;
  final int total;
  final String? snapshotDay;
  final PublicCompetitor? me;
  final String? nextCursor;
  final bool loadingMore;

  /// The last page fetch failed (offline, a 5xx): nothing loads by itself until the person taps
  /// «إعادة المحاولة» ([StandingsController.retryMore]).
  final bool loadFailed;
  final bool offline;

  StandingsPage copyWith({
    List<PublicCompetitor>? rows,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? loadFailed,
    bool? offline,
  }) =>
      StandingsPage(
        rows: rows ?? this.rows,
        total: total,
        snapshotDay: snapshotDay,
        me: me,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        loadFailed: loadFailed ?? this.loadFailed,
        offline: offline ?? this.offline,
      );
}

class StandingsController extends AutoDisposeFamilyAsyncNotifier<StandingsPage, String> {
  /// Bumped on every build, so a refresh from an earlier build never overwrites a newer state.
  int _generation = 0;

  /// Cached-then-fresh: the cached first page paints at once (no cursor until the fresh page
  /// arrives), then the fresh first page replaces it; offline it stays with the banner.
  @override
  Future<StandingsPage> build(String arg) async {
    final generation = ++_generation;
    var alive = true;
    ref.onDispose(() => alive = false);
    final repo = ref.watch(communityRepositoryProvider);
    final cached = await repo.cachedStandings(arg);
    if (cached == null) {
      final f = await repo.standings(arg);
      return StandingsPage.of(f.value, offline: f.offline);
    }
    // After this build has returned the cached page (an event-queue turn later), never before.
    unawaited(Future(() async {
      bool current() => alive && generation == _generation;
      try {
        // Offline the repository answers with the cached page and `offline` (the banner).
        final f = await repo.standings(arg);
        if (current()) state = AsyncData(StandingsPage.of(f.value, offline: f.offline));
      } on Object {
        // A server error keeps the cached page as it is.
      }
    }),);
    return StandingsPage.of(cached, withCursor: false);
  }

  /// The next page, once at a time. A failure keeps the cursor and sets [StandingsPage.loadFailed]:
  /// the list stops asking until [retryMore].
  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || cur.nextCursor == null || cur.loadingMore || cur.loadFailed) return;
    state = AsyncData(cur.copyWith(loadingMore: true));
    try {
      final next = (await ref.read(communityRepositoryProvider).standings(arg, cursor: cur.nextCursor)).value;
      final seen = {for (final r in cur.rows) r.handle};
      state = AsyncData(cur.copyWith(
        rows: [...cur.rows, ...next.rows.where((r) => !seen.contains(r.handle))],
        nextCursor: next.nextCursor,
        clearCursor: next.nextCursor == null,
        loadingMore: false,
      ),);
    } on Object {
      state = AsyncData(cur.copyWith(loadingMore: false, loadFailed: true));
    }
  }

  /// The person asked again after a failed page.
  Future<void> retryMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.loadFailed) return;
    state = AsyncData(cur.copyWith(loadFailed: false));
    await loadMore();
  }
}

final standingsProvider =
    AsyncNotifierProvider.autoDispose.family<StandingsController, StandingsPage, String>(StandingsController.new);

/* ---------------------------------------------------------- local hide (blocks) */

/// People blocked on this phone during this session: hidden from every list at once, before the
/// server's answer (and kept hidden after it).
class HiddenHandles extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hide(String handle) => state = {...state, handle};
  void unhide(String handle) => state = {...state}..remove(handle);
}

final hiddenHandlesProvider = NotifierProvider<HiddenHandles, Set<String>>(HiddenHandles.new);

/* ------------------------------------------------------------------- actions */

/// Joins the weekly league or a board ([update], a direct PUT /v1/me/community through
/// `meProfileProvider`) after taking the keys it turns on out of any leave still queued.
Future<Result<CommunitySettings, CommunityFailure>> joinCommunity(WidgetRef ref, CommunityUpdate update) =>
    ref.read(communityRepositoryProvider).withoutQueuedLeave(
          leagues: update.leagues ?? false,
          leaderboard: update.leaderboard ?? false,
          leaderboardCountry: update.leaderboardCountry ?? false,
          join: () => ref.read(meProfileProvider.notifier).join(update),
          succeeded: (r) => r.isOk,
        );

/// Leaves the weekly league: queued (Outbox) and gone from this phone's views at once.
Future<void> leaveLeague(WidgetRef ref) async {
  await ref.read(meProfileProvider.notifier).leave(leagues: true);
  await ref.read(communityRepositoryProvider).markLeagueLeft();
  ref.invalidate(leagueProvider);
}

/// Leaves a tournament: hidden here at once (before any network), then direct when online, else
/// queued.
Future<void> leaveTournament(WidgetRef ref, String id) async {
  ref.read(leftTournamentsProvider.notifier).add(id);
  final anyOn = ref.read(meProfileProvider).valueOrNull?.community.anyOn ?? false;
  await ref.read(communityRepositoryProvider).leaveTournament(id, otherCompetitionsOn: anyOn);
  ref
    ..invalidate(tournamentProvider(id))
    ..invalidate(standingsProvider(id))
    ..invalidate(tournamentsProvider);
}
