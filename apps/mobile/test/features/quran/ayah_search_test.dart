import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/text/arabic.dart';
import 'package:yaqeen/features/quran/domain/ayah_search.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';

void main() {
  late QuranData q;
  late AyahSearchIndex index;
  setUpAll(() {
    q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
    index = AyahSearchIndex.buildSync(q);
  });

  test('search key reads Uthmani spelling the everyday way', () {
    String k(String s) => ArabicText.searchKey(s).$1;
    expect(k('ٱلصَّلَوٰةَ'), k('الصلاة'));
    expect(k('ٱلۡعَٰلَمِينَ'), k('العالمين'));
    expect(k('ٱلرَّحۡمَٰنِ'), k('الرحمن'));
    expect(k('مُوسَىٰ'), k('موسى'));
    expect(k('ٱلۡحَيَوٰةِ'), k('الحياة'));
  });

  test('finds ayat in everyday spelling, in mushaf order', () {
    final r = index.search('الحمد لله رب العالمين');
    expect(r.matches.first.ref, const AyahRef(1, 2));
    expect(r.matches.first.exact, isTrue);
    final kursi = index.search('الحي القيوم');
    expect(kursi.matches.map((m) => m.ref), contains(const AyahRef(2, 255)));
    final salah = index.search('واقيموا الصلاة');
    expect(salah.total, greaterThan(5));
    for (var i = 1; i < salah.matches.length; i++) {
      final a = salah.matches[i - 1];
      final b = salah.matches[i];
      if (a.exact == b.exact) expect(a.ref < b.ref, isTrue);
    }
  });

  test('highlights cover the matched words in the original text', () {
    final m = index.search('القيوم').matches.firstWhere((m) => m.ref == const AyahRef(2, 255));
    final text = q.text(m.ref);
    final hit = text.substring(m.spans.first.$1, m.spans.first.$2);
    expect(ArabicText.searchKey(hit).$1, contains(ArabicText.searchKey('القيوم').$1));
  });

  test('words in any order; too-short and unknown queries return nothing', () {
    expect(index.search('العالمين الحمد').matches.map((m) => m.ref), contains(const AyahRef(1, 2)));
    expect(index.search('ا').total, 0);
    expect(index.search('zzzz').total, 0);
  });

  test('the whole mushaf is indexed and stays fast', () {
    final sw = Stopwatch()..start();
    final r = index.search('الله');
    sw.stop();
    expect(r.total, greaterThan(1500));
    expect(r.matches.length, 200);
    expect(sw.elapsedMilliseconds, lessThan(400));
  });
}
