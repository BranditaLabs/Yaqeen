import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/quran/domain/passage.dart';
import '../../features/recordings/presentation/recorder_screen.dart';
import '../../features/recordings/presentation/verse_picker_screen.dart';

/// `/profile/recordings/*` — «تلاواتي» (design doc §16, APP_SPEC §5.24; owned by the recordings
/// stream; router.dart only spreads this list). Both full screen over the dock.
///
/// - `new[?surah=&from=&to=]` the verse swipe picker (a range to start from: re-recording).
/// - `record?surah=&from=&to=` the live recorder and the review; a malformed range goes back to the picker.
List<RouteBase> recordingsRoutes(GlobalKey<NavigatorState> root) => [
      GoRoute(
        parentNavigatorKey: root,
        path: 'recordings/new',
        builder: (_, s) => VersePickerScreen(initial: passageFrom(s.uri.queryParameters)),
      ),
      GoRoute(
        parentNavigatorKey: root,
        path: 'recordings/record',
        redirect: (_, s) => passageFrom(s.uri.queryParameters) == null ? '/profile/recordings/new' : null,
        builder: (_, s) => RecorderScreen(passage: passageFrom(s.uri.queryParameters)!),
      ),
    ];

/// `?surah=&from=&to=` → a passage inside one surah (the picker clamps it to the surah), or null.
Passage? passageFrom(Map<String, String> q) {
  final s = int.tryParse(q['surah'] ?? '');
  final f = int.tryParse(q['from'] ?? '');
  final t = int.tryParse(q['to'] ?? '');
  if (s == null || f == null || t == null || s < 1 || s > 114 || f < 1 || t < f || t > 286) return null;
  return Passage(s, f, t);
}
