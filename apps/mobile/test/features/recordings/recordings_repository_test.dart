import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/features/recordings/data/recording_drafts.dart';
import 'package:yaqeen/features/recordings/data/recordings_repository.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';

import 'recordings_rig.dart';

/// The multipart body's parts by name (headers + bytes), read back as the server's parser does.
Map<String, ({String headers, List<int> data})> parts(http.Request req) {
  final type = req.headers['Content-Type']!;
  final boundary = RegExp('boundary=(.+)').firstMatch(type)!.group(1)!;
  final body = latin1.decode(req.bodyBytes);
  final out = <String, ({String headers, List<int> data})>{};
  for (final chunk in body.split('--$boundary')) {
    if (chunk.isEmpty || chunk.startsWith('--')) continue;
    final at = chunk.indexOf('\r\n\r\n');
    final headers = chunk.substring(2, at);
    final data = chunk.substring(at + 4, chunk.length - 2);
    final name = RegExp('name="([^"]+)"').firstMatch(headers)!.group(1)!;
    out[name] = (headers: headers, data: latin1.encode(data));
  }
  return out;
}

void main() {
  final created = recFixture('my_recordings.json')['items'][0] as Map<String, dynamic>;

  RecordingsRepository repoOf(RecordingsRig rig) => RecordingsRepository(api: rig.api, store: rig.kv, root: () async => rig.dir);

  group('upload', () {
    test('multipart: meta JSON + the .m4a as audio/mp4; device check only with a shared upload', () async {
      final rig = RecordingsRig(routes: {'POST /v1/me/recordings': (_) => jsonResponse({...created, 'status': 'processing'}, 202)});
      final repo = repoOf(rig);
      final r = await repo.upload(
        surah: 1,
        fromAyah: 1,
        toAyah: 4,
        durationMs: 9800,
        audio: const [0, 0, 0, 24, 102, 116, 121, 112],
        visibility: RecordingVisibility.members,
        clientScore: 0.93333,
        clientWords: const [RecordingWord(ayah: 1, index: 0, startMs: 10, endMs: 400)],
      );
      expect(r.status, RecordingStatus.processing);
      final req = rig.requests['POST /v1/me/recordings']!;
      expect(req.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
      final p = parts(req);
      final meta = jsonDecode(utf8.decode(p['meta']!.data)) as Map<String, dynamic>;
      expect(meta, {
        'surah': 1,
        'fromAyah': 1,
        'toAyah': 4,
        'durationMs': 9800,
        'visibility': 'members',
        'commentsOn': true,
        'clientScore': 0.933,
        'clientWords': [
          {'ayah': 1, 'index': 0, 'startMs': 10, 'endMs': 400},
        ],
      });
      expect(p['meta']!.headers, contains('Content-Type: application/json'));
      expect(p['audio']!.headers, contains('Content-Type: audio/mp4'));
      expect(p['audio']!.headers, contains('filename="recitation.m4a"'));
      expect(p['audio']!.data, const [0, 0, 0, 24, 102, 116, 121, 112]);
      // Cached for the Profile section.
      expect((await repo.cachedMine())!.items.single.id, r.id);
    });

    test('a private upload never carries the on-device check', () async {
      final rig = RecordingsRig(routes: {'POST /v1/me/recordings': (_) => jsonResponse({...created, 'status': 'private_ready', 'visibility': 'private'}, 202)});
      await repoOf(rig).upload(surah: 1, fromAyah: 1, toAyah: 4, durationMs: 9800, audio: const [1], clientScore: 0.9);
      final meta = jsonDecode(utf8.decode(parts(rig.requests['POST /v1/me/recordings']!)['meta']!.data)) as Map;
      expect(meta.containsKey('clientScore'), isFalse);
      expect(meta['visibility'], 'private');
    });
  });

  group('status and error codes', () {
    test('every server code maps to its failure (and 404 is gone)', () async {
      for (final f in RecordingFailure.serverCodes) {
        final status = switch (f) {
          RecordingFailure.tooLarge => 413,
          RecordingFailure.limit || RecordingFailure.notPublic => 409,
          RecordingFailure.dailyLimit || RecordingFailure.commentRateLimited || RecordingFailure.rateLimited => 429,
          RecordingFailure.notFound => 404,
          RecordingFailure.attestationRequired ||
          RecordingFailure.communityRequired ||
          RecordingFailure.communityBanned ||
          RecordingFailure.accountRequired ||
          RecordingFailure.blocked ||
          RecordingFailure.ownRecording ||
          RecordingFailure.commentsOff ||
          RecordingFailure.featureOff =>
            403,
          _ => 400,
        };
        final rig = RecordingsRig(routes: {'PATCH /v1/me/recordings/x': (_) => errorResponse(status, f.code)});
        await expectLater(
          repoOf(rig).patch('x', visibility: RecordingVisibility.members),
          throwsA(isA<RecordingException>().having((e) => e.failure, 'failure', f).having((e) => e.status, 'status', status)),
        );
      }
    });

    test('comment_rejected carries its reason; transient vs permanent', () async {
      final rig = RecordingsRig(routes: {
        'POST /v1/recordings/r1/comments': (_) => errorResponse(400, 'comment_rejected', details: {'problem': 'link'}),
      },);
      final e = await repoOf(rig).postComment('r1', 'see example.com').then<RecordingException?>((_) => null, onError: (Object e) => e as RecordingException);
      expect(e!.failure, RecordingFailure.commentRejected);
      expect(e.problem, 'link');
      expect(e.transient, isFalse);
      expect(const RecordingException(RecordingFailure.offline).transient, isTrue);
      expect(const RecordingException(RecordingFailure.unknown, status: 503).transient, isTrue);
      expect(const RecordingException(RecordingFailure.dailyLimit, status: 429).transient, isTrue);
      expect(RecordingException.from(ApiException(404, 'not_found')).failure, RecordingFailure.notFound);
      expect(RecordingException.from(const OfflineException()).failure, RecordingFailure.offline);
    });

    test('statuses parse from the list (and the list is cached)', () async {
      final rig = RecordingsRig(routes: {'GET /v1/me/recordings': (_) => jsonResponse(recFixture('my_recordings.json'))});
      final repo = repoOf(rig);
      final m = await repo.fetchMine();
      expect([for (final r in m.items) r.status], [RecordingStatus.approved, RecordingStatus.processing, RecordingStatus.rejected]);
      expect(m.items[0].live, isTrue);
      expect(m.items[1].pending, isTrue);
      expect(m.items[2].shareable, isFalse);
      expect((await repo.cachedMine())!.leftToday, 7);
    });
  });

  group('members, reactions, comments, reports', () {
    test('paths and bodies follow the API', () async {
      final rig = RecordingsRig(routes: {
        'GET /v1/community/members/ahmed-4821/recordings': (_) => jsonResponse(memberRecordingsFixture()),
        'PUT /v1/recordings/r1/reaction': (_) => jsonResponse(recFixture('reaction_state.json')),
        'DELETE /v1/recordings/r1/reaction': (_) => jsonResponse({
              'reactions': {'mashallah': 4, 'barakallah': 0, 'ahsant': 0},
              'myReaction': null,
            }),
        'GET /v1/recordings/r1/comments': (_) => jsonResponse(recFixture('comments.json')),
        'DELETE /v1/recordings/r1/comments/c1': (_) => http.Response('', 204),
        'POST /v1/recordings/r1/report': (_) => http.Response('', 204),
        'POST /v1/recordings/r1/comments/c1/report': (_) => http.Response('', 204),
      },);
      final repo = repoOf(rig);
      expect((await repo.member('ahmed-4821')).items, hasLength(1));
      expect((await repo.react('r1', ReactionKind.mashallah)).myReaction, ReactionKind.mashallah);
      expect(jsonDecode(rig.requests['PUT /v1/recordings/r1/reaction']!.body), {'kind': 'mashallah'});
      expect((await repo.unreact('r1')).myReaction, isNull);
      await repo.comments('r1', cursor: 'abc');
      expect(rig.calls, contains('GET /v1/recordings/r1/comments?cursor=abc'));
      await repo.deleteComment('r1', 'c1');
      await repo.reportRecording('r1', RecordingReportReason.notRecitation);
      expect(jsonDecode(rig.requests['POST /v1/recordings/r1/report']!.body), {'reason': 'not_recitation'});
      await repo.reportComment('r1', 'c1', RecordingReportReason.spam);
      expect(jsonDecode(rig.requests['POST /v1/recordings/r1/comments/c1/report']!.body), {'reason': 'spam'});
    });

    test('audio is fetched once with the session, then played from disk', () async {
      var fetched = 0;
      final rig = RecordingsRig(routes: {
        'GET /v1/recordings/r1/audio': (_) {
          fetched++;
          return http.Response.bytes([1, 2, 3], 200);
        },
      },);
      final repo = repoOf(rig);
      final a = await repo.audioFile('r1', '/v1/recordings/r1/audio');
      final b = await repo.audioFile('r1', '/v1/recordings/r1/audio');
      expect(a.path, b.path);
      expect(await a.readAsBytes(), [1, 2, 3]);
      expect(fetched, 1);
    });
  });

  group('drafts (outbox for takes)', () {
    Future<RecordingDraft> draft(RecordingsRig rig, {DraftState state = DraftState.queued}) async {
      final f = File('${rig.dir.path}/take.m4a')..writeAsBytesSync([9, 9]);
      return RecordingDraft(
        id: 'd1',
        surah: 112,
        fromAyah: 1,
        toAyah: 4,
        durationMs: 7000,
        path: f.path,
        visibility: RecordingVisibility.private,
        commentsOn: true,
        createdAt: rig.now,
        state: state,
      );
    }

    test('offline keeps it queued with backoff; back online it uploads and the file goes', () async {
      final rig = RecordingsRig(routes: {'POST /v1/me/recordings': (_) => jsonResponse({...created, 'status': 'private_ready'}, 202)});
      final drafts = RecordingDrafts(store: rig.kv, repo: repoOf(rig), now: () => rig.now, random: _Fixed());
      final d = await draft(rig);
      await drafts.add(d);
      rig.offlineAll = true;
      expect(await drafts.flush(), isEmpty);
      expect((await drafts.all()).single.state, DraftState.queued);
      rig.offlineAll = false;
      // Within the backoff window nothing is sent unless forced.
      expect(await drafts.flush(), isEmpty);
      final sent = await drafts.flush(force: true);
      expect(sent.single.id, created['id']);
      expect(await drafts.all(), isEmpty);
      expect(File(d.path).existsSync(), isFalse);
    });

    test('a refusal marks it failed with the code (kept for the person to decide)', () async {
      final rig = RecordingsRig(routes: {'POST /v1/me/recordings': (_) => errorResponse(409, 'recordings_limit')});
      final drafts = RecordingDrafts(store: rig.kv, repo: repoOf(rig), now: () => rig.now);
      await drafts.add(await draft(rig));
      await drafts.flush(force: true);
      final d = (await drafts.all()).single;
      expect(d.state, DraftState.failed);
      expect(d.failure, RecordingFailure.limit);
    });

    test('local drafts (a guest\'s) are never uploaded by the queue', () async {
      final rig = RecordingsRig(routes: {'POST /v1/me/recordings': (_) => jsonResponse(created, 202)});
      final drafts = RecordingDrafts(store: rig.kv, repo: repoOf(rig), now: () => rig.now);
      await drafts.add(await draft(rig, state: DraftState.local));
      expect(await drafts.flush(force: true), isEmpty);
      expect(rig.calls, isEmpty);
    });

    test('wipe removes the list, drafts, timings and every file', () async {
      final rig = RecordingsRig(routes: {'GET /v1/me/recordings': (_) => jsonResponse(recFixture('my_recordings.json'))});
      final repo = repoOf(rig);
      await repo.fetchMine();
      await repo.saveLocalWords(created['id'] as String, const [RecordingWord(ayah: 1, index: 0, startMs: 0, endMs: 1)]);
      await RecordingDrafts(store: rig.kv, repo: repo).add(await draft(rig));
      (await repo.draftsDir()).createSync(recursive: true);
      await repo.wipe();
      for (final k in RecordingsRepository.wipedKeys) {
        expect(await rig.kv.read(k), isNull, reason: k);
      }
      expect(Directory('${rig.dir.path}/recordings').existsSync(), isFalse);
    });
  });
}

/// Full jitter pinned near its ceiling, so the backoff window is never ~0.
class _Fixed implements Random {
  @override
  double nextDouble() => 0.9;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}
