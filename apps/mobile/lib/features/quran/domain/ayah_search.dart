import 'dart:isolate';

import '../../../core/text/arabic.dart';
import 'quran_data.dart';

/// One ayah that matched, with where to highlight it in the original (diacritised) text.
class AyahMatch {
  const AyahMatch({required this.ref, required this.page, required this.spans, required this.exact});
  final AyahRef ref;
  final int page;

  /// [start, end) ranges in `quran.text(ref)`, ascending, non-overlapping.
  final List<(int, int)> spans;

  /// The whole query appears as one phrase (ranked first).
  final bool exact;
}

/// Full-text search over all 6,236 ayat (spec §5.10), offline. Every ayah is reduced to a search
/// key once ([ArabicText.searchKey], built off the UI thread); a query matches an ayah when each of
/// its words occurs in the key, in any order. The mushaf text itself is never changed.
class AyahSearchIndex {
  AyahSearchIndex._(this._quran, this._keys, this._refs);

  final QuranData _quran;
  final List<String> _keys;
  final List<AyahRef> _refs;

  static const minQueryLength = 2;

  /// Builds the keys on a background isolate (≈ 330k characters).
  static Future<AyahSearchIndex> build(QuranData q) async {
    final refs = <AyahRef>[];
    final texts = <String>[];
    for (final s in q.surahs) {
      for (var a = 1; a <= s.ayahCount; a++) {
        final r = AyahRef(s.number, a);
        refs.add(r);
        texts.add(q.text(r));
      }
    }
    final keys = await Isolate.run(() => [for (final t in texts) ArabicText.searchKey(t).$1]);
    return AyahSearchIndex._(q, keys, refs);
  }

  /// Synchronous variant for tests.
  factory AyahSearchIndex.buildSync(QuranData q) {
    final refs = <AyahRef>[];
    final keys = <String>[];
    for (final s in q.surahs) {
      for (var a = 1; a <= s.ayahCount; a++) {
        final r = AyahRef(s.number, a);
        refs.add(r);
        keys.add(ArabicText.searchKey(q.text(r)).$1);
      }
    }
    return AyahSearchIndex._(q, keys, refs);
  }

  /// The query's words as search keys (empty when too short to be useful).
  static List<String> terms(String query) {
    // The ayat are Arabic only: a query without Arabic letters can't match.
    if (!RegExp('[\u0621-\u064A]').hasMatch(query)) return const [];
    final key = ArabicText.searchKey(query).$1.trim();
    if (key.length < minQueryLength) return const [];
    return key.split(' ').where((w) => w.isNotEmpty).toList();
  }

  /// Matches in mushaf order, exact phrases first; at most [limit]. [total] in the record is the
  /// full count (for «N نتيجة»).
  ({List<AyahMatch> matches, int total}) search(String query, {int limit = 200}) {
    final words = terms(query);
    if (words.isEmpty) return (matches: const [], total: 0);
    final phrase = words.join(' ');
    final exact = <int>[];
    final loose = <int>[];
    for (var i = 0; i < _keys.length; i++) {
      final k = _keys[i];
      if (words.length > 1 && k.contains(phrase)) {
        exact.add(i);
      } else if (words.every(k.contains)) {
        (words.length == 1 ? exact : loose).add(i);
      }
    }
    final ordered = [...exact, ...loose];
    final isExact = exact.toSet();
    return (
      matches: [for (final i in ordered.take(limit)) _match(i, words, phrase, exact: isExact.contains(i))],
      total: ordered.length,
    );
  }

  AyahMatch _match(int i, List<String> words, String phrase, {required bool exact}) {
    final ref = _refs[i];
    final (key, map) = ArabicText.searchKey(_quran.text(ref));
    final text = _quran.text(ref);
    final ranges = <(int, int)>[];
    void mark(String needle) {
      var from = 0;
      while (true) {
        final at = key.indexOf(needle, from);
        if (at < 0) break;
        final start = map[at];
        // End after the last source character of the match, plus any marks that follow it.
        var end = map[at + needle.length - 1] + 1;
        final next = at + needle.length < map.length ? map[at + needle.length] : text.length;
        while (end < next && text[end] != ' ') {
          end++;
        }
        ranges.add((start, end));
        from = at + needle.length;
      }
    }

    if (exact && words.length > 1) {
      mark(phrase);
    } else {
      words.forEach(mark);
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, r.$2 > merged.last.$2 ? r.$2 : merged.last.$2);
      } else {
        merged.add(r);
      }
    }
    return AyahMatch(ref: ref, page: _quran.pageOf(ref), spans: merged, exact: exact);
  }
}
