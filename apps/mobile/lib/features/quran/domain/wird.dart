/// Daily wird (spec §5.11): a page counts once it has been visible for at least
/// [minSecondsPerPage]; when the day's goal is reached the `wird` challenge task ticks — once a day.
class WirdDay {
  const WirdDay({required this.date, this.pages = const {}, this.ticked = false});

  /// YYYY-MM-DD (local).
  final String date;
  final Set<int> pages;

  /// The challenge task was already queued today.
  final bool ticked;

  int get count => pages.length;

  WirdDay withPage(int page) => WirdDay(date: date, pages: {...pages, page}, ticked: ticked);
  WirdDay markTicked() => WirdDay(date: date, pages: pages, ticked: true);

  Map<String, dynamic> toJson() => {'date': date, 'pages': pages.toList()..sort(), 'ticked': ticked};
  factory WirdDay.fromJson(Map<String, dynamic> j) => WirdDay(
        date: j['date'] as String,
        pages: ((j['pages'] as List?) ?? const []).cast<int>().toSet(),
        ticked: (j['ticked'] as bool?) ?? false,
      );
}

abstract final class WirdRules {
  static const minSecondsPerPage = 20;

  /// Result of reading [page] for [visibleFor] on [today].
  static ({WirdDay day, bool counted, bool tickNow}) read(
    WirdDay? current, {
    required String today,
    required int page,
    required Duration visibleFor,
    required int goalPages,
    int minSeconds = minSecondsPerPage,
  }) {
    var day = current == null || current.date != today ? WirdDay(date: today) : current;
    if (visibleFor.inSeconds < minSeconds || day.pages.contains(page)) return (day: day, counted: false, tickNow: false);
    day = day.withPage(page);
    final tickNow = !day.ticked && day.count >= goalPages;
    if (tickNow) day = day.markTicked();
    return (day: day, counted: true, tickNow: tickNow);
  }
}
