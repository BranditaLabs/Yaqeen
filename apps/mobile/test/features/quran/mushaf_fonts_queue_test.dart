import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/download_queue.dart';
import 'package:yaqeen/features/quran/data/mushaf_fonts.dart';

class _FakeLoader implements PageFontLoader {
  @override
  Future<void> load(String family, Uint8List bytes) async {}
}

void main() {
  test('a page on screen jumps ahead of «download the whole mushaf» and survives cancelling it', () async {
    final dir = Directory.systemTemp.createTempSync('mushaf-queue');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gate = Completer<void>();
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.pathSegments.last);
      await gate.future;
      return http.Response.bytes([0, 1, 0, 0, ...List.filled(20, 7)], 200);
    });
    final queue = DownloadQueue(maxConcurrent: 1);
    final fonts = MushafFonts(root: () async => dir, baseUrl: 'https://cdn.example/qcf', queue: queue, loader: _FakeLoader(), client: client);

    final bulk = fonts.downloadAll();
    for (var i = 0; i < 2000 && queue.waiting < MushafFonts.pageCount - 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(queue.running, 1);
    expect(queue.waiting, MushafFonts.pageCount - 1);

    final shown = fonts.ensure(300); // the reader turned to page 300
    await Future<void>.delayed(const Duration(milliseconds: 5));
    fonts.cancelDownloadAll();
    gate.complete();

    expect(await shown, isTrue);
    expect(fonts.isReady(300), isTrue);
    expect(fonts.hasFailed(300), isFalse);
    await bulk;
    expect(requested, ['p1.ttf', 'p300.ttf']); // nothing else was fetched after the cancel
  });
}
