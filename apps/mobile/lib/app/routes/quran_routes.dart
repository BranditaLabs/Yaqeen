import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../features/hifz/presentation/hifz_screen.dart';
import '../../features/listen/presentation/reciters_screen.dart';
import '../../features/quran/domain/passage.dart';
import '../../features/quran/domain/quran_data.dart';
import '../../features/quran/presentation/khatma_screen.dart';
import '../../features/quran/presentation/reader_screen.dart';

int? _int(String? raw) => int.tryParse(raw ?? '');

/// `?surah=&from=&to=` → the passage a layer works on (only with all three).
Passage? passageOfQuery(Map<String, String> q) {
  final s = _int(q['surah']), f = _int(q['from']), t = _int(q['to']);
  if (s == null || f == null || t == null || s < 1 || s > QuranData.surahCount || f < 1 || t < f) return null;
  return Passage(s, f, t);
}

/// The page of [surah]:[ayah] — from the mushaf when it is loaded, else the bundled table of surah
/// start pages (synchronous: a redirect never waits for the text).
int pageForRedirect(BuildContext context, int surah, int? ayah) {
  QuranData? q;
  try {
    q = ProviderScope.containerOf(context, listen: false).read(quranDataProvider).valueOrNull;
  } on Object {
    q = null;
  }
  if (q == null) return surahStartPage(surah);
  final s = q.surah(surah);
  return q.pageOf(AyahRef(surah, (ayah ?? 1).clamp(1, s.ayahCount)));
}

/// `/quran/listen/:surah[?ayah&to]` → the reader in listen mode with the player open.
String listenRedirect(BuildContext context, GoRouterState s) {
  final surah = (_int(s.pathParameters['surah']) ?? 1).clamp(1, QuranData.surahCount);
  final ayah = _int(s.uri.queryParameters['ayah']);
  final to = _int(s.uri.queryParameters['to']);
  final page = pageForRedirect(context, surah, ayah);
  return Uri(
    path: '/quran/read/$page',
    queryParameters: {
      'mode': QuranMode.listen.name,
      if (ayah != null) 'ayah': '$surah:$ayah',
      if (ayah != null && to != null) ...{'surah': '$surah', 'from': '$ayah', 'to': '$to'},
      'player': 'open',
    },
  ).toString();
}

/// `/quran/recite/:surah[?from&to&hifz]` → the reader in recite mode on that passage.
String reciteRedirect(BuildContext context, GoRouterState s) {
  final surah = (_int(s.pathParameters['surah']) ?? 1).clamp(1, QuranData.surahCount);
  final from = _int(s.uri.queryParameters['from']);
  final to = _int(s.uri.queryParameters['to']);
  final page = pageForRedirect(context, surah, from);
  return Uri(
    path: '/quran/read/$page',
    queryParameters: {
      'mode': QuranMode.recite.name,
      if (from != null && to != null) ...{'surah': '$surah', 'from': '$from', 'to': '$to'},
      if (s.uri.queryParameters['hifz'] == '1') 'session': 'hifz',
    },
  ).toString();
}

/// `/quran/*` (owned by the quran stream; router.dart only spreads this list). Full-screen routes sit
/// on [root], above the tab bar. The printed page is the only Quran surface: listening and reciting
/// are layers of `/quran/read/:page`, and their old paths redirect into it.
List<RouteBase> quranRoutes(GlobalKey<NavigatorState> root) => [
      GoRoute(path: 'hifz', builder: (_, __) => const HifzScreen()),
      GoRoute(path: 'khatma', builder: (_, __) => const KhatmaScreen()),
      GoRoute(path: 'reciters', builder: (_, __) => const RecitersScreen()),
      GoRoute(
        parentNavigatorKey: root,
        path: 'read/:page',
        builder: (_, s) {
          final q = s.uri.queryParameters;
          return ReaderScreen(
            key: ValueKey(s.uri.toString()),
            initialPage: (_int(s.pathParameters['page']) ?? 1).clamp(1, QuranData.pageCount),
            focus: parseAyahRef(q['ayah']),
            mode: QuranMode.parse(q['mode']),
            passage: passageOfQuery(q),
            session: q['session'],
            portion: q['portion'],
            openPlayer: q['player'] == 'open',
          );
        },
      ),
      GoRoute(parentNavigatorKey: root, path: 'recite/:surah', redirect: reciteRedirect),
      GoRoute(parentNavigatorKey: root, path: 'listen/:surah', redirect: listenRedirect),
    ];
