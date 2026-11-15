import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';
import 'package:yaqeen/features/recordings/domain/client_check.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';
import 'package:yaqeen/features/recordings/domain/verse_selection.dart';
import 'package:yaqeen/features/recordings/presentation/verse_words_view.dart';

import 'recordings_rig.dart';

void main() {
  final q = quranData();

  group('duration estimate', () {
    test('≈ 2.2 words a second', () {
      expect(kRecitationWordsPerSecond, 2.2);
      expect(estimateFor(22), const Duration(seconds: 10));
      expect(estimateFor(0), Duration.zero);
    });

    test('fit against the 30-second limit', () {
      expect(fitOf(const Duration(seconds: 10)), RangeFit.ok);
      expect(fitOf(const Duration(seconds: 24)), RangeFit.near); // 80 %
      expect(fitOf(const Duration(seconds: 30)), RangeFit.near);
      expect(fitOf(const Duration(milliseconds: 30001)), RangeFit.over);
      expect(fitOf(const Duration(seconds: 36)), RangeFit.over); // 120 % is still allowed
      expect(fitOf(const Duration(milliseconds: 36001)), RangeFit.blocked);
      expect(RangeFit.over.canRecord, isTrue);
      expect(RangeFit.blocked.canRecord, isFalse);
    });

    test('words are counted like the recogniser counts them (marks excluded)', () {
      expect(wordCount(q.text(const AyahRef(112, 1))), 4);
      // A pause sign standing alone is not a word.
      expect(wordCount('ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ هُدٗى'), RecitationAligner.words('ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ هُدٗى').length);
    });
  });

  group('range selection', () {
    test('a drag spans the anchor to the finger, either way', () {
      var s = VerseSelection.single(q, const AyahRef(112, 2));
      expect((s.from, s.to), (2, 2));
      s = s.dragTo(const AyahRef(112, 4));
      expect((s.from, s.to), (2, 4));
      s = s.dragTo(const AyahRef(112, 1));
      expect((s.from, s.to), (1, 2)); // the anchor stays at 2
      expect(s.passage, const Passage(112, 1, 2));
    });

    test('one surah only: another surah is ignored', () {
      final s = VerseSelection.single(q, const AyahRef(112, 4));
      expect(s.dragTo(const AyahRef(113, 1)), same(s));
    });

    test('handles stay inside the surah and never cross', () {
      var s = VerseSelection.ofPassage(q, const Passage(112, 2, 3));
      expect(s.moveStart(-5).from, 1);
      expect(s.moveStart(5).from, 3); // never past the end
      expect(s.moveEnd(9).to, 4); // never past the surah
      s = s.moveEnd(-9);
      expect((s.from, s.to), (2, 2));
    });

    test('the estimate follows the words; a long range is blocked and trims to fit', () {
      final ikhlas = VerseSelection.ofPassage(q, const Passage(112, 1, 4));
      expect(ikhlas.words, 15);
      expect(ikhlas.fit, RangeFit.ok);
      final long = VerseSelection.single(q, const AyahRef(2, 282));
      expect(long.fit, RangeFit.blocked);
      final kursi = VerseSelection.ofPassage(q, const Passage(2, 255, 257));
      expect(kursi.fit, RangeFit.blocked);
      final trimmed = kursi.trimmedToFit();
      expect(trimmed.from, 255);
      expect(trimmed.fit.index, lessThan(RangeFit.over.index));
    });
  });

  group('on-device check (advisory)', () {
    List<RecognizedWord> heard(List<String> words) => [for (final (i, w) in words.indexed) RecognizedWord(w, start: i * 0.5, end: i * 0.5 + 0.4)];
    final ikhlas = const Passage(112, 1, 4).expected(q);
    final all = [for (final (_, t) in ikhlas) ...RecitationAligner.words(t)];

    test('every word heard: clean, full coverage, a timing per word', () {
      final c = ClientCheck.of(ikhlas, heard(all));
      expect(c.score, 1);
      expect(c.verdict, ClientVerdict.clean);
      expect(c.flaggedAyat, isEmpty);
      expect(c.words, hasLength(15));
      expect(c.words.first, isA<RecordingWord>().having((w) => w.ayah, 'ayah', 1).having((w) => w.index, 'index', 0).having((w) => w.startMs, 'start', 0));
      expect(c.words.last.endMs, greaterThan(c.words.last.startMs));
    });

    test('a skipped word flags its ayah («تخطّيت كلمة في الآية 3»)', () {
      final missing = [...all]..removeAt(6 + 1); // ayah 3, second word
      final c = ClientCheck.of(ikhlas, heard(missing));
      expect(c.verdict, ClientVerdict.mostly);
      expect(c.flaggedAyat, [const AyahRef(112, 3)]);
      expect(c.score, closeTo(14 / 15, 1e-9));
    });

    test('the isti\'adha and Basmala before the passage are not counted', () {
      final c = ClientCheck.of(ikhlas, heard(['أعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم', 'بسم', 'الله', 'الرحمن', 'الرحيم', ...all]));
      expect(c.score, 1);
      expect(c.heardCount, 15);
    });

    test('other verses: not matching; silence: unclear', () {
      final falaq = [for (final (_, t) in const Passage(113, 1, 5).expected(q)) ...RecitationAligner.words(t)];
      expect(ClientCheck.of(ikhlas, heard(falaq)).verdict, ClientVerdict.notMatching);
      expect(ClientCheck.of(ikhlas, const []).verdict, ClientVerdict.unclear);
    });

    test('thresholds mirror contracts RECITATION_MATCH', () {
      expect(RecitationMatch.approveCoverage, 0.75);
      expect(RecitationMatch.rejectCoverage, 0.35);
    });
  });

  group('karaoke', () {
    const words = [
      RecordingWord(ayah: 1, index: 0, startMs: 300, endMs: 700),
      RecordingWord(ayah: 1, index: 1, startMs: 800, endMs: 1200),
      RecordingWord(ayah: 2, index: 0, startMs: 2300, endMs: 2700),
    ];

    test('ended words are lit, the playing one current, the rest plain', () {
      const at = Duration(milliseconds: 900);
      expect(Karaoke.lookAt(words, at, 1, 0), WordLook.lit);
      expect(Karaoke.lookAt(words, at, 1, 1), WordLook.current);
      expect(Karaoke.lookAt(words, at, 2, 0), WordLook.plain);
      expect(Karaoke.lookAt(words, at, 1, 5), WordLook.plain); // no timing for it
      expect(Karaoke.lookAt(words, at, 1, 0, started: false), WordLook.plain);
      expect(Karaoke.lookAt(null, at, 1, 0), WordLook.plain);
    });

    test('the current word is the latest that started', () {
      expect(Karaoke.currentAt(words, const Duration(milliseconds: 100)), isNull);
      expect(Karaoke.currentAt(words, const Duration(milliseconds: 1000)), (1, 1));
      expect(Karaoke.currentAt(words, const Duration(seconds: 3)), (2, 0));
    });
  });
}
