import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void>? _loaded;

/// Loads the bundled brand fonts so goldens show real Arabic/Latin shapes (not the test box font).
///
/// Once per test file: every font load makes the engine send a `fontsChange` system message that is
/// handled a moment later. Landing while a widget tree is up, it schedules a relayout frame, and a test
/// that ends without pumping it fails with "an animation is still running". So the load runs in real
/// async (it would never settle in a test's fake zone), waits until each load's notification arrived,
/// and later calls reuse it instead of sending more.
Future<void> loadAppFonts() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  return _loaded ??= binding.inTest ? binding.runAsync(_load) : _load();
}

Future<void> _load() async {
  final fonts = PaintingBinding.instance.systemFonts;
  var notified = 0;
  var loads = 0;
  var allSent = false;
  final settled = Completer<void>();
  void check() {
    if (allSent && notified >= loads && !settled.isCompleted) settled.complete();
  }

  void onChange() {
    notified++;
    check();
  }

  Future<void> load(String family, List<Uint8List> files) async {
    final loader = FontLoader(family);
    for (final bytes in files) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    loads++;
    await loader.load();
  }

  Uint8List asset(String f) => File('assets/fonts/$f').readAsBytesSync();
  fonts.addListener(onChange);
  try {
    await load('Tajawal', [asset('Tajawal-Regular.ttf'), asset('Tajawal-Medium.ttf'), asset('Tajawal-Bold.ttf')]);
    await load('Jost', [asset('Jost-Light.ttf'), asset('Jost-Regular.ttf'), asset('Jost-Medium.ttf')]);
    await load('Amiri', [asset('Amiri-Regular.ttf'), asset('Amiri-Bold.ttf')]);
    await load('AmiriQuran', [asset('AmiriQuran-Regular.ttf')]);
    // Material icons from the SDK, so chevrons render instead of boxes.
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
    final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await load('MaterialIcons', [icons.readAsBytesSync()]);
    allSent = true;
    check();
    // Real time here (runAsync); a missing notification must not hang the suite.
    await settled.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  } finally {
    fonts.removeListener(onChange);
  }
}
