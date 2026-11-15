import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/platform/audio_engine.dart';
import '../../../core/platform/audio_recorder.dart';
import '../../listen/presentation/listen_controller.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/recording_drafts.dart';
import '../data/recordings_repository.dart';
import '../domain/recording_models.dart';

/// The microphone for «تلاواتي» (no-op by default; main() sets the plugin recorder).
final voiceRecorderProvider = Provider<VoiceRecorder>((_) => const NoopVoiceRecorder());

final recordingsRepositoryProvider = Provider(
  (ref) => RecordingsRepository(api: ref.watch(apiClientProvider), store: ref.watch(kvStoreProvider), root: ref.watch(filesDirProvider)),
);

final recordingDraftsProvider = Provider(
  (ref) => RecordingDrafts(store: ref.watch(kvStoreProvider), repo: ref.watch(recordingsRepositoryProvider), now: ref.watch(clockProvider)),
);

/// The flag `recordings` (off by default).
final recordingsOnProvider = Provider<bool>((ref) => ref.watch(remoteConfigProvider).isOn(Flags.recordings));

/* ------------------------------------------------------------ the owner */

/// The Profile section's view: the server's recordings (cached first) and the takes still on this
/// phone (drafts: a guest's, or queued offline).
class MyRecordingsView {
  const MyRecordingsView({this.items = const [], this.drafts = const [], this.leftToday = kRecordingUploadsPerDay, this.offline = false});
  final List<Recording> items;
  final List<RecordingDraft> drafts;
  final int leftToday;

  /// Showing the cached list because the network is not there.
  final bool offline;

  int get count => items.length + drafts.length;
  bool get full => count >= kProfileRecordingsMax;
  bool get anyPending => items.any((r) => r.pending);

  MyRecordingsView copyWith({List<Recording>? items, List<RecordingDraft>? drafts, int? leftToday, bool? offline}) => MyRecordingsView(
        items: items ?? this.items,
        drafts: drafts ?? this.drafts,
        leftToday: leftToday ?? this.leftToday,
        offline: offline ?? this.offline,
      );
}

/// GET /v1/me/recordings with the device cache, plus the drafts. Polls every [pollEvery] while a
/// shared recording waits for the AI check (only while someone watches), and on [refresh] (pull,
/// app resume). Guests never reach the network: they see their drafts only.
class MyRecordingsController extends AutoDisposeAsyncNotifier<MyRecordingsView> {
  static const pollEvery = Duration(seconds: 20);

  Timer? _poll;
  bool _disposed = false;
  RecordingsRepository get _repo => ref.read(recordingsRepositoryProvider);
  RecordingDrafts get _drafts => ref.read(recordingDraftsProvider);

