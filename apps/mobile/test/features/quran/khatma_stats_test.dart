import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/features/quran/data/reading_repository.dart';
import 'package:yaqeen/features/quran/domain/annotations.dart';
import 'package:yaqeen/features/quran/domain/khatma.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/reading_stats.dart';

void main() {
  group('khatma', () {
    test('a dated plan spreads what is left over the days left', () {
      const k = Khatma(startedOn: '2027-02-08', targetDate: '2027-03-09'); // 30 days
      expect(k.daysLeft('2027-02-08'), 30);
      expect(k.dailyTarget('2027-02-08'), 21); // ceil(604 / 30)
      expect(k.expectedBy('2027-02-08'), 20);
      expect(k.balance('2027-02-08'), -20);
      var read = k;
      for (var p = 1; p <= 40; p++) {
        read = read.markRead(p, '2027-02-08');
      }
      expect(read.balance('2027-02-08'), 20);
      expect(read.nextPage, 41);
      // Behind later on: the target per day grows.
      expect(read.dailyTarget('2027-03-01'), ((604 - 40) / 9).ceil());
    });

    test('a fixed pace, its projection, completion and compact storage', () {
      var k = const Khatma(startedOn: '2026-10-01', pagesPerDay: 20);
      expect(k.dailyTarget('2026-10-05'), 20);
      expect(k.projectedFinish('2026-10-01'), '2026-10-31');
      for (var p = 1; p <= 604; p++) {
        k = k.markRead(p, '2026-10-30');
      }
      expect(k.finished, isTrue);
      expect(k.finishedOn, '2026-10-30');
      expect(k.toJson()['read'], [
        [1, 604],
      ]);
      expect(Khatma.fromJson(k.toJson()).done, 604);
      expect(k.markRead(5, '2026-10-31'), same(k)); // finished plans don't change
    });

    test('repository: reading pages, finishing moves the plan to history', () async {
      final repo = ReadingRepository(LocalStore(MemoryKvStore()));
      expect((await repo.khatmaRead(1, '2026-10-01')).plan, isNull);
      await repo.saveKhatma(Khatma(startedOn: '2026-10-01', pagesPerDay: 604, read: {for (var p = 2; p <= 604; p++) p}));
      final r = await repo.khatmaRead(1, '2026-10-02');
      expect(r.justFinished, isTrue);
      final history = await repo.khatmaHistory();
      expect(history.single.days, 2);
      expect((await repo.khatmaRead(3, '2026-10-02')).justFinished, isFalse);
    });
  });

  group('reading stats', () {
    test('week totals, streak and bars; a long idle view counts at most 5 minutes', () {
      var s = const ReadingStats({});
      s = s.add('2026-10-25', pages: 3, seconds: 240).add('2026-10-26', pages: 2, seconds: 9999).add('2026-10-27', pages: 1, seconds: 60);
      final today = DateTime(2026, 10, 27);
      final w = s.week(today);
      expect(w.pages, 6);
      expect(w.minutes, ((240 + 300 + 60) / 60).round());
      expect(w.activeDays, 3);
      expect(s.streak(today), 3);
      expect(s.streak(DateTime(2026, 10, 28)), 3); // today empty → counts up to yesterday
      expect(s.lastSeven(today), [0, 0, 0, 0, 3, 2, 1]);
      expect(ReadingStats.fromJson(s.toJson()).week(today).pages, 6);
    });
  });

  group('annotations', () {
    test('colours, highlights and notes round-trip; empty note removes it', () async {
      final repo = ReadingRepository(LocalStore(MemoryKvStore()));
      final now = DateTime(2026, 10, 27);
      await repo.toggle(Bookmark(kind: BookmarkKind.ayah, page: 1, ref: const AyahRef(1, 2), at: now));
      await repo.recolor('a1:2', MarkColor.lapis);
      expect((await repo.bookmarks()).single.color, MarkColor.lapis);
      await repo.setHighlight(const AyahRef(2, 255), MarkColor.green);
      await repo.setNote(const AyahRef(2, 255), '  آية الكرسي  ', now);
      var a = await repo.annotations();
      expect(a.highlights[const AyahRef(2, 255)], MarkColor.green);
      expect(a.notes[const AyahRef(2, 255)]!.text, 'آية الكرسي');
      await repo.setHighlight(const AyahRef(2, 255), null);
      await repo.setNote(const AyahRef(2, 255), ' ', now);
      a = await repo.annotations();
      expect(a.highlights, isEmpty);
      expect(a.notes, isEmpty);
    });
  });
}
