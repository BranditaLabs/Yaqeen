import 'package:yaqeen/core/time/zoned.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/hifz/domain/grade_suggestion.dart';
import 'package:yaqeen/features/hifz/domain/hifz_guide.dart';
import 'package:yaqeen/features/hifz/domain/hifz_plan.dart';
import 'package:yaqeen/features/hifz/domain/review_scheduler.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';

void main() {
  final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
  final day = DateTime(2026, 10, 20);

  group('hifz plan', () {
    test('goal sizes match the plan sheet (spec §5.25)', () {
      expect([HifzGoal.amma.surahs.length, HifzGoal.amma.ayat(q)], [37, 564]);
      expect([HifzGoal.tabarak.surahs.length, HifzGoal.tabarak.ayat(q)], [11, 431]);
      expect(HifzGoal.kahf.ayat(q), 110);
      expect(HifzGoal.all.ayat(q), 6236);
    });

    test('Juz ʿAmma starts at an-Nās, portions never cross a surah, then move up', () {
      var p = const HifzPlan(goal: HifzGoal.amma, perDay: 5);
      expect(p.today(q), (surah: 114, from: 1, to: 5));
      p = p.memorise(q, day);
      expect(p.today(q), (surah: 114, from: 6, to: 6));
      p = p.memorise(q, Zoned.addDays(day, 1));
      expect(p.today(q), (surah: 113, from: 1, to: 5));
      expect(p.memorisedAyat(), 6);
      expect(p.memorisedToday(day), isTrue);
    });

    test('first review is tomorrow; ratings follow the scheduler; estimate and strip', () {
      var p = const HifzPlan(goal: HifzGoal.kahf, perDay: 10).memorise(q, day);
      expect(p.due(day), isEmpty);
      final tomorrow = Zoned.addDays(day, 1);
      expect(p.due(tomorrow), hasLength(1));
      p = p.rate(p.portions.single.id, ReviewGrade.good, tomorrow);
      expect(p.portions.single.review.intervalDays, 3);
      expect(p.due(tomorrow), isEmpty);
      expect(p.upcoming(tomorrow), hasLength(1));
      expect(p.finishEstimate(q, tomorrow), Zoned.addDays(tomorrow, 10));
      expect(p.activeInLast(14, tomorrow), 2);
      expect(p.progress(q), closeTo(10 / 110, 1e-9));
    });

    test('progress and finish count only the current goal after «تعديل الخطة»', () {
      var p = const HifzPlan(goal: HifzGoal.all, perDay: 20);
      for (var i = 0; i < 10; i++) {
        p = p.memorise(q, Zoned.addDays(day, i)); // al-Fātiḥa and most of al-Baqarah
      }
      expect(p.memorisedAyatIn(), 187);
      final kahf = p.copyWith(goal: HifzGoal.kahf);
      expect(kahf.memorisedAyat(), 187); // still reviewed
      expect(kahf.memorisedAyatIn(), 0);
      expect(kahf.progress(q), 0);
      expect(kahf.finishEstimate(q, day), Zoned.addDays(day, (110 / 20).ceil()));
      expect(kahf.today(q), (surah: 18, from: 1, to: 20));
    });

    test('memorising twice in one day records one portion (the next, unstudied one is not taken)', () {
      final once = const HifzPlan(goal: HifzGoal.amma, perDay: 5).memorise(q, day);
      final twice = once.memorise(q, day);
      expect(twice, same(once));
      expect(twice.portions.map((p) => p.id), ['114:1-5']);
      expect(twice.memorise(q, Zoned.addDays(day, 1)).portions.map((p) => p.id), ['114:1-5', '114:6-6']);
    });

    test("today's card keeps the passage memorised today once the cursor moves on", () {
      final p = const HifzPlan(goal: HifzGoal.amma, perDay: 5).memorise(q, day);
      expect(p.todaysPortion(day)?.id, '114:1-5');
      expect(p.today(q), (surah: 114, from: 6, to: 6));
      expect(p.todaysPortion(Zoned.addDays(day, 1)), isNull);
    });

    test('steps ticked today are kept (and saved), and reset the next day', () {
      var p = const HifzPlan(goal: HifzGoal.amma, perDay: 5).toggleStep(0, day).toggleStep(1, day);
      expect(p.stepsFor(day), {0, 1});
      p = p.toggleStep(1, day);
      expect(p.stepsFor(day), {0});
      final back = HifzPlan.tryParse(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.stepsFor(day), {0});
      expect(back.copyWith(perDay: 7).stepsFor(day), {0});
      final tomorrow = Zoned.addDays(day, 1);
      expect(back.stepsFor(tomorrow), isEmpty);
      expect(back.toggleStep(2, tomorrow).stepsFor(tomorrow), {2});
    });

    test('a guided stage ticks its step once; a manual untick still works', () {
      const p = HifzPlan(goal: HifzGoal.amma, perDay: 5);
      final once = p.completeStep(0, day);
      expect(once.stepsFor(day), {0});
      expect(once.completeStep(0, day), same(once), reason: 'idempotent');
      final both = once.completeStep(1, day);
      expect(both.stepsFor(day), {0, 1});
      expect(both.toggleStep(1, day).stepsFor(day), {0});
      expect(HifzGuide.started(p, day), isFalse);
      expect(HifzGuide.started(once, day), isTrue);
      expect(HifzGuide.halaqaLocation(q, p.today(q)!), '/quran/read/604?session=hifz&surah=114&from=1&to=5');
    });

    test('round-trips through JSON', () {
      final p = const HifzPlan(goal: HifzGoal.amma, perDay: 3).memorise(q, day);
      final back = HifzPlan.tryParse(jsonDecode(jsonEncode(p.toJson())))!;
      expect([back.goal, back.perDay, back.portions.single.id, back.activeDays], [p.goal, 3, '114:1-3', p.activeDays]);
    });
  });

  group('suggested grade', () {
    final passage = [for (var a = 1; a <= 5; a++) (AyahRef(114, a), q.text(AyahRef(114, a)))];
    final all = passage.map((e) => e.$2).join(' ');

    test('from the recitation: all heard → easy; a slip in ten → good; much missing → hard', () {
      expect(suggestGrade(recite: RecitationAligner.align(passage, all), ayat: 5), ReviewGrade.easy);
      final words = all.split(' ');
      final oneSlip = [...words]..[3] = 'كلمة';
      final r1 = RecitationAligner.align(passage, oneSlip.join(' '));
      expect(r1.expand((r) => r.words).where((w) => w.mark != WordMark.ok).length, 1);
      expect(suggestGrade(recite: r1, ayat: 5), ReviewGrade.good);
      expect(suggestGrade(recite: RecitationAligner.align(passage, all), reveals: 2, ayat: 5), ReviewGrade.hard,
          reason: 'revealing more than a quarter of the ayat is not «good»',);
      expect(suggestGrade(recite: RecitationAligner.align(passage, words.take(4).join(' ')), ayat: 5), ReviewGrade.hard);
    });

    test('from reveals only (no recitation): none → easy, up to a third → good, more → hard', () {
      expect(suggestGrade(ayat: 5), ReviewGrade.easy);
      expect(suggestGrade(reveals: 1, ayat: 5), ReviewGrade.good);
      expect(suggestGrade(reveals: 2, ayat: 6), ReviewGrade.good);
      expect(suggestGrade(reveals: 3, ayat: 5), ReviewGrade.hard);
      expect(suggestGrade(recite: const [], reveals: 0, ayat: 0), ReviewGrade.easy);
    });
  });

  group('recitation alignment', () {
    final fatiha = [for (var a = 1; a <= 3; a++) (AyahRef(1, a), q.text(AyahRef(1, a)))];

    test('exact recitation (without tashkeel) is all ok', () {
      final heard = fatiha.map((e) => e.$2).join(' ').replaceAll(RegExp('[ً-ٰٟۖ-ۭ]'), '');
      final r = RecitationAligner.align(fatiha, heard);
      expect(r.every((a) => a.ok), isTrue);
      expect(RecitationAligner.recitedCount(r), 3);
    });

    test('a changed word is a warning on that word; a missing ayah is skipped', () {
      final expected = fatiha.take(2).toList();
      final words = RecitationAligner.words(expected[1].$2);
      final heard = [...RecitationAligner.words(expected[0].$2), ...words.take(words.length - 1), 'الناس'].join(' ');
      final r = RecitationAligner.align([...expected, fatiha[2]], heard);
      expect(r[0].ok, isTrue);
      expect(r[1].flagged.single.mark, WordMark.warn);
      expect(r[1].flagged.single.word, words.last);
      expect(r[2].words.every((w) => w.mark == WordMark.skipped), isTrue);
      expect(RecitationAligner.recitedCount(r), 2);
    });

    test('one-letter recogniser slips in long words still match', () {
      expect(RecitationAligner.same('الرَّحِيمِ', 'الرحيم'), isTrue);
      expect(RecitationAligner.same('مستقيم', 'مستقين'), isTrue);
      expect(RecitationAligner.same('من', 'ما'), isFalse);
    });
  });
}