  @override
  Future<MyRecordingsView> build() async {
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));
    final sub = ref.watch(recordingDraftsProvider).changes.listen((_) => _reloadDrafts().ignore());
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      sub.cancel();
      _poll?.cancel();
    });
    final drafts = await _drafts.all();
    if (!account) return MyRecordingsView(drafts: drafts);
    final cached = await _repo.cachedMine();
    if (cached != null) {
      // The cached list paints at once; the fresh one follows.
      Future.microtask(() => refresh(flush: true));
      return MyRecordingsView(items: cached.items, drafts: drafts, leftToday: cached.leftToday);
    }
    final fresh = await _fetch(drafts, flush: true);
    return fresh;
  }

  Future<MyRecordingsView> _fetch(List<RecordingDraft> drafts, {bool flush = false}) async {
    if (flush) {
      try {
        await _drafts.flush();
      } on Object {
        // Queued drafts wait for the next try.
      }
      drafts = await _drafts.all();
    }
    try {
      final m = await _repo.fetchMine();
      final view = MyRecordingsView(items: m.items, drafts: drafts, leftToday: m.leftToday);
      _schedulePoll(view);
      return view;
    } on RecordingException catch (e) {
      if (e.failure == RecordingFailure.featureOff) return MyRecordingsView(drafts: drafts);
      final cached = await _repo.cachedMine();
      if (cached != null || e.failure == RecordingFailure.offline) {
        return MyRecordingsView(items: cached?.items ?? const [], drafts: drafts, leftToday: cached?.leftToday ?? kRecordingUploadsPerDay, offline: true);
      }
      rethrow;
    }
  }

  void _schedulePoll(MyRecordingsView v) {
    _poll?.cancel();
    if (!v.anyPending || _disposed) return;
    _poll = Timer(pollEvery, () => refresh().ignore());
  }

  Future<void> _reloadDrafts() async {
    final v = state.valueOrNull;
    if (v == null || _disposed) return;
    final drafts = await _drafts.all();
    if (!_disposed) state = AsyncData((state.valueOrNull ?? v).copyWith(drafts: drafts));
  }

  /// Fresh from the server (pull-to-refresh, app resume, the poll). [flush] uploads queued drafts first.
  Future<void> refresh({bool flush = false}) async {
    if (!ref.read(sessionProvider).canEarnPoints) {
      await _reloadDrafts();
      return;
    }
    try {
      final view = await _fetch(await _drafts.all(), flush: flush);
      if (!_disposed) state = AsyncData(view);
    } on Object catch (e, st) {
      if (!_disposed && state.valueOrNull == null) state = AsyncError(e, st);
    }
  }

  void _replace(Recording r) {
    final v = state.valueOrNull;
    if (v == null) return;
    final items = [for (final x in v.items) x.id == r.id ? r : x];
    final view = v.copyWith(items: items);
    state = AsyncData(view);
    _schedulePoll(view);
  }

  /// A recording the upload just created.
  void added(Recording r) {
    final v = state.valueOrNull ?? const MyRecordingsView();
    final view = v.copyWith(items: [...v.items.where((x) => x.id != r.id), r], leftToday: v.leftToday > 0 ? v.leftToday - 1 : 0);
    state = AsyncData(view);
    _schedulePoll(view);
  }

  /// PATCH visibility; members/public start the AI check (the server answers `processing`).
  Future<Recording> setVisibility(Recording r, RecordingVisibility v) async {
    final next = await _repo.patch(r.id, visibility: v);
    _replace(next);
    if (r.status == RecordingStatus.privateReady && next.pending) {
      final s = state.valueOrNull;
      if (s != null) state = AsyncData(s.copyWith(leftToday: s.leftToday > 0 ? s.leftToday - 1 : 0));
    }
    return next;
  }

  Future<void> setComments(Recording r, bool on) async {
    _replace(r.copyWith(commentsOn: on));
    try {
      _replace(await _repo.patch(r.id, commentsOn: on));
    } on RecordingException {
      _replace(r);
      rethrow;
    }
  }

  /// Moves [r] to [position] (1-based): shown at once, then sent; a failure puts the order back.
  Future<void> move(Recording r, int position) async {
    final v = state.valueOrNull;
    if (v == null) return;
    final before = v.items;
    final order = [...before]..removeWhere((x) => x.id == r.id);
    order.insert((position - 1).clamp(0, order.length), r);
    state = AsyncData(v.copyWith(items: [for (final (i, x) in order.indexed) x.copyWith(position: i + 1)]));
    try {
      await _repo.patch(r.id, position: position);
    } on RecordingException {
      final now = state.valueOrNull;
      if (now != null) state = AsyncData(now.copyWith(items: before));
      rethrow;
    }
  }

  Future<void> delete(Recording r) async {
    await _repo.delete(r.id);
    final v = state.valueOrNull;
    if (v == null) return;
    final rest = [for (final x in v.items) if (x.id != r.id) x];
    state = AsyncData(v.copyWith(items: [for (final (i, x) in rest.indexed) x.copyWith(position: i + 1)]));
  }

  /// Uploads a draft on the person's tap (a guest's take after signing in, a failed one again).
  Future<Recording> uploadDraft(RecordingDraft d) async {
    final r = await _drafts.upload(d);
    added(r);
    return r;
  }

  Future<void> deleteDraft(RecordingDraft d) => _drafts.remove(d.id);
}

final myRecordingsProvider = AsyncNotifierProvider.autoDispose<MyRecordingsController, MyRecordingsView>(MyRecordingsController.new);

