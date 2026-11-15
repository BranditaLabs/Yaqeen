import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/asr/asr_model.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/hifz/presentation/voice_rehearsal.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';
import 'package:yaqeen/features/recite/domain/recite_progress.dart';
import 'package:yaqeen/features/recite/presentation/recite_controller.dart';

import 'quran/one_page_fakes.dart';

/// A live engine whose `stop` takes a while: the paused phrase is still being decoded.
class _SlowStopEngine extends ScriptedRecitationEngine {
  Completer<void>? gate;
  RecognitionUpdate? lastPhrase;

  @override
  Future<void> stop() async {
    final g = gate;
    if (g != null) await g.future;
    final last = lastPhrase;
    lastPhrase = null;
    if (last != null) emitUpdate(last);
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  const passage = Passage(112, 1, 4);
  final ikhlas = passage.expected(q);
  final words = [for (final r in passage.range) ...RecitationAligner.words(q.text(r))];
  String said(int from, int to) => words.sublist(from, to).join(' ');

  group('help waits for silence', () {
    test("no help while the voice is still going (the isti'adha, a phrase said again)", () {
      final p = ReciteProgress(ikhlas);
      // Five seconds of the isti'adha said slowly: tentative words keep arriving, nothing matches.
      for (var s = 1; s <= 9; s++) {
        p.update(const RecognitionUpdate(tentative: [RecognizedWord('أعوذ'), RecognizedWord('بالله')]), Duration(seconds: s));
        expect(p.tick(Duration(seconds: s)), isFalse, reason: 'speaking at ${s}s is not a silence');
      }
      expect(p.helps, 0);
      expect(p.hintOf(0), HintLevel.none);
      // Then silence: the letter at 4 s, the word at 8 s.
      expect(p.tick(const Duration(seconds: 12)), isFalse);
      expect(p.tick(const Duration(seconds: 13)), isTrue);
      expect(p.hintOf(0), HintLevel.letter);
      expect(p.tick(const Duration(seconds: 17)), isTrue);
      expect(p.helps, 1);
    });

    test('«سمّع ثم تحقّق» keeps time without any help', () {
      final p = ReciteProgress(ikhlas);
      expect(p.tick(const Duration(seconds: 30), help: false), isFalse);
      expect(p.elapsed, const Duration(seconds: 30));
      expect(p.helps, 0);
      expect(p.hintOf(0), HintLevel.none);
    });
  });

  test('only leaving the foreground stops the microphone — not the permission dialog', () {
    expect(leftForeground(AppLifecycleState.inactive), isFalse);
    expect(leftForeground(AppLifecycleState.resumed), isFalse);
    expect(leftForeground(AppLifecycleState.hidden), isTrue);
    expect(leftForeground(AppLifecycleState.paused), isTrue);
  });

  test('a store build never downloads the interim third-party export', () {
    expect(AsrModelManifest.resolve(baseUrl: '', release: true, allowInterim: false).published, isFalse);
    expect(AsrModelManifest.resolve(baseUrl: '', release: true, allowInterim: true).id, AsrModelManifest.interim.id);
    expect(AsrModelManifest.resolve(baseUrl: '', release: false, allowInterim: false).id, AsrModelManifest.interim.id);
    expect(AsrModelManifest.resolve(baseUrl: 'https://cdn.test/asr/', release: true, allowInterim: false).id, AsrModelManifest.yaqeen.id);
  });

  group('controllers', () {
    ProviderContainer container(ScriptedRecitationEngine engine) {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          recitationEngineProvider.overrideWithValue(engine),
          listenControllerProvider.overrideWith(FakeListen.new),
        ],
      );
      addTearDown(c.dispose);
      c.listen(reciteControllerProvider, (_, __) {});
      c.listen(voiceRehearsalProvider, (_, __) {});
      return c;
    }

    test('«متابعة» tapped while the pause is still closing keeps its last phrase', () async {
      final engine = _SlowStopEngine();
      final c = container(engine);
      final recite = c.read(reciteControllerProvider.notifier);
      await recite.start(passage, q);
      engine.emit(said(0, 4)); // the first ayah
      await Future<void>.delayed(Duration.zero);
      engine
        ..gate = Completer<void>()
        ..lastPhrase = RecognitionUpdate.text(said(0, 6), isFinal: true); // + «الله الصمد», decoded at the pause
      final paused = recite.pause();
      expect(c.read(reciteControllerProvider).phase, RecitePhase.paused);
      final resumed = recite.resume(); // before the pause has finished closing
      await Future<void>.delayed(Duration.zero);
      expect(engine.starts, 1, reason: 'the new session waits for the old one to close');
      engine.gate!.complete();
      await paused;
      await resumed;
      expect(engine.starts, 2);
      expect(c.read(reciteControllerProvider).progress!.follower.cursor, 6, reason: 'the paused phrase was judged');
      // The new session counts from zero again and carries on.
      engine.emit(said(6, words.length));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(reciteControllerProvider).progress!.complete, isTrue);
    });

    test('«سمّع ثم تحقّق»: the end card has the time spent reciting', () async {
      final engine = ScriptedRecitationEngine(live: false);
      final c = container(engine);
      final recite = c.read(reciteControllerProvider.notifier);
      await recite.start(passage, q);
      expect(engine.lastLive, isFalse);
      await Future<void>.delayed(ReciteController.tick * 9);
      engine.finalUpdate = RecognitionUpdate.text(words.join(' '), isFinal: true);
      await recite.finish();
      await Future<void>.delayed(Duration.zero);
      final s = c.read(reciteControllerProvider);
      expect(s.phase, RecitePhase.done);
      // Real timers (a loaded machine fires fewer ticks): any time at all — it stayed 0:00 before.
      expect(s.elapsed, greaterThan(Duration.zero));
      expect(s.helps, 0, reason: 'a recording gets no help');
    });

    test('stopping echo practice ends the wait for the user at once', () async {
      final engine = ScriptedRecitationEngine();
      final c = container(engine);
      final rehearsal = c.read(voiceRehearsalProvider.notifier);
      final heard = rehearsal.echoAyah(const AyahRef(112, 1), q, timeout: const Duration(minutes: 1));
      await Future<void>.delayed(Duration.zero);
      expect(engine.listening, isTrue);
      await rehearsal.stop();
      expect(await heard.timeout(const Duration(seconds: 1)), isFalse);
      expect(engine.listening, isFalse);
    });
  });
}
