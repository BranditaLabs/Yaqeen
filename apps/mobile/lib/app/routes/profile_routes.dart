import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/card/presentation/card_screen.dart';
import '../../features/profile/presentation/badges_screen.dart';
import '../../features/profile/presentation/downloads_screen.dart';
import '../../features/profile/presentation/ledger_screen.dart';
import '../../features/profile/presentation/privacy_screen.dart';
import '../../features/profile/presentation/profile_settings_screen.dart';

/// `/profile/*` (owned by the profile stream; router.dart only spreads this list).
List<RouteBase> profileRoutes(GlobalKey<NavigatorState> root) => [
      GoRoute(path: 'settings', builder: (_, __) => const ProfileSettingsScreen()),
      GoRoute(path: 'badges', builder: (_, __) => const BadgesScreen()),
      GoRoute(path: 'privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: 'ledger', builder: (_, __) => const LedgerScreen()),
      GoRoute(path: 'downloads', builder: (_, __) => const DownloadsScreen()),
      GoRoute(path: 'card', builder: (_, state) => CardScreen(tag: state.uri.queryParameters['tag'])),
    ];