/// Uploads takes queued offline wherever the person is in the app — the network back
/// (`force: true`), the app resumed, the 15-minute foreground timer (`AppGate`, beside the Outbox) —
/// so «ستُرفع عند الاتصال» holds even when the Profile is not open. An account with the flag on only.
class RecordingsSync {
  RecordingsSync(this._ref);
  final Ref _ref;

  Future<void> flush({bool force = false}) async {
    if (!_ref.read(sessionProvider).canEarnPoints || !_ref.read(recordingsOnProvider)) return;
    final List<Recording> sent;
    try {
      sent = await _ref.read(recordingDraftsProvider).flush(force: force);
    } on Object {
      return; // the queue keeps them for the next try
    }
    if (sent.isNotEmpty && _ref.exists(myRecordingsProvider)) await _ref.read(myRecordingsProvider.notifier).refresh();
  }
}

final recordingsSyncProvider = Provider(RecordingsSync.new);

/* -------------------------------------------------------------- members */

/// GET /v1/community/members/:handle/recordings.
final memberRecordingsProvider =
    FutureProvider.autoDispose.family<MemberRecordings, String>((ref, handle) => ref.watch(recordingsRepositoryProvider).member(handle));

/// The comments loaded so far for one recording (newest first).
class CommentsView {
  const CommentsView({this.items = const [], this.nextCursor, this.commentsOn = true, this.loadingMore = false, this.moreFailed = false});
  final List<RecordingComment> items;
  final String? nextCursor;
  final bool commentsOn;
  final bool loadingMore;
  final bool moreFailed;

  bool get hasMore => nextCursor != null;

  CommentsView copyWith({List<RecordingComment>? items, String? Function()? nextCursor, bool? commentsOn, bool? loadingMore, bool? moreFailed}) =>
      CommentsView(
        items: items ?? this.items,
        nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
        commentsOn: commentsOn ?? this.commentsOn,
        loadingMore: loadingMore ?? this.loadingMore,
        moreFailed: moreFailed ?? this.moreFailed,
      );
}

/// GET/POST/DELETE /v1/recordings/:id/comments (+ report), paged by cursor.
class CommentsController extends AutoDisposeFamilyAsyncNotifier<CommentsView, String> {
  RecordingsRepository get _repo => ref.read(recordingsRepositoryProvider);

  @override
  Future<CommentsView> build(String arg) async {
    final p = await _repo.comments(arg);
    return CommentsView(items: p.items, nextCursor: p.nextCursor, commentsOn: p.commentsOn);
  }

