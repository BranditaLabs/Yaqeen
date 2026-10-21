import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/azkar/presentation/azkar_screen.dart';
import '../features/challenge/presentation/challenge_screen.dart';
import '../features/content/domain/content_item.dart';
import '../features/duas/presentation/duas_screen.dart';
import '../features/debug/gallery_screen.dart';
import '../features/home/home_screen.dart';
import '../features/hifz/presentation/hifz_screen.dart';
import '../features/listen/presentation/now_playing_screen.dart';
import '../features/listen/presentation/reciters_screen.dart';
import '../features/notifications/presentation/inbox_screen.dart';
import '../features/notifications/presentation/notification_settings_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/prayer/presentation/qibla_screen.dart';
import '../features/quran/presentation/quran_index_screen.dart';
import '../features/quran/presentation/reader_screen.dart';
import '../features/recite/presentation/recite_screen.dart';
import '../features/rewards/presentation/redeem_screen.dart';
import 'shell.dart';

/// Navigator for full-screen routes (reader, recitation, player, Qibla) — above the tab bar.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

Widget _todo(String title) => PlaceholderScreen(title: title);

/// Route map (spec §4.1). Each tab is a branch so it keeps its own stack.
/// Deep links map onto these paths in core/notifications/push_service.dart › routeForDeepLink.
GoRouter buildRouter({String initialLocation = '/home'}) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(
          path: '/onboarding',
          redirect: (_, s) => s.uri.path == '/onboarding' ? '/onboarding/welcome' : null,
          routes: [
            GoRoute(path: 'welcome', builder: (_, __) => _todo('welcome')),
            GoRoute(path: 'language', builder: (_, __) => _todo('language')),
            GoRoute(path: 'prayer', builder: (_, __) => _todo('prayer')),
            GoRoute(path: 'consent', builder: (_, __) => _todo('consent')),
            GoRoute(path: 'goal', builder: (_, __) => _todo('goal')),
            GoRoute(path: 'download', builder: (_, __) => _todo('download')),
          ],
        ),
        if (kDebugMode) GoRoute(path: '/debug/gallery', builder: (_, __) => const GalleryScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const HomeScreen(),
                  routes: [
                    GoRoute(path: 'azkar', builder: (_, s) => AzkarScreen(initial: ZikrSet.of(s.uri.queryParameters['set'] ?? ''))),
                    GoRoute(
                      path: 'duas',
                      builder: (_, __) => const DuasScreen(),
                      routes: [GoRoute(path: ':category', builder: (_, s) => DuaCategoryScreen(category: s.pathParameters['category']!))],
                    ),
                    GoRoute(path: 'inbox', builder: (_, __) => const InboxScreen()),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/quran',
                  builder: (_, __) => const QuranIndexScreen(),
                  routes: [
                    GoRoute(path: 'hifz', builder: (_, __) => const HifzScreen()),
                    GoRoute(path: 'reciters', builder: (_, __) => const RecitersScreen()),
                    GoRoute(
                      parentNavigatorKey: rootNavigatorKey,
                      path: 'read/:page',
                      builder: (_, s) => ReaderScreen(initialPage: (int.tryParse(s.pathParameters['page'] ?? '') ?? 1).clamp(1, 604)),
                    ),
                    GoRoute(
                      parentNavigatorKey: rootNavigatorKey,
                      path: 'recite/:surah',
                      builder: (_, s) => ReciteScreen(
                        surah: (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114),
                        from: int.tryParse(s.uri.queryParameters['from'] ?? ''),
                        to: int.tryParse(s.uri.queryParameters['to'] ?? ''),
                        fromHifz: s.uri.queryParameters['hifz'] == '1',
                      ),
                    ),
                    GoRoute(
                      parentNavigatorKey: rootNavigatorKey,
                      path: 'listen/:surah',
                      builder: (_, s) => NowPlayingScreen(
                        surah: (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114),
                        ayah: int.tryParse(s.uri.queryParameters['ayah'] ?? ''),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/prayer',
                  builder: (_, __) => _todo('prayer'),
                  routes: [
                    GoRoute(path: 'notifications', builder: (_, __) => const NotificationSettingsScreen()),
                    GoRoute(parentNavigatorKey: rootNavigatorKey, path: 'qibla', builder: (_, __) => const QiblaScreen()),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/challenge',
                  builder: (_, __) => const ChallengeScreen(),
                  routes: [
                    GoRoute(path: 'calendar', builder: (_, __) => _todo('calendar')),
                    GoRoute(path: 'redeem', builder: (_, __) => const RedeemScreen()),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/profile', builder: (_, __) => _todo('profile')),
              ],
            ),
          ],
        ),
      ],
    );

final appRouter = buildRouter();
