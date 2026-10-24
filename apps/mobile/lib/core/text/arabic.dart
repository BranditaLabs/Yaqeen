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
}