  Future<void> loadMore() async {
    final v = state.valueOrNull;
    if (v == null || !v.hasMore || v.loadingMore) return;
    state = AsyncData(v.copyWith(loadingMore: true, moreFailed: false));
    try {
      final p = await _repo.comments(arg, cursor: v.nextCursor);
      final seen = v.items.map((c) => c.id).toSet();
      state = AsyncData(v.copyWith(items: [...v.items, ...p.items.where((c) => !seen.contains(c.id))], nextCursor: () => p.nextCursor, loadingMore: false));
    } on RecordingException {
      state = AsyncData(v.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  /// Posts [text]; the new comment goes on top. Throws [RecordingException] (inline errors).
  Future<RecordingComment> post(String text) async {
    try {
      final c = await _repo.postComment(arg, text);
      final v = state.valueOrNull ?? const CommentsView();
      state = AsyncData(v.copyWith(items: [c, ...v.items]));
      return c;
    } on RecordingException catch (e) {
      if (e.failure == RecordingFailure.commentsOff) {
        final v = state.valueOrNull;
        if (v != null) state = AsyncData(v.copyWith(commentsOn: false));
      }
      rethrow;
    }
  }

  /// Deletes at once; a failure puts the comment back.
  Future<void> delete(RecordingComment c) async {
    final v = state.valueOrNull;
    if (v == null) return;
    state = AsyncData(v.copyWith(items: [for (final x in v.items) if (x.id != c.id) x]));
    try {
      await _repo.deleteComment(arg, c.id);
    } on RecordingException catch (e) {
      if (e.failure == RecordingFailure.notFound) return; // already gone
      final now = state.valueOrNull ?? v;
      state = AsyncData(now.copyWith(items: v.items));
      rethrow;
    }
  }

  /// Hides a comment here (after a report or a block).
  void hide(bool Function(RecordingComment c) test) {
    final v = state.valueOrNull;
    if (v == null) return;
    state = AsyncData(v.copyWith(items: [for (final x in v.items) if (!test(x)) x]));
  }

  void setCommentsOn(bool on) {
    final v = state.valueOrNull;
    if (v != null) state = AsyncData(v.copyWith(commentsOn: on));
  }
}

final commentsProvider = AsyncNotifierProvider.autoDispose.family<CommentsController, CommentsView, String>(CommentsController.new);

/* ------------------------------------------------------------- playback */

/// What the single player is doing for «تلاواتي».
class ClipPlayback {
  const ClipPlayback({this.key, this.playing = false, this.position = Duration.zero, this.loading = false, this.failed = false});

  /// Which clip is loaded ('rec/<id>', 'draft/<id>', 'take'); null: none.
  final String? key;
  final bool playing;
  final Duration position;
  final bool loading;
  final bool failed;

  bool isOf(String k) => key == k;
  double progressOf(String k, int durationMs) => key == k && durationMs > 0 ? (position.inMilliseconds / durationMs).clamp(0.0, 1.0) : 0;
}

/// Plays recordings through the app's single player (`ListenController.playClip`, like a reciter
/// sample: the surah pauses and comes back paused). Position and play state come from the engine
/// while this clip is the one loaded; anything else taking the player resets this.
class RecordingPlayer extends Notifier<ClipPlayback> {
  final _subs = <StreamSubscription<Object?>>[];

  AudioEngine get _engine => ref.read(audioEngineProvider);
  static String metaId(String key) => 'clip/$key';

  @override
  ClipPlayback build() {
    final e = ref.watch(audioEngineProvider);
    ref.listen(listenControllerProvider.select((l) => l.sampleOf), (_, now) {
      final k = state.key;
      if (k != null && !state.loading && now != metaId(k)) state = const ClipPlayback();
    });
    void onPosition(Duration p) {
      if (_mine) state = ClipPlayback(key: state.key, playing: state.playing, position: p);
    }

    void onPlaying(bool p) {
      if (_mine) state = ClipPlayback(key: state.key, playing: p, position: state.position);
    }

    _subs
      ..add(e.position.listen(onPosition))
      ..add(e.playing.listen(onPlaying));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
    });
    return const ClipPlayback();
  }

  bool get _mine {
    final k = state.key;
    return k != null && ref.read(listenControllerProvider).sampleOf == metaId(k);
  }

  /// Plays [key] (loading its file with [load] the first time), or pauses / resumes it.
  Future<void> toggle(String key, Future<File> Function() load, {required String title, String artist = 'يقين'}) async {
    if (state.key == key && _mine) {
      if (state.playing) {
        await _engine.pause();
        state = ClipPlayback(key: key, position: state.position);
      } else {
        state = ClipPlayback(key: key, playing: true, position: state.position);
        await _engine.play();
      }
      return;
    }
    state = ClipPlayback(key: key, loading: true);
    try {
      final f = await load();
      final ok = await ref.read(listenControllerProvider.notifier).playClip(Uri.file(f.path), AudioMeta(id: metaId(key), title: title, artist: artist));
      state = ok ? ClipPlayback(key: key, playing: true) : ClipPlayback(key: key, failed: true);
    } on Object {
      state = ClipPlayback(key: key, failed: true);
    }
  }

  /// Stops [key] if it is the one loaded (a sheet closing, a take discarded).
  Future<void> stop([String? key]) async {
    if (state.key == null || (key != null && state.key != key)) return;
    final mine = _mine;
    state = const ClipPlayback();
    if (mine) await ref.read(listenControllerProvider.notifier).stopSample();
  }
}

final recordingPlayerProvider = NotifierProvider<RecordingPlayer, ClipPlayback>(RecordingPlayer.new);
