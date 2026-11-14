import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/features/hifz/domain/grade_suggestion.dart';
import 'package:yaqeen/features/hifz/domain/review_scheduler.dart';
import 'package:yaqeen/features/hifz/presentation/voice_rehearsal.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';
import 'package:yaqeen/features/recite/domain/recitation_follower.dart';
import 'package:yaqeen/features/recite/domain/recite_progress.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final ikhlas = const Passage(112, 1, 4).expected(q);
  List<String> said(String s) => s.split(' ');

  RecitationFollower follower() => RecitationFollower(ExpectedWord.of(ikhlas));

  group('incremental alignment (moving cursor)', () {
    test('the cursor moves word by word as committed words arrive', () {
      final f = follower();
      final heard = <String>[];
      for (final w in said('قل هو الله احد')) {
        heard.add(w);
        f.update(heard, const []);
      }
      expect(f.cursor, 4);
      expect(f.marks.take(4), everyElement(WordMark.ok));
      expect(f.marks.skip(4), everyElement(isNull), reason: 'not reached yet');
    });

    test("the isti'adha and the Basmala before a surah are not part of the passage", () {
      final f = follower();
      // Said in pieces: nothing is judged while the opening may still be going on.
      f.update(said('أعوذ بالله'), const []);
      expect(f.cursor, 0);
      expect(f.marks, everyElement(isNull));
      f.update(said('أعوذ بالله من الشيطان الرجيم بسم الله'), const []);
      expect(f.cursor, 0);
      f.update(said('أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم قل هو الله احد الله الصمد'), const []);
      expect(f.cursor, 6);
      expect(f.marks.take(6), everyElement(WordMark.ok));
    });

    test('a different word is «تنبيه» once the voice is past it; a word not said is skipped', () {
      final f = follower();
      f.update(said('قل هو الله واحد الله الصمد'), const []);
      expect(f.marks.take(6), [WordMark.ok, WordMark.ok, WordMark.ok, WordMark.warn, WordMark.ok, WordMark.ok]);
      final g = follower();
      g.update(said('قل هو احد'), const []);
      expect(g.marks.take(4), [WordMark.ok, WordMark.ok, WordMark.skipped, WordMark.ok]);
    });

    test('a word being said is never judged half-way; tentative words only reveal', () {
      final f = follower();
      f.update(said('قل'), said('هو الله'));
      expect(f.cursor, 1);
      expect(f.provisional, {1, 2});
      expect(f.marks[1], isNull);
      expect(f.frontier, 3);
      // Something else at the cursor waits for the next match instead of a «تنبيه».
      f.update(said('قل كلمة'), const []);
      expect(f.marks[1], isNull);
      expect(f.cursor, 1);
    });

    test('repeating a phrase to correct it costs nothing', () {
      final f = follower();
      f.update(said('قل هو قل هو الله احد'), const []);
      expect(f.marks.take(4), everyElement(WordMark.ok));
      expect(f.cursor, 4);
    });

    test('a different last word is judged when listening ends', () {
      final f = follower();
      final words = [for (final (_, t) in ikhlas) ...RecitationAligner.words(t)];
      f.update([...words.take(words.length - 1), 'كلمة'], const []);
      expect(f.done, isFalse);
      f.finish();
      expect(f.done, isTrue);
      expect(f.marks.last, WordMark.warn);
      // Stopping mid-way judges nothing it did not reach.
      final g = follower()..update(said('قل هو'), const []);
      g.finish();
      expect(g.marks.skip(2), everyElement(isNull));
    });

    test('a resumed session counts its words from zero and keeps what was judged', () {
      final f = follower()..update(said('قل هو الله'), const []);
      f.newSession();
      f.update(said('احد الله'), const []);
      expect(f.cursor, 5);
      expect(f.marks.take(5), everyElement(WordMark.ok));
    });

    test('the whole-transcript alignment is unchanged', () {
      final r = RecitationAligner.align(ikhlas, 'قل هو الله احد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احد');
      expect(RecitationAligner.recitedCount(r), 4);
      expect(r.every((a) => a.ok), isTrue);
    });
  });

  group('help and summary (fake clock)', () {
    test('first letter after 4 s on a word, the whole word after 8 s (one «مساعدة»), reset by progress', () {
      final p = ReciteProgress(ikhlas);
      p.update(RecognitionUpdate.text('قل'), const Duration(seconds: 1));
      expect(p.current, 1);
      expect(p.tick(const Duration(seconds: 4)), isFalse);
      expect(p.tick(const Duration(seconds: 5)), isTrue);
      expect(p.hintOf(1), HintLevel.letter);
      expect(p.revealed(1), isFalse);
      expect(p.tick(const Duration(seconds: 9)), isTrue);
      expect(p.hintOf(1), HintLevel.word);
      expect(p.revealed(1), isTrue);
      expect(p.helps, 1);
      expect(p.tick(const Duration(seconds: 20)), isFalse, reason: 'counted once');
      // Recited after the help: heard, and the help still counts.
      p.update(RecognitionUpdate.text('قل هو'), const Duration(seconds: 21));
      expect(p.markOf(1), WordMark.ok);
      expect(p.hintOf(1), HintLevel.none);
      expect(p.helps, 1);
      expect(p.tick(const Duration(seconds: 24)), isFalse);
      expect(p.tick(const Duration(seconds: 25)), isTrue);
      expect(p.hintOf(2), HintLevel.letter);
      // A pause does not count: the help clock restarts on resume.
      p.resume(const Duration(seconds: 60));
      expect(p.tick(const Duration(seconds: 63)), isFalse);
    });

    test('summary: ayat, notes (heard differently or passed), per-ayah progress, results', () {
      final p = ReciteProgress(ikhlas);
      p.update(RecognitionUpdate.text('قل هو الله واحد الله الصمد لم يلد'), const Duration(seconds: 6));
      expect(p.recitedAyat, 2);
      expect(p.flagged.map((w) => (w.ayah.ayah, w.mark)), [(1, WordMark.warn)]);
      expect(p.marks, {const AyahRef(112, 1): {4}});
      expect(p.ayahProgress(const AyahRef(112, 1)), 1);
      expect(p.ayahProgress(const AyahRef(112, 3)), closeTo(2 / 4, 1e-9));
      expect(p.ayahProgress(const AyahRef(112, 4)), 0);
      expect(p.results.expand((r) => r.words).where((w) => w.mark == WordMark.skipped), hasLength(7), reason: 'not reached');
      expect(p.indexAt(const AyahRef(112, 2), 1), 4);
    });

    test('the voice crossing a page boundary moves the word the page must show', () {
      // al-Baqarah 2:1-6 ends page 2; 2:6 is on page 3.
      const passage = Passage(2, 4, 6);
      final p = ReciteProgress(passage.expected(q));
      int pageOf(int i) => q.pageOf(p.words[i].ayah);
      final four = RecitationAligner.words(q.text(const AyahRef(2, 4)));
      final five = RecitationAligner.words(q.text(const AyahRef(2, 5)));
      p.update(RecognitionUpdate.text([...four, ...five.take(five.length - 1)].join(' ')), const Duration(seconds: 9));
      final before = pageOf(p.current!);
      p.update(RecognitionUpdate.text([...four, ...five].join(' ')), const Duration(seconds: 10));
      expect(before, q.pageOf(const AyahRef(2, 5)));
      expect(pageOf(p.current!), q.pageOf(const AyahRef(2, 6)));
    });

    test('the grade suggestion counts help', () {
      final words = [for (var i = 0; i < 20; i++) WordResult(ayah: const AyahRef(112, 1), index: i, word: 'w', mark: WordMark.ok)];
      final r = [AyahResult(const AyahRef(112, 1), words)];
      expect(suggestGrade(recite: r, ayat: 1), ReviewGrade.easy);
      expect(suggestGrade(recite: r, helps: 1, ayat: 1), ReviewGrade.good);
      expect(suggestGrade(recite: r, helps: 3, ayat: 1), ReviewGrade.hard);
    });
  });

  group('voice-aware repetition', () {
    test('a repetition counts when the passage is recited to its end with at most one note', () {
      final f = follower()..update(said('قل هو الله واحد الله الصمد لم يلد ولم يولد ولم يكن له كفوا احد'), const []);
      expect(f.done, isTrue);
      expect(repetitionCounts(f), isTrue);
      final g = follower()..update(said('قل هو الله واحد الله الصمد لم يلد ولم يولد ولم يكن له كفوا واحد'), const []);
      g.finish();
      expect(repetitionCounts(g), isFalse, reason: 'two notes');
    });
  });
}
