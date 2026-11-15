import 'dart:convert';
import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/recording_models.dart';

/// A recordings call refused by the server (one value per contracts `RECORDING_ERROR_CODES`) or no
/// network ([RecordingFailure.offline]). [problem] carries `comment_rejected`'s reason (`link`,
/// `phone`, `blocked_word`, `mention`, `too_short`, `too_long`, `invalid_chars`).
class RecordingException implements Exception {
  const RecordingException(this.failure, {this.status, this.problem});
  final RecordingFailure failure;
  final int? status;
  final String? problem;

  /// Caps the server answers with their own stable code (429 included): a retry before the cap
  /// resets is refused again, so these are never queued or retried on their own.
  static const hardLimits = {
    RecordingFailure.dailyLimit,
    RecordingFailure.commentRateLimited,
    RecordingFailure.rateLimited,
  };

  /// Worth trying again later: no network, the server busy, a timeout, or a gateway's generic 429
  /// (never one of the [hardLimits]).
  bool get transient {
    if (failure == RecordingFailure.offline) return true;
    if (hardLimits.contains(failure)) return false;
    final s = status;
    return s != null && (s >= 500 || s == 429 || s == 408);
  }

  static RecordingException from(Object e) {
    if (e is RecordingException) return e;
    if (e is OfflineException) return const RecordingException(RecordingFailure.offline);
    if (e is ApiException) {
      final details = e.details;
      final problem = details is Map ? details['problem'] as String? : null;
      final f = RecordingFailure.fromCode(e.code);
      // A 404 from any recordings path is gone (deleted, blocked, made private, moderated).
      final failure = f == RecordingFailure.unknown && e.status == 404 ? RecordingFailure.notFound : f;
      return RecordingException(failure, status: e.status, problem: problem);
    }
    return const RecordingException(RecordingFailure.unknown);
  }

  @override
  String toString() => 'RecordingException(${failure.code}, $status, $problem)';
}

/// The «تلاواتي» API (docs/API.md › Recordings, `services/api/src/routes/public/recordings.routes.ts`).
///
/// The owner's list is cached on the device (`recordings.mine.v1`) so the Profile section paints at
/// once; audio is fetched with the session (`ApiClient.getBytes`) into app storage
/// (`recordings/cache/<id>.m4a`) and played from there. Everything here is wiped with the account
/// ([wipe], from the session's forget path). Nothing is ever sent to analytics or ad sinks.
class RecordingsRepository {
  RecordingsRepository({required this.api, required this.store, required this.root});

  final ApiClient api;
  final KvStore store;
  final Future<Directory> Function() root;

  static const mineKey = 'recordings.mine.v1';
  static const mePath = '/v1/me/recordings';

  /// A 30-second clip is ≈ 120 KB: on a slow mobile link that is longer than the API's usual 12 s.
  static const uploadTimeout = Duration(seconds: 60);

  /// KV keys holding account data (wiped on sign-out and erasure).
  static const wipedKeys = [mineKey, 'recordings.drafts.v1', wordsKey];

