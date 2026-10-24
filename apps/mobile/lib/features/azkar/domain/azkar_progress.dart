import '../../content/domain/content_item.dart';

/// Today's azkar counts (spec §5.19): persisted per local day, per item; a set completing ticks its
/// challenge task once a day (`morning_azkar`, `evening_azkar`).
class AzkarDay {
  const AzkarDay({required this.date, this.counts = const {}, this.ticked = const {}});

  final String date;
  final Map<String, int> counts;

  /// Sets whose challenge task was already queued today.
  final Set<String> ticked;

  int countOf(ContentItem i) => (counts[i.id] ?? 0).clamp(0, i.repeatCount);
  bool doneItem(ContentItem i) => countOf(i) >= i.repeatCount;
  bool doneSet(List<ContentItem> items) => items.isNotEmpty && items.every(doneItem);

  /// One tap: +1, capped at the item's repeat count.
  AzkarDay tap(ContentItem i) => doneItem(i) ? this : AzkarDay(date: date, counts: {...counts, i.id: countOf(i) + 1}, ticked: ticked);

  AzkarDay reset(ContentItem i) => AzkarDay(date: date, counts: {...counts}..remove(i.id), ticked: ticked);

  AzkarDay markTicked(ZikrSet s) => AzkarDay(date: date, counts: counts, ticked: {...ticked, s.key});

  /// Today's state from what was stored (a new day starts at zero).
  static AzkarDay forToday(AzkarDay? stored, String today) => stored == null || stored.date != today ? AzkarDay(date: today) : stored;

  Map<String, dynamic> toJson() => {'date': date, 'counts': counts, 'ticked': ticked.toList()};
  static AzkarDay? tryParse(Object? j) => j is Map && j['date'] is String
      ? AzkarDay(
          date: j['date'] as String,
          counts: ((j['counts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
          ticked: {...((j['ticked'] as List?) ?? const []).cast<String>()},
        )
      : null;
}

/// The task a completed set ticks, if any.
String? taskWireFor(ZikrSet s) => switch (s) {
      ZikrSet.morning => 'morning_azkar',
      ZikrSet.evening => 'evening_azkar',
      _ => null,
    };
