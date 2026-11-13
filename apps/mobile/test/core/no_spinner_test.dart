import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §2 / §6 loading rule: «No bare spinners. Loading is a shaped skeleton under one shimmer;
/// determinate progress is a `YqRing`; buttons keep their label and shimmer it.»
///
/// Scans every Dart file under `lib/` for Material's spinners. The only file allowed to name them
/// is `core/widgets/yq_states.dart`, whose doc comment states the rule.
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
}
