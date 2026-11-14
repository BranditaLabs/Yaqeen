import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/hifz/presentation/voice_rehearsal.dart';
import 'package:yaqeen/features/quran/domain/mushaf_layout.dart';
import 'package:yaqeen/features/quran/domain/page_geometry.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/recite/domain/recite_progress.dart';
import 'package:yaqeen/features/recite/presentation/recite_end_card.dart';
import 'package:yaqeen/features/recite/presentation/recite_overlay.dart';

import '../helpers/harness.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final ayah = [(const AyahRef(112, 1), q.text(const AyahRef(112, 1)))];

  /// One printed line: the four words of 112:1 and its end marker.
  PageGeometry geometry() => PageGeometry.compute(
        lines: [
          TextLine([
            for (var p = 1; p <= 4; p++) MushafWord('w$p', const AyahRef(112, 1), p, MushafWordKind.word),
            const MushafWord('e', AyahRef(112, 1), 5, MushafWordKind.end),
          ]),
          for (var i = 1; i < MushafLayout.linesPerPage; i++) const EmptyLine(),
        ],
        size: const Size(320, 600),
        unitWidth: (_) => 2,
      );

  Widget layer(ReciteView view, {bool reduce = false}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: 320,
            height: 600,
            child: ReciteLayer(geometry: geometry(), family: 'Amiri', colors: MushafColors.of(MushafTheme.paper), night: false, view: view),
          ),
        ),
      );

  ReciteLayerState state(WidgetTester tester) => tester.state<ReciteLayerState>(find.byType(ReciteLayer));

  group('hidden words revealed by the voice', () {
    testWidgets('a recognised word fades and rises into place, then settles', (tester) async {
      final p = ReciteProgress(ayah);
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 0)));
      expect(state(tester).shown, isEmpty, reason: 'every word starts as a pill');
      p.update(RecognitionUpdate.text('قل هو'), const Duration(seconds: 1));
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 1)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state(tester).shown, {0, 1});
      expect(state(tester).animating, isTrue);
      await tester.pumpAndSettle();
      expect(state(tester).animating, isFalse);
    });

    testWidgets('reduce motion: words simply appear, the glow jumps — settled at once', (tester) async {
      final p = ReciteProgress(ayah);
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 0), reduce: true));
      p.update(RecognitionUpdate.text('قل هو الله'), const Duration(seconds: 1));
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 1), reduce: true));
      expect(state(tester).shown, {0, 1, 2});
      expect(state(tester).animating, isFalse);
      await tester.pumpAndSettle();
      expect(state(tester).shown, {0, 1, 2});
    });

    testWidgets('«سمّع ثم تحقّق»: all marks arrive together and are revealed one after another', (tester) async {
      final p = ReciteProgress(ayah);
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 0, live: false)));
      p.update(RecognitionUpdate.text('قل هو الله احد', isFinal: true), const Duration(seconds: 3));
      await tester.pumpWidget(layer(ReciteView(progress: p, version: 1, live: false)));
      await tester.pump(const Duration(milliseconds: 1));
      expect(state(tester).shown, {0, 1, 2, 3});
      expect(state(tester).animating, isTrue);
      await tester.pumpAndSettle();
      expect(state(tester).animating, isFalse);
    });
  });

  testWidgets('end card: ayat · notes · helps · time, a note plays its ayah, «سمّع الملاحظات فقط»', (tester) async {
    final p = ReciteProgress(const Passage(112, 1, 4).expected(q));
    p.update(RecognitionUpdate.text('قل هو الله واحد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احد'), const Duration(seconds: 83));
    p.finish();
    final played = <AyahRef>[];
    ReciteEndAction? action;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => action = await showReciteEndCard(context, progress: p, onPlay: played.add),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('أتممت التسميع'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // ayat
    expect(find.text('1:23'), findsOneWidget); // time, Western digits
    expect(find.textContaining('تنبيه:'), findsOneWidget);
    expect(find.textContaining('خطأ'), findsNothing);
    expect(find.text('يتحقّق من الكلمات، لا من التجويد'), findsOneWidget);
    await tester.tap(find.textContaining('تنبيه:'));
    expect(played, [const AyahRef(112, 1)]);
    await tester.tap(find.text('سمّع الملاحظات فقط'));
    await tester.pumpAndSettle();
    expect(action, ReciteEndAction.retryFlagged);
  });

  group('voice-aware «تحفيظ»', () {
    ProviderContainer container(ScriptedRecitationEngine engine) {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          recitationEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(c.dispose);
      c.listen(voiceRehearsalProvider, (_, __) {});
      return c;
    }

    const passage = Passage(112, 1, 4);
    final full = [for (final r in passage.range) q.text(r)].join(' ');

    test('«تكرار ×10»: each full recitation counts once; one with two notes does not', () async {
      final engine = ScriptedRecitationEngine();
      final c = container(engine);
      var count = 0;
      await c.read(voiceRehearsalProvider.notifier).listenForRepeats(passage, q, onRepeat: () => count++);
      expect(engine.listening, isTrue);
      expect(c.read(voiceRehearsalProvider).mode, RehearsalMode.repeats);
      engine.emit(full);
      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
      // The microphone stays open: the next repetition follows what is already heard.
      engine.emit('$full $full');
      await Future<void>.delayed(Duration.zero);
      expect(count, 2);
      final slips = full.split(' ')..[3] = 'واحد'..[14] = 'كلمة';
      engine.emit('$full $full ${slips.join(' ')}');
      await Future<void>.delayed(Duration.zero);
      expect(count, 2, reason: 'two notes: the tap counter is still there');
      await c.read(voiceRehearsalProvider.notifier).stop();
      expect(engine.listening, isFalse);
    });

    test('echo («ردّد بعد القارئ»): the next ayah starts once this one is repeated, or after the wait', () async {
      final engine = ScriptedRecitationEngine();
      final c = container(engine);
      final rehearsal = c.read(voiceRehearsalProvider.notifier);
      final heard = rehearsal.echoAyah(const AyahRef(112, 1), q, timeout: const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(voiceRehearsalProvider).mode, RehearsalMode.echo);
      engine.emit(q.text(const AyahRef(112, 1)));
      expect(await heard, isTrue);
      expect(engine.listening, isFalse, reason: 'the microphone closes before the reciter plays the next ayah');
      final silent = await rehearsal.echoAyah(const AyahRef(112, 2), q, timeout: const Duration(milliseconds: 50));
      expect(silent, isFalse);
    });
  });
}
