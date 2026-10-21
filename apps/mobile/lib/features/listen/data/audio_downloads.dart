import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/audio_models.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class WifiRequired implements Exception {
  const WifiRequired();
}

/// Cooperative cancellation for a running download.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Surah MP3 files on disk: `<root>/audio/<reciter>/<sss>.mp3` (spec §6.7). Downloads resume from
/// a `.part` file with an HTTP Range request, wait for Wi-Fi unless overridden, and deleting a
/// reciter reclaims its storage (shown in Profile).
class AudioDownloads {
  AudioDownloads({required this.root, required this.isUnmetered, http.Client? client}) : _http = client ?? http.Client();

  final Future<Directory> Function() root;
  final Future<bool> Function() isUnmetered;
  final http.Client _http;

  Future<Directory> _dir(String reciterId) async => Directory('${(await root()).path}/audio/$reciterId');

  Future<File> fileFor(String reciterId, int surah) async =>
      File('${(await _dir(reciterId)).path}/${surah.toString().padLeft(3, '0')}.mp3');

  Future<File> timingsFile(String reciterId) async => File('${(await _dir(reciterId)).path}/timings.json');

  Future<bool> has(String reciterId, int surah) async => (await fileFor(reciterId, surah)).exists();

  Future<Set<int>> downloadedSurahs(String reciterId) async {
    final d = await _dir(reciterId);
    if (!await d.exists()) return {};
    final out = <int>{};
    await for (final f in d.list()) {
      final m = RegExp(r'(\d{3})\.mp3$').firstMatch(f.path);
      if (m != null) out.add(int.parse(m.group(1)!));
    }
    return out;
  }

  Future<int> bytesOnDisk([String? reciterId]) async {
    final d = reciterId == null ? Directory('${(await root()).path}/audio') : await _dir(reciterId);
    if (!await d.exists()) return 0;
    var total = 0;
    await for (final f in d.list(recursive: true)) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> delete(String reciterId) async {
    final d = await _dir(reciterId);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Local file when downloaded, otherwise the streaming URL.
  Future<Uri> sourceFor(Reciter r, int surah) async {
    final f = await fileFor(r.id, surah);
    return await f.exists() ? f.uri : r.surahUrl(surah);
  }

  /// Downloads one surah; resumes a previous partial file. [onProgress] gets (received, total?).
  Future<File> downloadSurah(
    Reciter r,
    int surah, {
    CancelToken? cancel,
    bool allowMetered = false,
    void Function(int received, int? total)? onProgress,
  }) async {
    final target = await fileFor(r.id, surah);
    if (await target.exists()) return target;
    if (!allowMetered && !await isUnmetered()) throw const WifiRequired();
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    var have = await part.exists() ? await part.length() : 0;

    final req = http.Request('GET', r.surahUrl(surah));
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    final res = await _http.send(req);
    if (res.statusCode == 416) {
      // Server says the range is past the end — the partial file is complete.
      await part.rename(target.path);
      return target;
    }
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('download ${res.statusCode}', uri: req.url);
    }
    if (res.statusCode == 200) have = 0; // server ignored the range — start over
    final total = res.contentLength == null ? null : res.contentLength! + have;
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var received = have;
    try {
      await for (final chunk in res.stream) {
        if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total != null && received < total) throw HttpException('download truncated', uri: req.url);
    await part.rename(target.path);
    return target;
  }
}
