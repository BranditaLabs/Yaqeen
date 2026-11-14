import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../network/download_queue.dart';
import '../../network/resumable_download.dart';
import '../../storage/kv_store.dart';
import 'asr_model.dart';

class AsrChecksumMismatch implements Exception {
  const AsrChecksumMismatch(this.file);
  final String file;
}

/// The on-device recitation model's files in the app's support directory (`<root>/asr/<id>/`):
/// downloaded on request through the app-wide [DownloadQueue] (resumable: a `.part` file survives a
/// kill, and an interrupted download carries on at the next launch), each file checked against the
/// pinned SHA-256 before the model counts as ready. Deleting reclaims every byte.
class AsrModelStore {
  AsrModelStore({
    required this.root,
    required this.kv,
    required this.isUnmetered,
    this.queue,
    AsrModelManifest? manifest,
    http.Client? client,
  })  : manifest = manifest ?? AsrModelManifest.current,
        _http = client ?? http.Client();

  final Future<Directory> Function() root;
  final KvStore kv;
  final Future<bool> Function() isUnmetered;

  /// App-wide download slots (null in tests: downloads run directly).
  final DownloadQueue? queue;
  final AsrModelManifest manifest;
  final http.Client _http;

  /// Set while a download the user asked for is unfinished (cleared on success, cancel or delete).
  static const downloadingKey = 'asr.downloading';

  /// Remembers whether the user allowed mobile data for it.
  static const meteredKey = 'asr.allowMetered';

  Future<Directory> dir() async => Directory('${(await root()).path}/asr/${manifest.id}');
  Future<File> _file(AsrModelFile f) async => File('${(await dir()).path}/${f.name}');
  Future<File> _marker() async => File('${(await dir()).path}/ready.json');

  Future<String> pathOf(AsrFileRole role) async => (await _file(manifest.file(role))).path;

  /// Every file is on disk with its size, and was verified when it landed.
  Future<bool> isReady() async {
    if (!manifest.published) return false;
    final marker = await _marker();
    if (!await marker.exists()) return false;
    try {
      final m = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      if (m['id'] != manifest.id) return false;
    } on FormatException {
      return false;
    }
    for (final f in manifest.files) {
      final file = await _file(f);
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  Future<bool> wasDownloading() async => await kv.read(downloadingKey) == manifest.id;
  Future<bool> allowedMetered() async => await kv.read(meteredKey) == '1';

  /// Downloads (or resumes) every missing file, verifies it, then marks the model ready. Progress is
  /// bytes received over the whole model. Throws [WifiRequired] on mobile data unless [allowMetered]
  /// (the user's explicit choice — never assumed), [AsrChecksumMismatch], [DownloadCancelled].
  Future<void> download({
    bool allowMetered = false,
    CancelToken? cancel,
    void Function(int received, int total)? onProgress,
    bool urgent = true,
  }) async {
    if (!manifest.published) throw StateError('no model published for this build');
    if (!allowMetered && !await isUnmetered()) throw const WifiRequired();
    await kv.write(downloadingKey, manifest.id);
    // The choice belongs to this download only: a later one on Wi-Fi never inherits an old «yes».
    await kv.write(meteredKey, allowMetered ? '1' : '0');
    final d = await dir();
    await d.create(recursive: true);
    final got = <String, int>{};
    void report() => onProgress?.call(got.values.fold(0, (a, b) => a + b), manifest.bytes);
    for (final f in manifest.files) {
      final target = await _file(f);
      if (await target.exists() && await target.length() == f.bytes) {
        got[f.name] = f.bytes;
        report();
        continue;
      }
      final staging = File('${target.path}.download');
      final uri = manifest.urlOf(f);
      Future<File> run(CancelToken c, ProgressFn p) => downloadResumable(_http, uri, staging, cancel: LinkedCancelToken(cancel, c), onProgress: p);
      void progress(int r, int? _) {
        got[f.name] = r;
        report();
      }

      final q = queue;
      if (q == null) {
        await run(cancel ?? CancelToken(), progress);
      } else {
        await q.add('asr:${manifest.id}:${f.name}', group: 'asr', run: run, onProgress: progress, urgent: urgent);
      }
      // Hash on a background isolate (a 40–90 MB file would stall the UI thread).
      final digest = await _sha256Of(staging.path);
      if (digest != f.sha256) {
        await staging.delete();
        throw AsrChecksumMismatch(f.name);
      }
      if (await target.exists()) await target.delete();
      await staging.rename(target.path);
      got[f.name] = f.bytes;
      report();
    }
    await (await _marker()).writeAsString(jsonEncode({'id': manifest.id, 'bytes': manifest.bytes}));
    await kv.delete(downloadingKey);
  }

  static Future<String> _sha256Of(String path) =>
      Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());

  /// Stops a running download (the partial files stay for a later resume unless [forget]).
  Future<void> cancel({bool forget = true}) async {
    queue?.cancelGroup('asr');
    if (forget) await kv.delete(downloadingKey);
  }

  /// Removes the model (and any partial download) from the phone.
  Future<void> delete() async {
    queue?.cancelGroup('asr');
    await kv.delete(downloadingKey);
    await kv.delete(meteredKey);
    final base = Directory('${(await root()).path}/asr');
    if (await base.exists()) await base.delete(recursive: true);
  }

  Future<int> bytesOnDisk() async {
    final base = Directory('${(await root()).path}/asr');
    if (!await base.exists()) return 0;
    var total = 0;
    await for (final f in base.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }
}
