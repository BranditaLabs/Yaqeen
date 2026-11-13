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

/// GET /v1/tournaments.
final tournamentsProvider = StreamProvider.autoDispose<Fresh<List<Tournament>>>((ref) async* {
  final repo = ref.watch(communityRepositoryProvider);
  if (!ref.watch(sessionProvider).canEarnPoints) {
    yield Fresh(await repo.cachedTournaments() ?? const <Tournament>[]);
    return;
  }
  yield* _cachedThenFresh(repo.cachedTournaments, repo.tournaments);
});

/// GET /v1/tournaments/:id.
final tournamentProvider = StreamProvider.autoDispose.family<Fresh<Tournament>, String>((ref, id) async* {
  final repo = ref.watch(communityRepositoryProvider);
  final cached = (await repo.cachedTournaments())?.where((t) => t.id == id).firstOrNull;
  if (cached != null) yield Fresh(cached);
  yield await repo.tournament(id);
});

/// GET /v1/leaderboard?scope=.
final leaderboardProvider = StreamProvider.autoDispose.family<Fresh<LeaderboardView>, LeaderboardScope>((ref, scope) async* {
  final repo = ref.watch(communityRepositoryProvider);
  yield await repo.leaderboard(scope);
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
    this.offline = false,
  });
  final List<PublicCompetitor> rows;
  final int total;
  final String? snapshotDay;
  final PublicCompetitor? me;
  final String? nextCursor;
  final bool loadingMore;
  final bool offline;

  StandingsPage copyWith({List<PublicCompetitor>? rows, String? nextCursor, bool clearCursor = false, bool? loadingMore}) => StandingsPage(
        rows: rows ?? this.rows,
        total: total,
        snapshotDay: snapshotDay,
        me: me,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        offline: offline,
      );
}

class StandingsController extends AutoDisposeFamilyAsyncNotifier<StandingsPage, String> {
  @override
  Future<StandingsPage> build(String arg) async {
    final f = await ref.watch(communityRepositoryProvider).standings(arg);
    final s = f.value;
    return StandingsPage(
      rows: s.rows,
      total: s.total,
      snapshotDay: s.snapshotDay,
      me: s.me,
      nextCursor: f.offline ? null : s.nextCursor,
      offline: f.offline,
    );
  }

  /// The next page, once at a time; a failure keeps the cursor for the next try.
  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || cur.nextCursor == null || cur.loadingMore) return;
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
      state = AsyncData(cur.copyWith(loadingMore: false));
    }
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

/// Leaves the weekly league: queued (Outbox) and gone from this phone's views at once.
Future<void> leaveLeague(WidgetRef ref) async {
  await ref.read(meProfileProvider.notifier).leave(leagues: true);
  await ref.read(communityRepositoryProvider).markLeagueLeft();
  ref.invalidate(leagueProvider);
}

/// Leaves a tournament: direct when online, else queued; hidden here at once.
Future<void> leaveTournament(WidgetRef ref, String id) async {
  await ref.read(communityRepositoryProvider).leaveTournament(id);
  ref
    ..invalidate(tournamentProvider(id))
    ..invalidate(standingsProvider(id))
    ..invalidate(tournamentsProvider);
}
