import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../quran/domain/quran_data.dart';
import '../data/audio_downloads.dart';
import '../domain/audio_models.dart';

@immutable
class ReciterDownload {
  const ReciterDownload({this.surahs = 0, this.running = false, this.error, this.partial = 0});
  final int surahs;
  final bool running;
  final Object? error;

  /// Sum of the in-flight surahs' fractions, so the bar moves smoothly between whole surahs.
  final double partial;
  bool get complete => surahs >= QuranData.surahCount;
  double get fraction => ((surahs + partial) / QuranData.surahCount).clamp(0.0, 1.0);
}

/// Full-mushaf downloads per reciter (spec §5.14) on the app-wide [DownloadQueue]: several surahs
/// in parallel, resumable (partial files survive), cancellable, Wi-Fi only unless the user allowed
/// mobile data. App-scoped, so leaving the screen never stops a download; one interrupted by a kill
/// or restart resumes on the next launch ([resumeInterrupted]).
class DownloadsController extends Notifier<Map<String, ReciterDownload>> {
  static const _repaint = Duration(milliseconds: 250);

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
    final queue = ref.read(downloadQueueProvider);
    final listen = ref.read(listenStoreProvider);
    final allowMetered = await listen.allowMetered();
    await listen.setDownloading(r.id, true);
    // Every surah's ayah timings next to the files, so the whole download keeps ayah sync offline.
    if (r.isQf) ref.read(reciterRepositoryProvider).saveOfflineTimings(r).ignore();
    var have = await d.downloadedSurahs(r.id);
    final inFlight = <int, double>{};
    var painted = DateTime.fromMillisecondsSinceEpoch(0);
    void paint({bool now = false}) {
      final t = DateTime.now();
      if (!now && t.difference(painted) < _repaint) return;
      painted = t;
      _set(r.id, ReciterDownload(surahs: have.length, running: true, partial: inFlight.values.fold(0.0, (a, b) => a + b)));
    }

    paint(now: true);
    final jobs = [
      for (var s = 1; s <= QuranData.surahCount; s++)
        if (!have.contains(s))
          queue
              .add(
            surahDownloadKey(r.id, s),
            group: r.id,
            run: (cancel, progress) => d.downloadSurah(r, s, cancel: cancel, allowMetered: allowMetered, onProgress: progress),
            onProgress: (received, total) {
              if (total != null && total > 0) inFlight[s] = received / total;
              paint();
            },
          )
              .then((_) {
            inFlight.remove(s);
            have = {...have, s};
            paint(now: true);
          }),
    ];
    try {
      await Future.wait(jobs, eagerError: true);
      await listen.setDownloading(r.id, false);
      _set(r.id, ReciterDownload(surahs: have.length));
    } on DownloadCancelled {
      _set(r.id, ReciterDownload(surahs: have.length));
    } on Exception catch (e) {
      // One failure (no Wi-Fi, server error) stops the rest; partial files resume next time.
      queue.cancelGroup(r.id);
      _set(r.id, ReciterDownload(surahs: have.length, error: e));
    }
  }

  /// Restarts downloads a kill or restart interrupted (called after the first frame).
  Future<void> resumeInterrupted() async {
    final ids = await ref.read(listenStoreProvider).downloading();
    if (ids.isEmpty) return;
    final reciters = await ref.read(reciterRepositoryProvider).cached();
    for (final r in reciters.where((r) => ids.contains(r.id))) {
      downloadAll(r).ignore();
    }
  }

  /// One surah, now (the player's «تنزيل السورة», a guided session without audio): at the head of
  /// the app-wide [DownloadQueue] (key `<reciter>/<surah>`, in the reciter's group), so leaving the
  /// screen never stops it and a full download already queuing it simply joins. Progress is in
  /// [surahDownloadsProvider]; throws [WifiRequired] and other failures to the caller.
  Future<void> downloadSurah(Reciter r, int surah) async {
    final key = surahDownloadKey(r.id, surah);
    final progress = ref.read(surahDownloadsProvider.notifier);
    progress.set(key, 0);
    try {
      final allowMetered = await ref.read(listenStoreProvider).allowMetered();
      await ref.read(downloadQueueProvider).add(
            key,
            group: r.id,
            urgent: true,
            run: (cancel, onProgress) =>
                ref.read(audioDownloadsProvider).downloadSurah(r, surah, cancel: cancel, allowMetered: allowMetered, onProgress: onProgress),
            onProgress: (received, total) {
              if (total != null && total > 0) progress.set(key, received / total);
            },
          );
      progress.set(key, 1);
    } finally {
      progress.clear(key);
    }
  }

  void cancel(String id) {
    ref.read(downloadQueueProvider).cancelGroup(id);
    ref.read(listenStoreProvider).setDownloading(id, false).ignore();
  }

  Future<void> delete(String id) async {
    cancel(id);
    await ref.read(audioDownloadsProvider).delete(id);
    _set(id, const ReciterDownload());
  }
}

final downloadsControllerProvider = NotifierProvider<DownloadsController, Map<String, ReciterDownload>>(DownloadsController.new);

String surahDownloadKey(String reciterId, int surah) => '$reciterId/$surah';

/// Single-surah downloads in flight: key → fraction (0…1).
class SurahDownloads extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};
  void set(String key, double v) => state = {...state, key: v.clamp(0.0, 1.0)};
  void clear(String key) => state = {...state}..remove(key);
}

final surahDownloadsProvider = NotifierProvider<SurahDownloads, Map<String, double>>(SurahDownloads.new);
