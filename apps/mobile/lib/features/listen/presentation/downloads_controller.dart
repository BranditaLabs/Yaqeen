import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../quran/domain/quran_data.dart';
import '../data/audio_downloads.dart';
import '../domain/audio_models.dart';

@immutable
class ReciterDownload {
  const ReciterDownload({this.surahs = 0, this.running = false, this.error});
  final int surahs;
  final bool running;
  final Object? error;
  bool get complete => surahs >= QuranData.surahCount;
  double get fraction => surahs / QuranData.surahCount;
}

/// Full-mushaf downloads per reciter (spec §5.14): one surah at a time, resumable (partial files
/// survive), cancellable, Wi-Fi only unless the user allowed mobile data.
class DownloadsController extends Notifier<Map<String, ReciterDownload>> {
  final _tokens = <String, CancelToken>{};

  @override
  Map<String, ReciterDownload> build() => const {};

  Future<void> refresh(Iterable<Reciter> reciters) async {
    final d = ref.read(audioDownloadsProvider);
    final next = {...state};
    for (final r in reciters) {
      if (next[r.id]?.running ?? false) continue;
      next[r.id] = ReciterDownload(surahs: (await d.downloadedSurahs(r.id)).length);
    }
    state = next;
  }

  void _set(String id, ReciterDownload v) => state = {...state, id: v};

  Future<void> downloadAll(Reciter r) async {
    if (state[r.id]?.running ?? false) return;
    final d = ref.read(audioDownloadsProvider);
    final allowMetered = await ref.read(listenStoreProvider).allowMetered();
    final token = _tokens[r.id] = CancelToken();
    var have = await d.downloadedSurahs(r.id);
    _set(r.id, ReciterDownload(surahs: have.length, running: true));
    try {
      for (var s = 1; s <= QuranData.surahCount; s++) {
        if (token.isCancelled) break;
        if (have.contains(s)) continue;
        await d.downloadSurah(r, s, cancel: token, allowMetered: allowMetered);
        have = {...have, s};
        _set(r.id, ReciterDownload(surahs: have.length, running: true));
      }
      _set(r.id, ReciterDownload(surahs: have.length));
    } on DownloadCancelled {
      _set(r.id, ReciterDownload(surahs: have.length));
    } on Exception catch (e) {
      _set(r.id, ReciterDownload(surahs: have.length, error: e));
    } finally {
      _tokens.remove(r.id);
    }
  }

  void cancel(String id) => _tokens[id]?.cancel();

  Future<void> delete(String id) async {
    cancel(id);
    await ref.read(audioDownloadsProvider).delete(id);
    _set(id, const ReciterDownload());
  }
}

final downloadsControllerProvider = NotifierProvider<DownloadsController, Map<String, ReciterDownload>>(DownloadsController.new);
