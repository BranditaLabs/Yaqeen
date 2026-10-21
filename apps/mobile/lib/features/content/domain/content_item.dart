enum ContentKind { dua, zikr }

/// Azkar sets — category keys from contracts `ZIKR_CATEGORIES`.
enum ZikrSet {
  morning('morning'),
  evening('evening'),
  afterPrayer('after_prayer'),
  sleep('sleep');

  const ZikrSet(this.key);
  final String key;
  static ZikrSet? of(String key) => values.where((v) => v.key == key).firstOrNull;
}

/// Dua sections — category keys from contracts `DUA_CATEGORIES`.
enum DuaCategory {
  worry('worry'),
  travel('travel'),
  food('food'),
  sleep('sleep'),
  mosque('mosque'),
  general('general');

  const DuaCategory(this.key);
  final String key;
  static DuaCategory? of(String key) => values.where((v) => v.key == key).firstOrNull;
}

/// A reviewer-approved dua or zikr from `GET /v1/content` (spec §6.11). Rendering always shows
/// [source]; the text is never edited on the device.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.kind,
    required this.category,
    required this.title,
    required this.textAr,
    required this.source,
    this.translationEn,
    this.virtue,
    this.repeatCount = 1,
    this.sortOrder = 0,
    this.featured = false,
    this.version = 1,
  });

  final String id;
  final ContentKind kind;
  final String category;
  final String title;
  final String textAr;
  final String source;
  final String? translationEn;
  final String? virtue;
  final int repeatCount;
  final int sortOrder;
  final bool featured;
  final int version;

  static ContentItem? tryParse(Object? j) {
    if (j is! Map) return null;
    final kind = switch (j['type']) {
      'dua' => ContentKind.dua,
      'zikr' => ContentKind.zikr,
      _ => null,
    };
    final source = j['source'];
    // No source, no display (spec §5.19: every text needs a source line).
    if (kind == null || source is! String || source.trim().isEmpty || j['textAr'] is! String || j['id'] is! String) return null;
    return ContentItem(
      id: j['id'] as String,
      kind: kind,
      category: (j['category'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      textAr: j['textAr'] as String,
      source: source,
      translationEn: j['translationEn'] as String?,
      virtue: j['virtue'] as String?,
      repeatCount: ((j['repeatCount'] as num?)?.toInt() ?? 1).clamp(1, 1000),
      sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      featured: (j['featured'] as bool?) ?? false,
      version: (j['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': kind.name,
        'category': category,
        'title': title,
        'textAr': textAr,
        'source': source,
        'translationEn': translationEn,
        'virtue': virtue,
        'repeatCount': repeatCount,
        'sortOrder': sortOrder,
        'featured': featured,
        'version': version,
      };
}

/// Ordered, typed view over the synced items.
class ContentLibrary {
  ContentLibrary(List<ContentItem> items)
      : items = [...items]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder - b.sortOrder : a.title.compareTo(b.title));

  final List<ContentItem> items;

  bool get isEmpty => items.isEmpty;

  List<ContentItem> azkar(ZikrSet set) => [
        for (final i in items)
          if (i.kind == ContentKind.zikr && i.category == set.key) i,
      ];
  List<ContentItem> duas(DuaCategory c) => [
        for (final i in items)
          if (i.kind == ContentKind.dua && i.category == c.key) i,
      ];
  ContentItem? byId(String id) => items.where((i) => i.id == id).firstOrNull;

  /// «دعاء اليوم»: deterministic by local date from the featured pool (falls back to all duas).
  ContentItem? duaOfTheDay(String isoDate) {
    final duas = [
      for (final i in items)
        if (i.kind == ContentKind.dua) i,
    ];
    final pool = duas.where((d) => d.featured).toList();
    final from = pool.isEmpty ? duas : pool;
    if (from.isEmpty) return null;
    var h = 0x811c9dc5;
    for (final c in isoDate.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return from[h % from.length];
  }
}
