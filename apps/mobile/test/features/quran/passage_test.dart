import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/quran/domain/mushaf_layout.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/quran/domain/wird.dart';

void main() {
  final layout = MushafLayout.fromJson(jsonDecode(File('assets/quran/layout_v2.json').readAsStringSync()) as Map<String, dynamic>);
  // As the app loads it: the printed layout sets the page boundaries.
  final q = QuranData.fromJson(
    jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>,
    pageStarts: layout.starts,
  );

  test('Passage.ofPage stays on its page and in one surah, over all 604 pages', () {
    for (var p = 1; p <= QuranData.pageCount; p++) {
      final passage = Passage.ofPage(q, p);
      expect(q.pageOf(passage.first), p, reason: 'page $p');
      expect(q.pageOf(passage.last), p, reason: 'page $p');
      expect(passage.pages(q), [p]);
      expect(passage.contains(passage.first) && passage.contains(passage.last), isTrue);
      final segments = q.page(p);
      // The longest run on the page (the first one on a tie).
      final longest = segments.fold<int>(0, (n, s) => s.ayat.length > n ? s.ayat.length : n);
      expect(passage.length, longest, reason: 'page $p');
      expect(segments.firstWhere((s) => s.ayat.length == longest).surah.number, passage.surah, reason: 'page $p');
      // A given ayah picks its own run.
      for (final s in segments) {
        final at = Passage.ofPage(q, p, at: s.ayat.last.ref);
        expect([at.surah, at.from, at.to], [s.surah.number, s.ayat.first.ref.ayah, s.ayat.last.ref.ayah]);
      }
    }
  });

  test('the bundled surah → page table matches the mushaf and its printed layout', () {
    for (var s = 1; s <= QuranData.surahCount; s++) {
      expect(surahStartPage(s), q.surah(s).startPage, reason: 'surah $s');
      expect(surahStartPage(s), q.pageOf(AyahRef(s, 1)), reason: 'surah $s');
    }
    expect(surahStartPage(0), 1);
    expect(surahStartPage(200), 604);
  });

  test('hifz and khatma passages; range, contains, JSON', () {
    final h = Passage.ofHifz(q, 114, 3, 99);
    expect([h.surah, h.from, h.to], [114, 3, 6]);
    expect(h.range, const [AyahRef(114, 3), AyahRef(114, 4), AyahRef(114, 5), AyahRef(114, 6)]);
    expect(h.contains(const AyahRef(114, 2)), isFalse);
    expect(Passage.tryParse(jsonDecode(jsonEncode(h.toJson()))), h);
    expect(Passage.tryParse({'s': 2, 'f': 5, 't': 1}), isNull);

    // A khatma portion starting mid-surah runs to that surah's end inside the portion.
    final k = Passage.ofKhatma(q, 2, 21);
    expect([k.surah, k.from, k.to], [2, 1, q.firstOfPage(22).ayah - 1]);
    expect(q.pageOf(k.last), 21);
    // A portion that crosses into the next surah stops at the first surah's end.
    final cross = Passage.ofKhatma(q, 48, 52);
    expect([cross.surah, cross.to], [2, q.surah(2).ayahCount]);
    final last = Passage.ofKhatma(q, 604, 604);
    expect(last.first, q.firstOfPage(604));
    expect(last.pages(q), [604]);
  });

  test('modes parse from the route, unknown → read', () {
    expect(QuranMode.parse('listen'), QuranMode.listen);
    expect(QuranMode.parse('recite'), QuranMode.recite);
    expect(QuranMode.parse(null), QuranMode.read);
    expect(QuranMode.parse('x'), QuranMode.read);
  });

  test('wird clock runs only uncovered and in the foreground', () {
    var now = DateTime(2026, 11, 13, 10);
    final c = WirdClock(now: () => now)..restart();
    now = now.add(const Duration(seconds: 8));
    c.covered = true;
    expect(c.sync(), isFalse);
    now = now.add(const Duration(minutes: 5)); // a full-screen page on top: not reading
    expect(c.visible, const Duration(seconds: 8));
    c.covered = false;
    expect(c.sync(), isTrue);
    now = now.add(const Duration(seconds: 7));
    c.foreground = false;
    c.sync();
    now = now.add(const Duration(minutes: 1));
    expect(c.visible, const Duration(seconds: 15));
    c
      ..foreground = true
      ..sync();
    now = now.add(const Duration(seconds: 5));
    expect(c.visible, const Duration(seconds: 20));
    c.restart();
    expect(c.visible, Duration.zero);
  });
}
