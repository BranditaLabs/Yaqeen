import '../../../core/storage/local_store.dart';
import '../domain/annotations.dart';
import '../domain/khatma.dart';
import '../domain/quran_data.dart';
import '../domain/reading_stats.dart';
import '../domain/wird.dart';

enum BookmarkKind { page, ayah }

class Bookmark {
  const Bookmark({required this.kind, required this.page, this.ref, required this.at, this.color = MarkColor.gold});
  final BookmarkKind kind;
  final int page;
  final AyahRef? ref;
  final DateTime at;
  final MarkColor color;

  String get key => kind == BookmarkKind.page ? 'p$page' : 'a$ref';

  Bookmark withColor(MarkColor c) => Bookmark(kind: kind, page: page, ref: ref, at: at, color: c);

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'p': page,
        if (ref != null) 's': ref!.surah,
        if (ref != null) 'a': ref!.ayah,
        'at': at.toIso8601String(),
        if (color != MarkColor.gold) 'c': color.name,
      };
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        kind: BookmarkKind.values.byName(j['k'] as String),
        page: j['p'] as int,
        ref: j['s'] == null ? null : AyahRef(j['s'] as int, j['a'] as int),
        at: DateTime.parse(j['at'] as String),
        color: MarkColor.values.where((c) => c.name == j['c']).firstOrNull ?? MarkColor.gold,
      );
}

class LastRead {
  const LastRead({required this.page, required this.surah, required this.at});
  final int page;
  final int surah;
  final DateTime at;
}

/// Bookmarks, last read page, today's wird, notes, stats and khatma — device first; optional
/// encrypted cloud backup (consent `cloud_backup`, spec §6.13; see features/backup).
class ReadingRepository {
  ReadingRepository(this.store);
  final LocalStore store;

  Future<Map<String, dynamic>> _doc() => store.readMap('reading');

  /// Every write is a read-modify-write of one document, and the reader fires several at once
  /// (wird, stats, khatma): run them one after another so none is lost.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Cloud backup: copies of whole fields of the reading document, taken in the write queue.
  Future<Map<String, dynamic>> backupFields(List<String> keys) => _serial(() async {
        final d = await _doc();
        return {for (final k in keys) k: d[k]};
      });

  /// Cloud backup: replaces whole fields (already merged with this device's copy), in the write queue.
  Future<void> restoreFields(Map<String, dynamic> fields) => _serial(() async {
        final d = await _doc();
        d.addAll(fields);
        await store.write('reading', d);
      });

  Future<void> _put(String key, Object? value) async {
    final d = await _doc();
    d[key] = value;
    await store.write('reading', d);
  }

  Future<LastRead?> lastRead() async {
    final j = (await _doc())['lastRead'] as Map?;
    if (j == null || j['page'] == null) return null;
    return LastRead(
      page: j['page'] as int,
      surah: (j['surah'] as int?) ?? 1,
      at: DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime(2000),
    );
  }

  Future<void> saveLastRead(int page, int surah, DateTime at) =>
      _serial(() => _put('lastRead', {'page': page, 'surah': surah, 'at': at.toIso8601String()}));