  /// The on-device check's word timings per recording id: karaoke for a private recording, which
  /// the server never verifies (so its `words` stay null). Device-only, wiped with the account.
  static const wordsKey = 'recordings.words.v1';

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on Object catch (e) {
      throw RecordingException.from(e);
    }
  }

  /* ------------------------------------------------------------ owner */

  Future<MyRecordings?> cachedMine() async {
    final raw = await store.read(mineKey);
    if (raw == null) return null;
    try {
      return MyRecordings.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  Future<void> _cache(MyRecordings m) => store.write(mineKey, jsonEncode(m.toJson()));

  /// GET /v1/me/recordings (cached).
  Future<MyRecordings> fetchMine() => _call(() async {
        final m = MyRecordings.fromJson(((await api.get(mePath)) as Map).cast<String, dynamic>());
        await _cache(m);
        return m;
      });

  /// POST /v1/me/recordings (multipart `meta` + `audio`) → 202 with the new recording.
  Future<Recording> upload({
    required int surah,
    required int fromAyah,
    required int toAyah,
    required int durationMs,
    required List<int> audio,
    RecordingVisibility visibility = RecordingVisibility.private,
    bool commentsOn = true,
    double? clientScore,
    List<RecordingWord>? clientWords,
    String? clientId,
  }) =>
      _call(() async {
        final shared = visibility != RecordingVisibility.private;
        final meta = <String, Object?>{
          // The take's id on this phone (contracts `clientId`): the server answers a repeat of the
          // same take with the recording it already kept.
          if (clientId != null) 'clientId': clientId,
          'surah': surah,
          'fromAyah': fromAyah,
          'toAyah': toAyah,
          'durationMs': durationMs.clamp(1, kRecordingMaxMs + 250),
          'visibility': visibility.code,
          'commentsOn': commentsOn,
          // The on-device pre-check travels only with a shared upload (a reviewer's diagnostics).
          if (shared && clientScore != null) 'clientScore': double.parse(clientScore.clamp(0, 1).toStringAsFixed(3)),
          if (shared && clientWords != null && clientWords.isNotEmpty) 'clientWords': [for (final w in clientWords.take(400)) w.toJson()],
        };
        final json = await api.postMultipart(
          mePath,
          [
            MultipartPart.json('meta', meta),
            MultipartPart('audio', audio, contentType: RecordingFormat.mime, filename: 'recitation.m4a'),
          ],
          timeout: uploadTimeout,
        );
        final r = Recording.fromJson((json as Map).cast<String, dynamic>());
        await _upsert(r);
        return r;
      });

  /// PATCH /v1/me/recordings/:id — visibility (members/public starts the AI check), comments, position.
  Future<Recording> patch(String id, {RecordingVisibility? visibility, bool? commentsOn, int? position}) => _call(() async {
        final json = await api.patch('$mePath/$id', {
          if (visibility != null) 'visibility': visibility.code,
          if (commentsOn != null) 'commentsOn': commentsOn,
          if (position != null) 'position': position,
        });
        final r = Recording.fromJson((json as Map).cast<String, dynamic>());
        await _upsert(r);
        return r;
      });

  /// DELETE /v1/me/recordings/:id — gone with its audio, reactions and comments.
  Future<void> delete(String id) => _call(() async {
        await api.delete('$mePath/$id');
        final m = await cachedMine();
        if (m != null) {
          final rest = [for (final r in m.items) if (r.id != id) r];
          await _cache(MyRecordings(items: [for (final (i, r) in rest.indexed) r.copyWith(position: i + 1)], leftToday: m.leftToday));
        }
        await _dropAudio(id);
      });

  Future<void> _upsert(Recording r) async {
    final m = await cachedMine() ?? MyRecordings.empty;
    final items = [for (final x in m.items) if (x.id != r.id) x, r]..sort((a, b) => a.position.compareTo(b.position));
    await _cache(MyRecordings(items: items.take(kProfileRecordingsMax).toList(), leftToday: m.leftToday));
  }

  Future<Map<String, List<RecordingWord>>> _localWords() async {
    final raw = await store.read(wordsKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries) e.key as String: RecordingWord.listFrom(e.value) ?? const [],
      };
    } on Object {
      return {};
    }
  }

  /// Keeps [words] for the recording [id] on this phone (at most the profile's recordings).
  Future<void> saveLocalWords(String id, List<RecordingWord> words) async {
    if (words.isEmpty) return;
    final all = await _localWords();
    all[id] = words;
    final mine = (await cachedMine())?.items.map((r) => r.id).toSet();
    if (mine != null) all.removeWhere((k, _) => k != id && !mine.contains(k));
    await store.write(wordsKey, jsonEncode({for (final e in all.entries) e.key: [for (final w in e.value) w.toJson()]}));
  }

  /// The on-device timings kept for [id], if any.
  Future<List<RecordingWord>?> localWords(String id) async => (await _localWords())[id];

  /* ---------------------------------------------------------- members */

  /// GET /v1/community/members/:handle/recordings.
  Future<MemberRecordings> member(String handle) => _call(() async {
        final json = await api.get('/v1/community/members/${Uri.encodeComponent(handle)}/recordings');
        return MemberRecordings.fromJson((json as Map).cast<String, dynamic>());
      });

  /// PUT /v1/recordings/:id/reaction (set or change) → the new counts.
  Future<ReactionState> react(String id, ReactionKind kind) => _call(() async {
        final json = await api.put('/v1/recordings/$id/reaction', {'kind': kind.code});
        return ReactionState.fromJson((json as Map).cast<String, dynamic>());
      });

  /// DELETE /v1/recordings/:id/reaction.
  Future<ReactionState> unreact(String id) => _call(() async {
        final json = await api.delete('/v1/recordings/$id/reaction');
        return ReactionState.fromJson((json as Map).cast<String, dynamic>());
      });

  /// GET /v1/recordings/:id/comments?cursor= — newest first, [kCommentsPageSize] a page.
  Future<RecordingCommentsPage> comments(String id, {String? cursor}) => _call(() async {
        final json = await api.get('/v1/recordings/$id/comments', query: cursor == null ? null : {'cursor': cursor});
        return RecordingCommentsPage.fromJson((json as Map).cast<String, dynamic>());
      });

  /// POST /v1/recordings/:id/comments → 201 with the comment.
  Future<RecordingComment> postComment(String id, String text) => _call(() async {
        final json = await api.post('/v1/recordings/$id/comments', {'text': text});
        return RecordingComment.fromJson((json as Map).cast<String, dynamic>());
      });

  /// DELETE /v1/recordings/:id/comments/:cid (the author or the recording's owner).
  Future<void> deleteComment(String id, String commentId) => _call(() => api.delete('/v1/recordings/$id/comments/$commentId'));

  Future<void> reportRecording(String id, RecordingReportReason reason) =>
      _call(() => api.post('/v1/recordings/$id/report', {'reason': reason.code}));

  Future<void> reportComment(String id, String commentId, RecordingReportReason reason) =>
      _call(() => api.post('/v1/recordings/$id/comments/$commentId/report', {'reason': reason.code}));

  /* ------------------------------------------------------------ audio */

  Future<Directory> _dir(String name) async {
    final d = Directory('${(await root()).path}${Platform.pathSeparator}recordings${Platform.pathSeparator}$name');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Where drafts (takes not uploaded yet) live.
  Future<Directory> draftsDir() => _dir('drafts');

  /// The owner's own recording as a local file: fetched once with the session, then played from
  /// disk (gone with [delete] and [wipe]).
  Future<File> audioFile(String id, String audioPath) => _call(() async {
        final f = File('${(await _dir('cache')).path}${Platform.pathSeparator}$id.m4a');
        if (f.existsSync() && f.lengthSync() > 0) return f;
        final bytes = await api.getBytes(audioPath);
        await f.writeAsBytes(bytes, flush: true);
        return f;
      });

  /// Another member's recording, fetched fresh for this listen only (`recordings/listen/`): never
  /// kept beyond it, so a recording its owner deleted or made private, a moderator removed, or a
  /// block hid is not left on this phone. Only the clip being played is there; [clearListened]
  /// empties the folder when the listener or the member's sheet closes.
  Future<File> memberAudioFile(String id, String audioPath) => _call(() async {
        final dir = await _dir('listen');
        await _clear(dir);
        final bytes = await api.getBytes(audioPath);
        final f = File('${dir.path}${Platform.pathSeparator}$id.m4a');
        f.writeAsBytesSync(bytes, flush: true);
        return f;
      });

  /// Drops every member clip fetched for listening.
  Future<void> clearListened() async => _clear(await _dir('listen'));

  Future<void> _clear(Directory dir) async {
    if (!dir.existsSync()) return;
    for (final e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort (a file the player still holds goes next time)
      }
    }
  }

  Future<void> _dropAudio(String id) async {
    final f = File('${(await _dir('cache')).path}${Platform.pathSeparator}$id.m4a');
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } on FileSystemException {
        // best effort
      }
    }
  }

  /* ------------------------------------------------------------- wipe */

  /// Sign-out and erasure: the cached list, drafts and every audio file on this phone.
  Future<void> wipe() async {
    for (final k in wipedKeys) {
      await store.delete(k);
    }
    final d = Directory('${(await root()).path}${Platform.pathSeparator}recordings');
    if (d.existsSync()) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        // best effort
      }
    }
  }
}
