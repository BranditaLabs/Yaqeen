import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/wird.dart';

void main() {
  final bytes = File('assets/quran/quran.json').readAsBytesSync();
  final q = QuranData.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  test('asset checksum matches tools/quran/build_quran.py output (text is never altered)', () {
    expect(sha256.convert(bytes).toString(), 'c4514b12e5c5b8bebea9eba4a603074a6e538b09ec05e731bc28cc9470b053c7');
  });

  test('every ayah is on exactly one page, in order, across all 604 pages', () {
    var count = 0;
    AyahRef? prev;
    for (var p = 1; p <= QuranData.pageCount; p++) {
      for (final seg in q.page(p)) {
        for (final a in seg.ayat) {
          if (prev != null) expect(a.ref, q.next(prev), reason: 'page $p');
          expect(q.pageOf(a.ref), p);
          prev = a.ref;
          count++;
        }
      }
    }
    expect(count, QuranData.totalAyat);
    expect(q.surahs.fold<int>(0, (s, x) => s + x.ayahCount), QuranData.totalAyat);
  });

  test('Madani landmarks: pages, juz and hizb', () {
    expect(q.firstOfPage(1), const AyahRef(1, 1));
    expect(q.firstOfPage(2), const AyahRef(2, 1));
    expect(q.firstOfPage(3), const AyahRef(2, 6));
    expect(q.surah(18).startPage, 293);
    expect(q.juzOf(const AyahRef(18, 1)), 15);
    expect(q.juzOf(const AyahRef(2, 142)), 2);
    expect(q.juzStartPage(30), 582);
    expect(q.firstOfJuz(30), const AyahRef(78, 1));
    expect(q.hizbOf(const AyahRef(1, 1)), 1);
    expect(q.hizbOf(const AyahRef(114, 6)), 60);
    expect(q.pageOf(const AyahRef(114, 6)), 604);
    expect(q.sajdas, hasLength(15));
  });

  test('page segments mark where a surah starts', () {
    final last = q.page(604);
    expect(last.map((s) => s.surah.number), [112, 113, 114]);
    expect(last.every((s) => s.startsSurah), isTrue);
    final mid = q.page(3);
    expect(mid.single.startsSurah, isFalse);
    expect(q.surah(9).ayahCount, 129);
    expect(q.basmala, q.text(const AyahRef(1, 1)));
  });

  test('search: names with or without the article, numbers, surah:ayah — fast', () {
    final sw = Stopwatch()..start();
    expect((q.search('الكهف').first as SurahHit).surah.number, 18);
    expect((q.search('كهف').first as SurahHit).surah.number, 18);
    expect((q.search('سورة يس').first as SurahHit).surah.number, 36);
    expect((q.search('18').single as SurahHit).surah.number, 18);
    final hit = q.search('18:10').single as AyahHit;
    expect(hit.page, q.pageOf(const AyahRef(18, 10)));
    expect((q.search('Kahf').first as SurahHit).surah.number, 18);
    expect(q.search('115'), isEmpty);
    expect(q.search('2:300'), isEmpty);
    expect(q.search('zzz'), isEmpty);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  group('wird', () {
    test('a page counts after 20 s; the goal ticks the challenge once a day', () {
      var r = WirdRules.read(null, today: '2026-10-20', page: 296, visibleFor: const Duration(seconds: 10), goalPages: 2);
      expect(r.counted, isFalse);
      r = WirdRules.read(r.day, today: '2026-10-20', page: 296, visibleFor: const Duration(seconds: 25), goalPages: 2);
      expect((r.counted, r.tickNow), (true, false));
      r = WirdRules.read(r.day, today: '2026-10-20', page: 296, visibleFor: const Duration(seconds: 40), goalPages: 2);
      expect(r.counted, isFalse); // same page again
      r = WirdRules.read(r.day, today: '2026-10-20', page: 297, visibleFor: const Duration(seconds: 30), goalPages: 2);
      expect(r.tickNow, isTrue);
      r = WirdRules.read(r.day, today: '2026-10-20', page: 298, visibleFor: const Duration(seconds: 30), goalPages: 2);
      expect((r.counted, r.tickNow, r.day.count), (true, false, 3));
    });

    test('a new day starts fresh', () {
      final y = WirdRules.read(null, today: '2026-10-19', page: 1, visibleFor: const Duration(minutes: 1), goalPages: 1);
      expect(y.tickNow, isTrue);
      final t = WirdRules.read(y.day, today: '2026-10-20', page: 1, visibleFor: const Duration(minutes: 1), goalPages: 1);
      expect((t.day.date, t.day.count, t.tickNow), ('2026-10-20', 1, true));
    });
  });
}
