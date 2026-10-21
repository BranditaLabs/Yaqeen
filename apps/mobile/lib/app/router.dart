import 'package:go_router/go_router.dart';

import '../features/challenge/presentation/challenge_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/rewards/presentation/redeem_screen.dart';
import 'shell.dart';

/// Routes. Each tab is a branch so it keeps its own navigation stack.
/// Deep links (`yaqeen://…` from pushes) map to these paths in
/// core/notifications/push_service.dart › routeForDeepLink.
GoRouter buildRouter({String initialLocation = '/home'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            ],),
            StatefulShellBranch(routes: [
              GoRoute(path: '/quran', builder: (_, __) => const PlaceholderScreen(titleKey: PlaceholderTitle.quran)),
            ],),
            StatefulShellBranch(routes: [
              GoRoute(path: '/prayer', builder: (_, __) => const PlaceholderScreen(titleKey: PlaceholderTitle.prayer)),
            ],),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/challenge',
                builder: (_, __) => const ChallengeScreen(),
                routes: [
                  GoRoute(path: 'redeem', builder: (_, __) => const RedeemScreen()),
                ],
              ),
            ],),
            StatefulShellBranch(routes: [
              GoRoute(path: '/profile', builder: (_, __) => const PlaceholderScreen(titleKey: PlaceholderTitle.profile)),
            ],),
          ],
        ),
      ],
    );

final appRouter = buildRouter();
