import 'package:yaqeen/core/time/zoned.dart';

/// Reading time and pages per day (spec §5.11 «إحصاءات القراءة») — device only. A page view counts
/// at most [maxSecondsPerView] so a phone left open on a page doesn't inflate the time.
class ReadingStats {
  const ReadingStats(this.days);

  /// YYYY-MM-DD → (pages, seconds).
  final Map<String, ({int pages, int seconds})> days;

  static const keepDays = 120;
  static const maxSecondsPerView = 300;

  ReadingStats add(String date, {int pages = 0, int seconds = 0}) {
    final d = days[date] ?? (pages: 0, seconds: 0);
    final next = {...days, date: (pages: d.pages + pages, seconds: d.seconds + seconds.clamp(0, maxSecondsPerView))};
    // Keep the most recent [keepDays] days.
    if (next.length > keepDays) {
      final keys = next.keys.toList()..sort();
      for (final k in keys.take(next.length - keepDays)) {
        next.remove(k);
      }
    }
    return ReadingStats(next);
  }

  /// Totals over the 7 days ending [today] (inclusive).
  ({int pages, int minutes, int activeDays}) week(DateTime today) {
    var pages = 0;
    var seconds = 0;
    var active = 0;
    for (var i = 0; i < 7; i++) {
      final d = days[_iso(Zoned.addDays(today, -i))];
      if (d == null) continue;
      pages += d.pages;
      seconds += d.seconds;
      if (d.pages > 0) active++;
    }
    return (pages: pages, minutes: (seconds / 60).round(), activeDays: active);
  }

  /// Consecutive days with at least one page read, ending today (or yesterday, if today is empty).
  int streak(DateTime today) {
    var n = 0;
    var day = today;
    if ((days[_iso(day)]?.pages ?? 0) == 0) day = Zoned.addDays(day, -1);
    while ((days[_iso(day)]?.pages ?? 0) > 0) {
      n++;
      day = Zoned.addDays(day, -1);
    }
    return n;
  }

  /// Pages per day for the 7 days ending [today], oldest first (the bars).
  List<int> lastSeven(DateTime today) => [for (var i = 6; i >= 0; i--) days[_iso(Zoned.addDays(today, -i))]?.pages ?? 0];

  Map<String, dynamic> toJson() => {
        for (final e in days.entries) e.key: [e.value.pages, e.value.seconds],
      };

  factory ReadingStats.fromJson(Map<String, dynamic> j) => ReadingStats({
        for (final e in j.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key: (pages: (e.value as List)[0] as int, seconds: (e.value as List)[1] as int),
      });

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
