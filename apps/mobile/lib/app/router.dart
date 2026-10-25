import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/azkar/presentation/azkar_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
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
import '../features/onboarding/presentation/onboarding_screens.dart';
import '../features/onboarding/presentation/splash_gate.dart';
import '../features/prayer/presentation/prayer_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/prayer/presentation/qibla_screen.dart';
import '../features/quran/presentation/quran_index_screen.dart';
import '../features/quran/presentation/reader_screen.dart';
import '../features/recite/presentation/recite_screen.dart';
import '../features/rewards/presentation/redeem_screen.dart';
import '../core/notifications/push_service.dart';
import 'shell.dart';

/// Navigator for full-screen routes (reader, recitation, player, Qibla) — above the tab bar.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Route map (spec §4.1). Each tab is a branch so it keeps its own stack.
/// Deep links map onto these paths in core/notifications/push_service.dart › routeForDeepLink.
GoRouter buildRouter({String initialLocation = '/home'}) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: initialLocation,
      // Universal / App Links arrive as /app/<target> (spec §4.2): through the splash, so a cold
      // start still warms up and a first launch still onboards before landing on the target.
      redirect: (_, s) =>
          s.uri.path.startsWith('/app/') ? Uri(path: '/splash', queryParameters: {'to': routeForDeepLink(s.uri)}).toString() : null,
      routes: [
        GoRoute(path: '/splash', builder: (_, s) => SplashGate(deepLink: s.uri.queryParameters['to'])),
        GoRoute(
          path: '/onboarding',
          redirect: (_, s) => s.uri.path == '/onboarding' ? '/onboarding/welcome' : null,
          routes: [
            GoRoute(path: 'welcome', builder: (_, __) => const WelcomeScreen()),
            GoRoute(path: 'language', builder: (_, __) => const LanguageStep()),
            GoRoute(path: 'prayer', builder: (_, __) => const PrayerStep()),
            GoRoute(path: 'consent', builder: (_, __) => const ConsentStep()),
            GoRoute(path: 'goal', builder: (_, __) => const GoalStep()),
            GoRoute(path: 'routine', builder: (_, __) => const RoutineStep()),
            GoRoute(path: 'download', builder: (_, __) => const DownloadStep()),
          ],
        ),
        if (kDebugMode) GoRoute(path: '/debug/gallery', builder: (_, __) => const GalleryScreen()),
        StatefulShellRoute(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          // Like indexedStack (every tab keeps its state) but cross-fades on switch.
          navigatorContainerBuilder: (context, shell, children) => TabBranches(currentIndex: shell.currentIndex, children: children),
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
                  builder: (_, s) => QuranIndexScreen(key: ValueKey(s.uri.query), focusSearch: s.uri.queryParameters['search'] == '1'),
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
                  builder: (_, __) => const PrayerScreen(),
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
                    GoRoute(path: 'calendar', builder: (_, __) => const CalendarScreen()),
                    GoRoute(
                      path: 'redeem',
                      builder: (_, __) => const RedeemScreen(),
                      routes: [GoRoute(path: 'codes', builder: (_, __) => const CodesScreen())],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, __) => const ProfileScreen(),
                  routes: [
                    GoRoute(path: 'privacy', builder: (_, __) => const PrivacyScreen()),
                    GoRoute(path: 'ledger', builder: (_, __) => const LedgerScreen()),
                    GoRoute(path: 'downloads', builder: (_, __) => const DownloadsScreen()),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

final appRouter = buildRouter();
