import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled brand fonts so goldens show real Arabic/Latin shapes (not the test box font).
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Tajawal', ['Tajawal-Regular.ttf', 'Tajawal-Medium.ttf', 'Tajawal-Bold.ttf']);
  await load('Jost', ['Jost-Light.ttf', 'Jost-Regular.ttf', 'Jost-Medium.ttf']);
  await load('Amiri', ['Amiri-Regular.ttf', 'Amiri-Bold.ttf']);
  await load('AmiriQuran', ['AmiriQuran-Regular.ttf']);
  // Material icons from the SDK, so chevrons render instead of boxes.
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}
