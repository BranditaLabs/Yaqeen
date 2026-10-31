/// Arabic search normalisation (spec §5.10): strip tashkeel and Quranic marks, unify alef forms,
/// taa marbuta → haa, alef maqsura → yaa, drop tatweel, Western digits, lower-case Latin.
abstract final class ArabicText {
  // Harakat, tanween, shadda, sukun, superscript alef, Quranic annotation marks, small letters.
  static final _marks = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]');
  static const _easternDigits = '٠١٢٣٤٥٦٧٨٩';

  static String normalize(String input) {
    final b = StringBuffer();
    for (final ch in input.replaceAll(_marks, '').runes) {
      final c = String.fromCharCode(ch);
      final d = _easternDigits.indexOf(c);
      if (d >= 0) {
        b.write(d);
        continue;
      }
      b.write(
        switch (c) {
          'أ' || 'إ' || 'آ' || 'ٱ' || 'ٲ' || 'ٳ' => 'ا',
          'ة' => 'ه',
          'ى' => 'ي',
          'ؤ' => 'و',
          'ئ' => 'ي',
          'ـ' => '',
          _ => c.toLowerCase(),
        },
      );
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Drop a leading definite article so «كهف» finds «الكهف».
  static String withoutArticle(String normalized) =>
      normalized.startsWith('ال') && normalized.length > 3 ? normalized.substring(2) : normalized;

  /// Ayah search key (spec §5.10 full-text): [normalize] plus Uthmani → everyday spelling, so
  /// «الصلاة» finds «ٱلصَّلَوٰةَ» and «العالمين» finds «ٱلۡعَٰلَمِينَ». Alefs are dropped altogether
  /// (the mushaf writes many of them as a small alef or not at all), and so are spaces' neighbours'
  /// marks. Returns the key and, for each key character, the index of the source character it came
  /// from — to highlight a match in the original text.
  static (String, List<int>) searchKey(String input) {
    final out = StringBuffer();
    final map = <int>[];
    final units = input.codeUnits;
    var lastSpace = true;
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      final next = i + 1 < units.length ? units[i + 1] : 0;
      // A waw carrying a small alef is read as alef (صلوٰة، حيوٰة، زكوٰة) → dropped like an alef.
      // (Ya and alef maqsura keep their letter: يٰأيها → «يا أيها», موسىٰ → «موسى».)
      if (u == 0x0648 && next == 0x0670) {
        i++;
        continue;
      }
      final ch = String.fromCharCode(u);
      if (_marks.hasMatch(ch) || ch == 'ـ') continue;
      final String k = switch (ch) {
        'ا' || 'أ' || 'إ' || 'آ' || 'ٱ' || 'ٲ' || 'ٳ' || 'ء' => '',
        'ة' => 'ه',
        'ى' => 'ي',
        'ؤ' => 'و',
        'ئ' => 'ي',
        _ => ch.toLowerCase(),
      };
      if (k.isEmpty) continue;
      final space = k.trim().isEmpty;
      if (space) {
        if (lastSpace) continue;
        out.write(' ');
        map.add(i);
        lastSpace = true;
        continue;
      }
      out.write(k);
      map.add(i);
      lastSpace = false;
    }
    var key = out.toString();
    if (key.endsWith(' ')) {
      key = key.substring(0, key.length - 1);
      map.removeLast();
    }
    return (key, map);
  }
}
