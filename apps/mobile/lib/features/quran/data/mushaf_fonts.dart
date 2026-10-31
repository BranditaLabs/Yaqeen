import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/download_queue.dart';
import '../../../core/network/resumable_download.dart';

/// Registers font bytes with the engine under a family name (a fake in tests: fonts can't download there).
abstract interface class PageFontLoader {
  Future<void> load(String family, Uint8List bytes);
}

class EngineFontLoader implements PageFontLoader {
  const EngineFontLoader();
  @override
  Future<void> load(String family, Uint8List bytes) => (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

/// Progress of «download the whole mushaf».
@immutable
class MushafBulk {
  const MushafBulk({required this.done, required this.total, this.running = false, this.failed = false});
  final int done;
  final int total;
  final bool running;
  final bool failed;
  bool get complete => done >= total;
  double get progress => total == 0 ? 0 : done / total;
}

/// The per-page KFGQPC «QCF V2» fonts (one font per printed page, ≈ 330 KB each, ≈ 200 MB for 604).
///
/// Downloaded on demand into app storage, kept forever (the mushaf works offline once a page has been
/// seen), loaded into the engine once per session, and shared by every screen. Downloads go through the
/// app-wide [DownloadQueue] (group `mushaf`), so they share bandwidth fairly with recitation audio.
/// The base URL is build configuration (`Env.mushafFontBaseUrl`) so the files can move to our CDN.
class MushafFonts extends ChangeNotifier {
  MushafFonts({
    required this.root,
    required this.baseUrl,
    this.queue,
    PageFontLoader loader = const EngineFontLoader(),
    http.Client? client,
  })  : _loader = loader,
        _http = client ?? http.Client();

  final Future<Directory> Function() root;
  final String baseUrl;
  final DownloadQueue? queue;
  final PageFontLoader _loader;
  final http.Client _http;

  static const pageCount = 604;

  /// Approximate size of all 604 fonts on disk, shown before the bulk download (measured 2026-10:
  /// 198.5 MB, 159–863 KB per page; ≈ 130 MB on the wire with gzip).
  static const approxTotalMb = 200;

  final _loaded = <int>{};
  final _loading = <int, Future<bool>>{};
  final _failed = <int>{};
  Set<int>? _onDisk;
  CancelToken? _bulkCancel;

  /// «Download the whole mushaf» progress (null until it is first asked for).
  final bulk = ValueNotifier<MushafBulk?>(null);

  /// Font family for a page's glyphs.
  static String family(int page) => 'QCF2_P${page.toString().padLeft(3, '0')}';

  Uri urlFor(int page) => Uri.parse('${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}p$page.ttf');

  /// Registered with the engine — the page can be drawn now.
  bool isReady(int page) => _loaded.contains(page);
  bool allReady(Iterable<int> pages) => pages.every(_loaded.contains);

  /// The last attempt failed (offline, server error): the reader shows the text page and a hint.
  bool hasFailed(int page) => _failed.contains(page);

  Future<Directory> _dir() async => Directory('${(await root()).path}/mushaf/qcf_v2');
  Future<File> _file(int page) async => File('${(await _dir()).path}/p${page.toString().padLeft(3, '0')}.ttf');

  Future<Set<int>> _disk() async {
    if (_onDisk != null) return _onDisk!;
    final found = <int>{};
    final dir = await _dir();
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        final m = RegExp(r'p(\d{3})\.ttf$').firstMatch(f.path);
        if (m != null) found.add(int.parse(m.group(1)!));
      }
    }
    return _onDisk ??= found;
  }

  /// Pages whose font is on the device.
  Future<int> downloadedCount() async => (await _disk()).length;

  /// Makes [page] drawable: from disk, else downloaded. True when ready; never throws.
  Future<bool> ensure(int page) {
    if (_loaded.contains(page)) return SynchronousFuture(true);
    // (Block body: returning the removed future from whenComplete would make it wait on itself.)
    return _loading[page] ??= _ensure(page).whenComplete(() {
      _loading.remove(page);
    });
  }

  Future<bool> _ensure(int page) async {
    try {
      final file = await _fetch(page);
      final bytes = await file.readAsBytes();
      if (!_isFont(bytes)) {
        await file.delete();
        (await _disk()).remove(page);
        throw const FormatException('not a font');
      }
      await _loader.load(family(page), bytes);
      _loaded.add(page);
      _failed.remove(page);
      notifyListeners();
      return true;
    } on Object {
      final changed = _failed.add(page);
      if (changed) notifyListeners();
      return false;
    }
  }

  /// The font file on disk, downloading it first if needed.
  Future<File> _fetch(int page, {CancelToken? cancel}) async {
    final file = await _file(page);
    if (await file.exists()) return file;
    Future<File> run(CancelToken c, ProgressFn p) =>
        downloadResumable(_http, urlFor(page), file, cancel: LinkedCancelToken(cancel, c), onProgress: p);
    final q = queue;
    final f = q == null ? await run(CancelToken(), (_, __) {}) : await q.add<File>('mushaf:p$page', group: 'mushaf', run: run);
    (await _disk()).add(page);
    return f;
  }

  static bool _isFont(Uint8List b) =>
      b.length > 12 &&
      ((b[0] == 0 && b[1] == 1 && b[2] == 0 && b[3] == 0) || // TrueType
          (b[0] == 0x4F && b[1] == 0x54 && b[2] == 0x54 && b[3] == 0x4F) || // 'OTTO' (CFF)
          (b[0] == 0x74 && b[1] == 0x72 && b[2] == 0x75 && b[3] == 0x65)); // 'true'

  /// Warms [pages] (neighbours of the open page) without blocking anything.
  void prefetch(Iterable<int> pages) {
    for (final p in pages) {
      if (p >= 1 && p <= pageCount && !_loaded.contains(p)) ensure(p).ignore();
    }
  }

  /// Downloads every page font that is not yet on the device (files only; they load when shown).
  Future<void> downloadAll() async {
    if (bulk.value?.running ?? false) return;
    final cancel = _bulkCancel = CancelToken();
    final disk = await _disk();
    bulk.value = MushafBulk(done: disk.length, total: pageCount, running: true);
    final missing = [
      for (var p = 1; p <= pageCount; p++)
        if (!disk.contains(p)) p,
    ];
    var failed = false;
    // The queue runs a few at a time; adding all keeps its slots busy.
    Future<void> one(int p) async {
      try {
        await _fetch(p, cancel: cancel);
        if (!cancel.isCancelled) bulk.value = MushafBulk(done: disk.length, total: pageCount, running: true);
      } on Object {
        failed = true;
      }
    }

    await Future.wait([for (final p in missing) one(p)]);
    bulk.value = MushafBulk(done: disk.length, total: pageCount, failed: failed && !cancel.isCancelled);
    _bulkCancel = null;
  }

  void cancelDownloadAll() {
    _bulkCancel?.cancel();
    queue?.cancelGroup('mushaf');
  }

  /// Bytes the page fonts take on the device.
  Future<int> bytesOnDisk() async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final f in dir.list()) {
      if (f is File && f.path.endsWith('.ttf')) n += await f.length();
    }
    return n;
  }

  @visibleForTesting
  void markLoaded(int page) {
    _loaded.add(page);
    notifyListeners();
  }

  @override
  void dispose() {
    bulk.dispose();
    super.dispose();
  }
}
