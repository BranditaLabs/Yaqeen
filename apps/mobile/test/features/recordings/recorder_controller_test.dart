import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/platform/audio_recorder.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';
import 'package:yaqeen/features/recordings/data/recording_drafts.dart';
import 'package:yaqeen/features/recordings/domain/client_check.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';
import 'package:yaqeen/features/recordings/presentation/recorder_controller.dart';
import 'package:yaqeen/features/recordings/presentation/recordings_providers.dart';

import 'recordings_rig.dart';

/// Waits (real time) until [test] holds, up to [limit].
Future<void> until(bool Function() test, {Duration limit = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(limit);
  while (!test()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RecorderController.countInStep = const Duration(milliseconds: 5));

  const ikhlas = Passage(112, 1, 4);
  final created = recFixture('my_recordings.json')['items'][0] as Map<String, dynamic>;
  String ikhlasText() => [for (final (_, t) in ikhlas.expected(quranData())) t].join(' ');

  ({ProviderContainer c, RecordingsRig rig}) setUpRig({bool signedIn = true, PcmFakeEngine? engine, Map<String, ApiRoute>? routes}) {
    final rig = RecordingsRig(signedIn: signedIn, routes: routes);
    if (engine != null) rig.engine = engine;
    final c = rig.container();
    c.listen(recorderProvider(ikhlas), (_, __) {});
    addTearDown(c.dispose);
    return (c: c, rig: rig);
  }

  RecorderState stateOf(ProviderContainer c) => c.read(recorderProvider(ikhlas));
  RecorderController ctl(ProviderContainer c) => c.read(recorderProvider(ikhlas).notifier);

  test('a refused microphone: the denied state (the screen offers Settings)', () async {
    final s = setUpRig();
    s.rig.recorder.allowed = false;
    await ctl(s.c).begin();
    expect(stateOf(s.c).phase, RecorderPhase.denied);
    expect(s.rig.recorder.starts, 0);
  });

  test('3-2-1, then recording with the real microphone level', () async {
    final s = setUpRig();
    final counts = <int>[];
    s.c.listen(recorderProvider(ikhlas), (_, n) {
      if (n.phase == RecorderPhase.countIn) counts.add(n.countIn);
    });
    await ctl(s.c).begin();
    expect(counts.toSet(), {3, 2, 1});
    expect(stateOf(s.c).phase, RecorderPhase.recording);
    expect(stateOf(s.c).mode, FollowMode.pacing); // no model on this phone
    final levels = <double>[];
    final sub = ctl(s.c).level.listen(levels.add);
    s.rig.recorder.take!.emit(level: 0.2);
    s.rig.recorder.take!.emit(level: 0.7);
    await Future<void>.delayed(Duration.zero);
    expect(levels, [0.2, 0.7]);
    await sub.cancel();
  });

  test('stops by itself at 30 s (the limit), then review', () async {
    final s = setUpRig();
    await ctl(s.c).begin();
    s.rig.recorder.take!.emit(ms: kRecordingMaxMs);
    await until(() => stateOf(s.c).phase == RecorderPhase.review);
    final st = stateOf(s.c);
    expect(st.autoStopped, isTrue);
    expect(st.elapsed, const Duration(milliseconds: kRecordingMaxMs));
    expect(st.clip!.duration, const Duration(milliseconds: kRecordingMaxMs));
    expect(File(st.clip!.path).existsSync(), isTrue);
    expect(s.rig.recorder.take!.stopped, isTrue);
  });

  test('a tap stops early; too short a take asks for at least a verse', () async {
    final s = setUpRig();
    await ctl(s.c).begin();
    s.rig.recorder.take!.emit(ms: 400);
    await ctl(s.c).stop();
    expect(stateOf(s.c).phase, RecorderPhase.ready);
    expect(stateOf(s.c).tooShort, isTrue);
    expect(s.rig.recorder.take!.cancelled, isTrue);

    await ctl(s.c).begin();
    s.rig.recorder.take!.emit(ms: 6000);
    await ctl(s.c).stop();
    expect(stateOf(s.c).phase, RecorderPhase.review);
    expect(stateOf(s.c).autoStopped, isFalse);
  });

  test('live follow: words light from the on-device recogniser fed with the same PCM', () async {
    final engine = PcmFakeEngine();
    final s = setUpRig(engine: engine);
    await ctl(s.c).begin();
    expect(stateOf(s.c).mode, FollowMode.live);
    expect(engine.startedLive, isTrue);
    s.rig.recorder.take!.emit();
    engine.emit(spoken(ikhlasText(), n: 5));
    await Future<void>.delayed(Duration.zero);
    final st = stateOf(s.c);
    expect(st.marks.take(4), everyElement(WordMark.ok));
    expect(st.frontier, greaterThanOrEqualTo(4));
    expect(engine.pcmChunks, 1);
    // The whole take: every word → a clean advisory check with karaoke timings.
    engine.finalWords = [for (final (w, a, b) in spoken(ikhlasText())) RecognizedWord(w, start: a, end: b)];
    s.rig.recorder.take!.emit(ms: 6000);
    await ctl(s.c).stop();
    await until(() => !stateOf(s.c).checking);
    final check = stateOf(s.c).check!;
    expect(check.verdict, ClientVerdict.clean);
    expect(check.words, hasLength(15));
  });

  test('a slow phone records with the pacing guide and still checks the whole clip', () async {
    final engine = PcmFakeEngine(live: false);
    final s = setUpRig(engine: engine);
    await ctl(s.c).begin();
    expect(stateOf(s.c).mode, FollowMode.pacing);
    expect(engine.startedLive, isFalse);
    final words = spoken(ikhlasText());
    engine.finalWords = [for (final (w, a, b) in words.take(10)) RecognizedWord(w, start: a, end: b)]; // stopped after ayah 3
    s.rig.recorder.take!.emit(ms: 6000);
    await ctl(s.c).stop();
    await until(() => !stateOf(s.c).checking);
    expect(stateOf(s.c).check!.flaggedAyat.map((r) => r.ayah), [4]);
  });

  group('save', () {
    Future<void> record(ProviderContainer c, RecordingsRig rig) async {
      await ctl(c).begin();
      rig.recorder.take!.emit(ms: 7000);
      await ctl(c).stop();
      await until(() => stateOf(c).phase == RecorderPhase.review && !stateOf(c).checking);
    }

    test('a guest keeps the take on this phone (private, never uploaded)', () async {
      final s = setUpRig(signedIn: false);
      await record(s.c, s.rig);
      ctl(s.c).setVisibility(RecordingVisibility.public);
      expect(await ctl(s.c).save(), SaveOutcome.local);
      final d = (await s.c.read(recordingDraftsProvider).all()).single;
      expect(d.state, DraftState.local);
      expect(d.visibility, RecordingVisibility.private);
      expect(File(d.path).existsSync(), isTrue);
      expect(s.rig.calls, isEmpty);
    });

    test('an account uploads at once (multipart) and the file is removed', () async {
      final s = setUpRig(routes: {'POST /v1/me/recordings': (_) => jsonResponse({...created, 'status': 'private_ready', 'visibility': 'private'}, 202)});
      await record(s.c, s.rig);
      final path = stateOf(s.c).clip!.path;
      expect(await ctl(s.c).save(), SaveOutcome.uploaded);
      expect(s.rig.calls, ['POST /v1/me/recordings']);
      expect(File(path).existsSync(), isFalse);
      expect(stateOf(s.c).phase, RecorderPhase.saved);
    });

    test('offline: saved quietly and queued for later', () async {
      final s = setUpRig();
      await record(s.c, s.rig);
      s.rig.offlineAll = true;
      expect(await ctl(s.c).save(), SaveOutcome.queued);
      expect((await s.c.read(recordingDraftsProvider).all()).single.state, DraftState.queued);
    });

    test("the day's uploads used up: kept on this phone for tomorrow, never queued against the cap", () async {
      final s = setUpRig(routes: {'POST /v1/me/recordings': (_) => errorResponse(429, 'recording_daily_limit')});
      await record(s.c, s.rig);
      ctl(s.c).setVisibility(RecordingVisibility.members);
      expect(await ctl(s.c).save(), SaveOutcome.later);
      final d = (await s.c.read(recordingDraftsProvider).all()).single;
      expect(d.state, DraftState.local);
      expect(d.visibility, RecordingVisibility.members);
      expect(File(d.path).existsSync(), isTrue);
    });

    test("the upload carries the take's id; a queued retry sends the same one", () async {
      final s = setUpRig();
      await record(s.c, s.rig);
      s.rig.offlineAll = true;
      expect(await ctl(s.c).save(), SaveOutcome.queued);
      final d = (await s.c.read(recordingDraftsProvider).all()).single;
      expect(utf8.decode(s.rig.requests['POST /v1/me/recordings']!.bodyBytes), contains('"clientId":"${d.id}"'));
      s.rig.offlineAll = false;
      s.rig.routes['POST /v1/me/recordings'] = (_) => jsonResponse({...created, 'status': 'private_ready', 'visibility': 'private'}, 202);
      expect(await s.c.read(recordingDraftsProvider).flush(force: true), hasLength(1));
      expect(utf8.decode(s.rig.requests['POST /v1/me/recordings']!.bodyBytes), contains('"clientId":"${d.id}"'));
    });

    test('a gate refusal stays on the review with its code', () async {
      final s = setUpRig(routes: {'POST /v1/me/recordings': (_) => errorResponse(403, 'community_required')});
      await record(s.c, s.rig);
      ctl(s.c).setVisibility(RecordingVisibility.members);
      expect(await ctl(s.c).save(), isNull);
      expect(stateOf(s.c).phase, RecorderPhase.review);
      expect(stateOf(s.c).error, RecordingFailure.communityRequired);
      final meta = s.rig.requests['POST /v1/me/recordings']!;
      expect(utf8.decode(meta.bodyBytes), contains('"visibility":"members"'));
    });
  });

  group('one take at a time', () {
    tearDown(() => RecorderController.checkTimeout = const Duration(seconds: 25));

    test('re-recording while the last check runs: the old stop never touches the new take', () async {
      RecorderController.checkTimeout = const Duration(milliseconds: 300);
      final engine = PcmFakeEngine()..finalGate = Completer<void>(); // the old final pass never lands
      final s = setUpRig(engine: engine);
      await ctl(s.c).begin();
      s.rig.recorder.take!.emit(ms: 6000);
      final oldStop = ctl(s.c).stop();
      await until(() => stateOf(s.c).phase == RecorderPhase.review);
      expect(stateOf(s.c).checking, isTrue);
      // «أعد التسجيل» while the check of the first take still runs.
      engine.finalGate = null;
      await ctl(s.c).again();
      expect(stateOf(s.c).phase, RecorderPhase.recording);
      expect(engine.starts, 2);
      await oldStop; // its wait ended with the discard (or its timeout)
      await Future<void>.delayed(const Duration(milliseconds: 400)); // past the old stop's timeout
      // The new take still follows the voice and its check covers the whole take.
      s.rig.recorder.take!.emit();
      engine.emit(spoken(ikhlasText(), n: 5));
      await Future<void>.delayed(Duration.zero);
      expect(stateOf(s.c).marks.take(4), everyElement(WordMark.ok));
      engine.finalWords = [for (final (w, a, b) in spoken(ikhlasText())) RecognizedWord(w, start: a, end: b)];
      s.rig.recorder.take!.emit(ms: 6000);
      await ctl(s.c).stop();
      expect(stateOf(s.c).checking, isFalse);
      expect(stateOf(s.c).check!.verdict, ClientVerdict.clean);
    });

    test('«حفظ» before the on-device check finished waits for it: the karaoke timings are kept', () async {
      final engine = PcmFakeEngine()..finalGate = Completer<void>();
      final s = setUpRig(engine: engine, routes: {'POST /v1/me/recordings': (_) => jsonResponse({...created, 'status': 'private_ready', 'visibility': 'private'}, 202)});
      await ctl(s.c).begin();
      engine.finalWords = [for (final (w, a, b) in spoken(ikhlasText())) RecognizedWord(w, start: a, end: b)];
      s.rig.recorder.take!.emit(ms: 6000);
      ctl(s.c).stop().ignore();
      await until(() => stateOf(s.c).phase == RecorderPhase.review);
      expect(stateOf(s.c).checking, isTrue);
      final saving = ctl(s.c).save();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.rig.calls, isEmpty); // waiting for the check
      engine.finalGate!.complete();
      expect(await saving, SaveOutcome.uploaded);
      final words = await s.c.read(recordingsRepositoryProvider).localWords(created['id'] as String);
      expect(words, hasLength(15));
    });

    test('leaving while the engine is asked about the model: no recogniser, no timer, the take closed', () async {
      final engine = PcmFakeEngine()..availableGate = Completer<void>();
      final s = setUpRig(engine: engine);
      await until(() => ctl(s.c).words.isNotEmpty);
      final begun = ctl(s.c).begin();
      await until(() => s.rig.recorder.take != null);
      await ctl(s.c).discard(keepScreen: true);
      engine.availableGate!.complete();
      await begun;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(engine.starts, 0);
      expect(stateOf(s.c).phase, RecorderPhase.ready);
      expect(s.rig.recorder.take!.cancelled, isTrue);
    });

    test('backing out while the clip is written: the file is not left behind', () async {
      final s = setUpRig();
      await ctl(s.c).begin();
      s.rig.writeGate = Completer<void>();
      s.rig.recorder.take!.emit(ms: 6000);
      final stopping = ctl(s.c).stop();
      expect(stateOf(s.c).phase, RecorderPhase.encoding);
      await ctl(s.c).discard();
      s.rig.writeGate!.complete();
      await stopping;
      final path = s.rig.recorder.take!.stoppedAt!;
      expect(File(path).existsSync(), isFalse);
      expect(stateOf(s.c).phase, isNot(RecorderPhase.review));
    });

    test('a take on review is deleted when the screen goes without saving it', () async {
      final rig = RecordingsRig();
      final c = rig.container();
      final sub = c.listen(recorderProvider(ikhlas), (_, __) {});
      final ctl = c.read(recorderProvider(ikhlas).notifier);
      await ctl.begin();
      rig.recorder.take!.emit(ms: 6000);
      await ctl.stop();
      final path = c.read(recorderProvider(ikhlas)).clip!.path;
      expect(File(path).existsSync(), isTrue);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(File(path).existsSync(), isFalse);
      c.dispose();
    });
  });

  test('leaving cancels an open microphone', () async {
    final rig = RecordingsRig();
    final c = rig.container();
    final sub = c.listen(recorderProvider(ikhlas), (_, __) {});
    await c.read(recorderProvider(ikhlas).notifier).begin();
    final FakeVoiceTake take = rig.recorder.take!;
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(take.cancelled, isTrue);
    c.dispose();
  });
}
