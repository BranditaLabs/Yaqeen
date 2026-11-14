import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §2 / §6 loading rule: «No bare spinners. Loading is a shaped skeleton under one shimmer;
/// determinate progress is a `YqRing`; buttons keep their label and shimmer it.»
///
/// Scans every Dart file under `lib/` for Material's spinners. The only file allowed to name them
/// is `core/widgets/yq_states.dart`, whose doc comment states the rule. Pull-to-refresh is the one
/// recorded exception and is pinned to its two files below.
void main() {
  const banned = ['CircularProgressIndicator', 'LinearProgressIndicator', 'RefreshProgressIndicator'];
  const allowed = 'lib/core/widgets/yq_states.dart';

  test('no spinner widgets in lib/ outside yq_states.dart', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from apps/mobile');
    final hits = <String>[];
    var scanned = 0;
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      scanned++;
      if (path == allowed) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final name in banned) {
          if (lines[i].contains(name)) hits.add('$path:${i + 1}: $name');
        }
      }
    }
    expect(scanned, greaterThan(100), reason: 'the scan should see the whole app');
    expect(
      hits,
      isEmpty,
      reason: 'Use a shaped skeleton inside one YqSkeleton, a YqRing for progress, or '
          'YqButton(loading: true) instead of:\n${hits.join('\n')}',
    );
  });

  test('the allowlisted file exists (keeps the allowlist honest)', () {
    expect(File(allowed).existsSync(), isTrue);
  });

  // The one recorded exception (docs/design/2026-11-profile-community-quran.md §10 / §12.8):
  // pull-to-refresh keeps Material's RefreshIndicator pull cue while the content stays on screen.
  // It may live only where it is today; a new use is a design decision, not a loading state.
  test('pull-to-refresh RefreshIndicator stays in its two recorded places', () {
    const refreshAllowed = {'lib/core/widgets/yq_stage.dart', 'lib/features/home/home_screen.dart'};
    final hits = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == allowed) continue;
      if (RegExp(r'\bRefreshIndicator\b').hasMatch(entity.readAsStringSync())) hits.add(path);
    }
    expect(hits.difference(refreshAllowed), isEmpty, reason: 'RefreshIndicator outside its recorded places');
    for (final path in refreshAllowed) {
      expect(File(path).existsSync(), isTrue, reason: '$path moved: update the allowlist and the design doc');
    }
  });
}
