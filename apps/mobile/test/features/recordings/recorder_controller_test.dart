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
