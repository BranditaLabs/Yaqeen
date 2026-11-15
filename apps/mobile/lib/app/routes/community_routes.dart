import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/community/presentation/community_settings_screen.dart';
import '../../features/community/presentation/leaderboard_screen.dart';
import '../../features/community/presentation/league_screen.dart';
import '../../features/community/presentation/tournament_screen.dart';
import '../../features/community/presentation/tournaments_screen.dart';

/// `/profile/leagues`, `/profile/tournaments[/:id]`, `/profile/leaderboard`, `/profile/community`
/// (APP_SPEC §5.31; owned by the competitions stream; router.dart only spreads this list).
List<RouteBase> communityRoutes(GlobalKey<NavigatorState> root) => [
      GoRoute(path: 'leagues', builder: (_, __) => const LeagueScreen()),
      GoRoute(
        path: 'tournaments',
        builder: (_, __) => const TournamentsScreen(),
        routes: [GoRoute(path: ':id', builder: (_, s) => TournamentScreen(id: s.pathParameters['id']!))],
      ),
      GoRoute(path: 'leaderboard', builder: (_, __) => const LeaderboardScreen()),
      GoRoute(path: 'community', builder: (_, __) => const CommunitySettingsScreen()),
    ];