  Future<List<Bookmark>> bookmarks() async {
    final list = ((await _doc())['bookmarks'] as List?) ?? const [];
    return list.map((e) => Bookmark.fromJson((e as Map).cast<String, dynamic>())).toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Adds or removes; returns true when the bookmark now exists.
  Future<bool> toggle(Bookmark b) => _serial(() async {
        final all = await bookmarks();
        final exists = all.any((x) => x.key == b.key);
        final next = exists ? all.where((x) => x.key != b.key).toList() : [b, ...all];
        await _put('bookmarks', next.map((x) => x.toJson()).toList());
        return !exists;
      });

  /// Changes a bookmark's colour (no-op when it isn't saved).
  Future<void> recolor(String key, MarkColor color) => _serial(() async {
        final all = await bookmarks();
        await _put('bookmarks', [for (final b in all) (b.key == key ? b.withColor(color) : b).toJson()]);
      });

  /* --------------------------------------------------- notes & highlights */

  Future<Annotations> annotations() async {
    final d = await _doc();
    final hl = (d['highlights'] as Map?)?.cast<String, dynamic>() ?? const {};
    final notes = (d['notes'] as List?) ?? const [];
    return Annotations(
      highlights: {
        for (final e in hl.entries)
          if (_ref(e.key) case final r?)
            if (MarkColor.values.where((c) => c.name == e.value).firstOrNull case final c?) r: c,
      },
      notes: {
        for (final n in notes)
          if (n is Map) AyahNote.fromJson(n.cast<String, dynamic>()).ref: AyahNote.fromJson(n.cast<String, dynamic>()),
      },
    );
  }

  /// null removes the highlight.
  Future<void> setHighlight(AyahRef ref, MarkColor? color) => _serial(() async {
        final d = await _doc();
        final hl = Map<String, dynamic>.from((d['highlights'] as Map?) ?? const {});
        if (color == null) {
          hl.remove('$ref');
        } else {
          hl['$ref'] = color.name;
        }
        await _put('highlights', hl);
      });

  /// Empty text removes the note.
  Future<void> setNote(AyahRef ref, String text, DateTime at) => _serial(() async {
        final trimmed = text.trim();
        final all = (await annotations()).notes.values.where((n) => n.ref != ref).toList();
        if (trimmed.isNotEmpty) {
          all.add(
            AyahNote(ref: ref, text: trimmed.length > AyahNote.maxLength ? trimmed.substring(0, AyahNote.maxLength) : trimmed, at: at),
          );
        }
        all.sort((a, b) => b.at.compareTo(a.at));
        await _put('notes', [for (final n in all) n.toJson()]);
      });

  static AyahRef? _ref(String key) {
    final p = key.split(':');
    if (p.length != 2) return null;
    final s = int.tryParse(p[0]);
    final a = int.tryParse(p[1]);
    return s == null || a == null ? null : AyahRef(s, a);
  }

  /* -------------------------------------------------------------- stats */

  Future<ReadingStats> stats() async {
    final j = (await _doc())['stats'] as Map?;
    return j == null ? const ReadingStats({}) : ReadingStats.fromJson(j.cast<String, dynamic>());
  }

  Future<void> addStats(String date, {int pages = 0, int seconds = 0}) => _serial(() async {
        final next = (await stats()).add(date, pages: pages, seconds: seconds);
        await _put('stats', next.toJson());
      });

  /* ------------------------------------------------------------- khatma */

  Future<Khatma?> khatma() async {
    final j = (await _doc())['khatma'] as Map?;
    return j == null ? null : Khatma.fromJson(j.cast<String, dynamic>());
  }

  Future<void> saveKhatma(Khatma? k) => _serial(() => _put('khatma', k?.toJson()));

  Future<List<KhatmaRecord>> khatmaHistory() async {
    final list = ((await _doc())['khatmaHistory'] as List?) ?? const [];
    return [for (final e in list) KhatmaRecord.fromJson((e as Map).cast<String, dynamic>())];
  }

  /// Marks a page read in the active plan; a finished plan moves to the history. Returns the
  /// plan after the change (null when there is none) and whether it just finished.
  Future<({Khatma? plan, bool justFinished})> khatmaRead(int page, String today) => _serial(() async {
        final k = await khatma();
        if (k == null || k.finished) return (plan: k, justFinished: false);
        final next = k.markRead(page, today);
        if (identical(next, k)) return (plan: k, justFinished: false);
        await _put('khatma', next.toJson());
        if (next.finished) {
          final history = await khatmaHistory();
          await _put(
            'khatmaHistory',
            [KhatmaRecord(startedOn: next.startedOn, finishedOn: today).toJson(), ...history.map((h) => h.toJson())],
          );
        }
        return (plan: next, justFinished: next.finished);
      });

  Future<WirdDay?> wird() async {
    final j = (await _doc())['wird'] as Map?;
    return j == null ? null : WirdDay.fromJson(j.cast<String, dynamic>());
  }

  Future<void> saveWird(WirdDay day) => _serial(() => _put('wird', day.toJson()));
}
