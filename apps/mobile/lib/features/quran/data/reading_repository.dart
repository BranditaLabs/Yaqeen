import '../../../core/storage/local_store.dart';
import '../domain/quran_data.dart';
import '../domain/wird.dart';

enum BookmarkKind { page, ayah }

class Bookmark {
  const Bookmark({required this.kind, required this.page, this.ref, required this.at});
  final BookmarkKind kind;
  final int page;
  final AyahRef? ref;
  final DateTime at;

  String get key => kind == BookmarkKind.page ? 'p$page' : 'a$ref';

  Map<String, dynamic> toJson() =>
      {'k': kind.name, 'p': page, if (ref != null) 's': ref!.surah, if (ref != null) 'a': ref!.ayah, 'at': at.toIso8601String()};
  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        kind: BookmarkKind.values.byName(j['k'] as String),
        page: j['p'] as int,
        ref: j['s'] == null ? null : AyahRef(j['s'] as int, j['a'] as int),
        at: DateTime.parse(j['at'] as String),
      );
}

class LastRead {
  const LastRead({required this.page, required this.surah, required this.at});
  final int page;
  final int surah;
  final DateTime at;
}

/// Bookmarks, last read page and today's wird — on the device only, never synced (spec §6.13).
class ReadingRepository {
  ReadingRepository(this.store);
  final LocalStore store;

  Future<Map<String, dynamic>> _doc() => store.readMap('reading');
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
      _put('lastRead', {'page': page, 'surah': surah, 'at': at.toIso8601String()});

  Future<List<Bookmark>> bookmarks() async {
    final list = ((await _doc())['bookmarks'] as List?) ?? const [];
    return list.map((e) => Bookmark.fromJson((e as Map).cast<String, dynamic>())).toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Adds or removes; returns true when the bookmark now exists.
  Future<bool> toggle(Bookmark b) async {
    final all = await bookmarks();
    final exists = all.any((x) => x.key == b.key);
    final next = exists ? all.where((x) => x.key != b.key).toList() : [b, ...all];
    await _put('bookmarks', next.map((x) => x.toJson()).toList());
    return !exists;
  }

  Future<WirdDay?> wird() async {
    final j = (await _doc())['wird'] as Map?;
    return j == null ? null : WirdDay.fromJson(j.cast<String, dynamic>());
  }

  Future<void> saveWird(WirdDay day) => _put('wird', day.toJson());
}
