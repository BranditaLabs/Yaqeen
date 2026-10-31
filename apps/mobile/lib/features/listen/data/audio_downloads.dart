import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart' show OfflineException;
import '../../../core/network/resumable_download.dart';
import '../domain/audio_models.dart';

export '../../../core/network/resumable_download.dart' show CancelToken, DownloadCancelled, WifiRequired;

/// Surah MP3 files on disk: `<root>/audio/<reciter>/<sss>.mp3` (spec §6.7). Downloads resume from
/// a `.part` file with an HTTP Range request, wait for Wi-Fi unless overridden, and deleting a
/// reciter reclaims its storage (shown in Profile). Remote URLs come from [resolve] (Quran Foundation
/// surahs are looked up through our API); without it only own-CDN reciters (`baseUrl`) work.
class AudioDownloads {
  AudioDownloads({required this.root, required this.isUnmetered, this.resolve, http.Client? client}) : _http = client ?? http.Client();

  final Future<Directory> Function() root;
  final Future<bool> Function() isUnmetered;
  final Future<Uri> Function(Reciter r, int surah)? resolve;
  final http.Client _http;

  Future<Uri> _remote(Reciter r, int surah) async {
    final resolver = resolve;
    if (resolver != null) return resolver(r, surah);
    final url = r.surahUrl(surah);
    if (url == null) throw const OfflineException();
    return url;
  }

  Future<Directory> _dir(String reciterId) async => Directory('${(await root()).path}/audio/$reciterId');

  Future<File> fileFor(String reciterId, int surah) async =>
      File('${(await _dir(reciterId)).path}/${surah.toString().padLeft(3, '0')}.mp3');

  Future<File> timingsFile(String reciterId) async => timingsFileIn(await root(), reciterId);

  /// `<root>/audio/<reciter>/timings.json` — shared with [ReciterRepository] (which can't depend on this class's provider).
  static File timingsFileIn(Directory root, String reciterId) => File('${root.path}/audio/$reciterId/timings.json');

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
    return await f.exists() ? f.uri : _remote(r, surah);
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
    return downloadResumable(_http, await _remote(r, surah), target, cancel: cancel, onProgress: onProgress);
  }
}
