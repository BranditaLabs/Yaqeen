import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      p = p.memorise(q, day.add(const Duration(days: 1)));
      expect(p.today(q), (surah: 113, from: 1, to: 5));
      expect(p.memorisedAyat(), 6);
      expect(p.memorisedToday(day), isTrue);
    });

    test('first review is tomorrow; ratings follow the scheduler; estimate and strip', () {
      var p = const HifzPlan(goal: HifzGoal.kahf, perDay: 10).memorise(q, day);
      expect(p.due(day), isEmpty);
      final tomorrow = day.add(const Duration(days: 1));
      expect(p.due(tomorrow), hasLength(1));
      p = p.rate(p.portions.single.id, ReviewGrade.good, tomorrow);
      expect(p.portions.single.review.intervalDays, 3);
      expect(p.due(tomorrow), isEmpty);
      expect(p.upcoming(tomorrow), hasLength(1));
      expect(p.finishEstimate(q, tomorrow), tomorrow.add(const Duration(days: 10)));
      expect(p.activeInLast(14, tomorrow), 2);
      expect(p.progress(q), closeTo(10 / 110, 1e-9));
    });

    test('round-trips through JSON', () {
      final p = const HifzPlan(goal: HifzGoal.amma, perDay: 3).memorise(q, day);
      final back = HifzPlan.tryParse(jsonDecode(jsonEncode(p.toJson())))!;
      expect([back.goal, back.perDay, back.portions.single.id, back.activeDays], [p.goal, 3, '114:1-3', p.activeDays]);
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
