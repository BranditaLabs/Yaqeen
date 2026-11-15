import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/storage/kv_store.dart';
import '../domain/recording_models.dart';
import 'recordings_repository.dart';

/// Where a take that is not on the server yet stands.
enum DraftState {
  /// Kept on this phone only: a guest's take, or one saved before signing in. Uploaded only when the
  /// person taps «انشر» after signing in (never on its own).
  local,

  /// Saved while offline (or the server was busy): uploaded by itself when the network is back.
  queued,

  /// The server refused it for good ([failure]); the card offers to re-record or delete.
  failed,
}

/// A finished take waiting on this phone: the .m4a in app storage and what the upload sends.
class RecordingDraft {
  const RecordingDraft({
    required this.id,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.durationMs,
    required this.path,
    required this.visibility,
    required this.commentsOn,
    required this.createdAt,
    this.state = DraftState.queued,
    this.failure,
    this.clientScore,
    this.clientWords,
  });

  final String id;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int durationMs;

  /// The .m4a (contracts `RECORDING_FORMAT`).
  final String path;
  final RecordingVisibility visibility;
  final bool commentsOn;
  final DateTime createdAt;
  final DraftState state;
  final RecordingFailure? failure;
  final double? clientScore;

  /// Karaoke timings from the on-device check (private playback; a shared upload's diagnostics).
  final List<RecordingWord>? clientWords;

  RecordingDraft copyWith({DraftState? state, RecordingFailure? failure, RecordingVisibility? visibility, bool clearFailure = false}) => RecordingDraft(
        id: id,
        surah: surah,
        fromAyah: fromAyah,
        toAyah: toAyah,
        durationMs: durationMs,
        path: path,
        visibility: visibility ?? this.visibility,
        commentsOn: commentsOn,
        createdAt: createdAt,
        state: state ?? this.state,
        failure: clearFailure ? null : (failure ?? this.failure),
        clientScore: clientScore,
        clientWords: clientWords,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        's': surah,
        'f': fromAyah,
        't': toAyah,
        'ms': durationMs,
        'path': path,
        'vis': visibility.code,
        'c': commentsOn,
        'at': createdAt.toIso8601String(),
        'state': state.name,
        if (failure != null) 'fail': failure!.code,
        if (clientScore != null) 'score': clientScore,
        if (clientWords != null) 'words': [for (final w in clientWords!) w.toJson()],
      };

  static RecordingDraft? tryParse(Object? j) {
    if (j is! Map) return null;
    try {
      return RecordingDraft(
        id: j['id'] as String,
        surah: j['s'] as int,
        fromAyah: j['f'] as int,
        toAyah: j['t'] as int,
        durationMs: j['ms'] as int,
        path: j['path'] as String,
        visibility: RecordingVisibility.fromCode(j['vis']),
        commentsOn: j['c'] != false,
        createdAt: DateTime.parse(j['at'] as String),
        state: DraftState.values.asNameMap()[j['state']] ?? DraftState.local,
        failure: j['fail'] == null ? null : RecordingFailure.fromCode(j['fail'] as String),
        clientScore: (j['score'] as num?)?.toDouble(),
        clientWords: RecordingWord.listFrom(j['words']),
      );
    } on Object {
      return null;
    }
  }
}

/// Takes not on the server yet (KV `recordings.drafts.v1`, files in `recordings/drafts/`), and the
/// upload of queued ones with backoff (30 s → 15 min, jittered) — the same rhythm as the Outbox, but
/// for a binary body the JSON Outbox cannot carry. Drafts are account data: wiped with the account.
class RecordingDrafts {
  RecordingDrafts({required this.store, required this.repo, DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final KvStore store;
  final RecordingsRepository repo;
  final DateTime Function() _now;
  final Random _random;

  static const key = 'recordings.drafts.v1';
  static const baseDelay = Duration(seconds: 30);
  static const maxDelay = Duration(minutes: 15);

  int _failures = 0;
  DateTime? _retryAfter;
  Future<List<Recording>>? _running;

  final _changes = StreamController<void>.broadcast();

  /// Fires after every change to the drafts.
  Stream<void> get changes => _changes.stream;

  static String newId() => 'd${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  Future<List<RecordingDraft>> all() async {
    final raw = await store.read(key);
    if (raw == null) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) RecordingDraft.tryParse(j)].whereType<RecordingDraft>().toList();
    } on Object {
      return const [];
    }
  }

  Future<void> _save(List<RecordingDraft> list) async {
    await store.write(key, jsonEncode([for (final d in list) d.toJson()]));
    _changes.add(null);
  }

  Future<void> add(RecordingDraft d) async => _save([...await all(), d]);

  Future<void> replace(RecordingDraft d) async => _save([for (final x in await all()) x.id == d.id ? d : x]);

  /// Removes the draft and its file.
  Future<void> remove(String id) async {
    final list = await all();
    for (final d in list.where((d) => d.id == id)) {
      final f = File(d.path);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } on FileSystemException {
          // best effort
        }
      }
    }
    await _save([for (final d in list) if (d.id != id) d]);
  }

  /// Uploads one draft now (a person's tap, or the queue). On success the draft is gone and the
  /// server's recording returned; a refusal marks it failed; no network keeps it queued.
  Future<Recording> upload(RecordingDraft d) async {
    final f = File(d.path);
    if (!f.existsSync()) {
      await remove(d.id);
      throw const RecordingException(RecordingFailure.badFormat);
    }
    try {
      final r = await repo.upload(
        surah: d.surah,
        fromAyah: d.fromAyah,
        toAyah: d.toAyah,
        durationMs: d.durationMs,
        audio: await f.readAsBytes(),
        visibility: d.visibility,
        commentsOn: d.commentsOn,
        clientScore: d.clientScore,
        clientWords: d.clientWords,
      );
      await remove(d.id);
      return r;
    } on RecordingException catch (e) {
      if (e.transient) {
        if (d.state != DraftState.local) await replace(d.copyWith(state: DraftState.queued, clearFailure: true));
      } else {
        await replace(d.copyWith(state: DraftState.failed, failure: e.failure));
      }
      rethrow;
    }
  }

  /// Uploads every queued draft in order (concurrent callers share one run). [force] (a person's
  /// action, the network back) ignores the backoff. Returns what reached the server.
  Future<List<Recording>> flush({bool force = false}) => _running ??= _flush(force: force).whenComplete(() => _running = null);

  Future<List<Recording>> _flush({required bool force}) async {
    if (!force && _retryAfter != null && _now().isBefore(_retryAfter!)) return const [];
    final out = <Recording>[];
    var stalled = false;
    for (final d in await all()) {
      if (d.state != DraftState.queued) continue;
      try {
        out.add(await upload(d));
      } on RecordingException catch (e) {
        if (e.transient) {
          stalled = true;
          break;
        }
      }
    }
    if (stalled) {
      _failures++;
      final cap = baseDelay * pow(2, _failures - 1).toInt();
      final ceiling = cap > maxDelay ? maxDelay : cap;
      _retryAfter = _now().add(Duration(milliseconds: (_random.nextDouble() * ceiling.inMilliseconds).round()));
    } else {
      _failures = 0;
      _retryAfter = null;
    }
    return out;
  }
}
