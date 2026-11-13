import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/hifz/presentation/hifz_screen.dart';
import '../../features/listen/presentation/now_playing_screen.dart';
import '../../features/listen/presentation/reciters_screen.dart';
import '../../features/quran/domain/quran_data.dart';
import '../../features/quran/presentation/khatma_screen.dart';
import '../../features/quran/presentation/reader_screen.dart';
import '../../features/recite/presentation/recite_screen.dart';

/// `/quran/*` (moved unchanged from router.dart; owned by the quran stream; router.dart only
/// spreads this list). Full-screen routes sit on [root], above the tab bar.
List<RouteBase> quranRoutes(GlobalKey<NavigatorState> root) => [
      GoRoute(path: 'hifz', builder: (_, __) => const HifzScreen()),
      GoRoute(path: 'khatma', builder: (_, __) => const KhatmaScreen()),
      GoRoute(path: 'reciters', builder: (_, __) => const RecitersScreen()),
      GoRoute(
        parentNavigatorKey: root,
        path: 'read/:page',
        builder: (_, s) => ReaderScreen(
          initialPage: (int.tryParse(s.pathParameters['page'] ?? '') ?? 1).clamp(1, 604),
          focus: parseAyahRef(s.uri.queryParameters['ayah']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: root,
        path: 'recite/:surah',
        builder: (_, s) => ReciteScreen(
          surah: (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114),
          from: int.tryParse(s.uri.queryParameters['from'] ?? ''),
          to: int.tryParse(s.uri.queryParameters['to'] ?? ''),
          fromHifz: s.uri.queryParameters['hifz'] == '1',
        ),
      ),
      GoRoute(
        parentNavigatorKey: root,
        path: 'listen/:surah',
        builder: (_, s) => NowPlayingScreen(
          surah: (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114),
          ayah: int.tryParse(s.uri.queryParameters['ayah'] ?? ''),
          to: int.tryParse(s.uri.queryParameters['to'] ?? ''),
        ),
      ),
    ];
