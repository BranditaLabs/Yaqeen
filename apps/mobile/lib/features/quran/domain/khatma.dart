import 'quran_data.dart';

/// A khatma plan (spec §5.30): read the whole mushaf by a date, or at a steady pace. Pages count
/// when the reader has shown them for the wird threshold (20 s), in any order. Device only.
class Khatma {
  const Khatma({
    required this.startedOn,
    this.targetDate,
    this.pagesPerDay,
    this.read = const {},
    this.finishedOn,
  }) : assert(targetDate != null || pagesPerDay != null);

  /// YYYY-MM-DD (the place's calendar).
  final String startedOn;

  /// Finish by this day (inclusive), or …
  final String? targetDate;

  /// … read this many pages a day.
  final int? pagesPerDay;

  /// Pages read since the plan started.
  final Set<int> read;
  final String? finishedOn;

  static const total = QuranData.pageCount;

  int get done => read.length;
  int get remaining => total - done;
  double get progress => done / total;
  bool get finished => finishedOn != null;

  /// The first page not read yet (where today's portion starts), or null when complete.
  int? get nextPage {
    for (var p = 1; p <= total; p++) {
      if (!read.contains(p)) return p;
    }
    return null;
  }

  /// Days left including [today] (≥ 1), for a dated plan.
  int daysLeft(String today) {
    if (targetDate == null) return (remaining / (pagesPerDay ?? 1)).ceil().clamp(1, 100000);
    return (_day(targetDate!).difference(_day(today)).inDays + 1).clamp(1, 100000);
  }

  /// Pages to read today to stay on plan: the fixed pace, or what's left spread over the days left.
  /// Today's already-read pages count towards it ([readToday]).
  int dailyTarget(String today, {int readToday = 0}) {
    if (pagesPerDay != null) return pagesPerDay!;
    return ((remaining + readToday) / daysLeft(today)).ceil();
  }

  /// Pages the plan expected done by the end of [today] (for «متقدّم / متأخّر»).
  int expectedBy(String today) {
    final elapsed = _day(today).difference(_day(startedOn)).inDays + 1;
    if (pagesPerDay != null) return (pagesPerDay! * elapsed).clamp(0, total);
    final span = _day(targetDate!).difference(_day(startedOn)).inDays + 1;
    return ((total * elapsed) / span).floor().clamp(0, total);
  }

  /// Positive: pages ahead of plan; negative: behind (at the end of today).
  int balance(String today) => done - expectedBy(today);

  /// The day the plan will finish at today's pace (fixed-pace plans).
  String projectedFinish(String today) {
    final per = pagesPerDay ?? dailyTarget(today);
    final days = per <= 0 ? 0 : (remaining / per).ceil();
    return _iso(_day(today).add(Duration(days: days == 0 ? 0 : days - 1)));
  }

  Khatma markRead(int page, String today) {
    if (finished || read.contains(page) || page < 1 || page > total) return this;
    final next = {...read, page};
    return Khatma(
      startedOn: startedOn,
      targetDate: targetDate,
      pagesPerDay: pagesPerDay,
      read: next,
      finishedOn: next.length == total ? today : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'startedOn': startedOn,
        if (targetDate != null) 'targetDate': targetDate,
        if (pagesPerDay != null) 'pagesPerDay': pagesPerDay,
        'read': _ranges(read),
        if (finishedOn != null) 'finishedOn': finishedOn,
      };

  factory Khatma.fromJson(Map<String, dynamic> j) => Khatma(
        startedOn: j['startedOn'] as String,
        targetDate: j['targetDate'] as String?,
        pagesPerDay: (j['pagesPerDay'] as num?)?.toInt() ?? (j['targetDate'] == null ? 5 : null),
        read: _unranges(j['read']),
        finishedOn: j['finishedOn'] as String?,
      );

  /// Pages stored as [from, to] runs — a whole khatma is one pair instead of 604 numbers.
  static List<List<int>> _ranges(Set<int> pages) {
    final sorted = pages.toList()..sort();
    final out = <List<int>>[];
    for (final p in sorted) {
      if (out.isNotEmpty && out.last[1] == p - 1) {
        out.last[1] = p;
      } else {
        out.add([p, p]);
      }
    }
    return out;
  }

  static Set<int> _unranges(Object? raw) => {
        for (final r in (raw as List? ?? const []))
          if (r is List && r.length == 2 && r[0] is int && r[1] is int)
            for (var p = (r[0] as int).clamp(1, total); p <= (r[1] as int).clamp(1, total); p++) p,
      };

  static DateTime _day(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A completed khatma, kept for the history list.
class KhatmaRecord {
  const KhatmaRecord({required this.startedOn, required this.finishedOn});
  final String startedOn;
  final String finishedOn;

  int get days => Khatma._day(finishedOn).difference(Khatma._day(startedOn)).inDays + 1;

  Map<String, dynamic> toJson() => {'startedOn': startedOn, 'finishedOn': finishedOn};
  factory KhatmaRecord.fromJson(Map<String, dynamic> j) =>
      KhatmaRecord(startedOn: j['startedOn'] as String, finishedOn: j['finishedOn'] as String);
}
