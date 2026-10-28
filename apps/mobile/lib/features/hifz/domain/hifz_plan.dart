import 'package:yaqeen/core/time/zoned.dart';
import '../../quran/domain/quran_data.dart';
import 'review_scheduler.dart';

/// Plan goals (spec §5.25 «خطتي»). Juz ʿAmma is memorised from an-Nās upwards, as it is taught;
/// the others in mushaf order.
enum HifzGoal {
  amma(114, 78),
  tabarak(67, 77),
  kahf(18, 18),
  all(1, 114);

  const HifzGoal(this.first, this.last);
  final int first;
  final int last;

  /// Surahs in memorisation order.
  List<int> get surahs => first <= last ? [for (var s = first; s <= last; s++) s] : [for (var s = first; s >= last; s--) s];

  int ayat(QuranData q) => surahs.fold(0, (n, s) => n + q.surah(s).ayahCount);
}

/// A memorised passage inside one surah; reviewed on its own schedule.
class HifzPortion {
  const HifzPortion({
    required this.surah,
    required this.from,
    required this.to,
    required this.memorisedOn,
    required this.review,
    this.lastReview,
  });

  final int surah;
  final int from;
  final int to;
  final DateTime memorisedOn;
  final ReviewState review;
  final DateTime? lastReview;

  String get id => '$surah:$from-$to';
  int get length => to - from + 1;

  HifzPortion rated(ReviewGrade g, DateTime today) => HifzPortion(
        surah: surah,
        from: from,
        to: to,
        memorisedOn: memorisedOn,
        review: ReviewScheduler.review(review, g, today),
        lastReview: DateTime(today.year, today.month, today.day),
      );

  Map<String, dynamic> toJson() => {
        's': surah,
        'f': from,
        't': to,
        'm': memorisedOn.toIso8601String(),
        'rv': review.toJson(),
        if (lastReview != null) 'l': lastReview!.toIso8601String(),
      };

  factory HifzPortion.fromJson(Map<String, dynamic> j) => HifzPortion(
        surah: j['s'] as int,
        from: j['f'] as int,
        to: j['t'] as int,
        memorisedOn: DateTime.parse(j['m'] as String),
        review: ReviewState.fromJson((j['rv'] as Map).cast<String, dynamic>()),
        lastReview: j['l'] == null ? null : DateTime.parse(j['l'] as String),
      );
}

/// Whole hifz state — device only (spec §5.25 rule; no sync, no analytics).
class HifzPlan {
  const HifzPlan({required this.goal, required this.perDay, this.portions = const [], this.activeDays = const {}});

  final HifzGoal goal;

  /// New ayat per day (1–20).
  final int perDay;
  final List<HifzPortion> portions;

  /// Local dates (YYYY-MM-DD) with a memorisation or review — for the 14-day strip.
  final Set<String> activeDays;

  static const minPerDay = 1;
  static const maxPerDay = 20;

  int memorisedAyat() => portions.fold(0, (n, p) => n + p.length);

  /// Next ayah to memorise, or null when the goal is complete.
  AyahRef? cursor(QuranData q) {
    final done = <int, int>{}; // surah → highest memorised ayah (portions are contiguous from 1)
    for (final p in portions) {
      if (p.to > (done[p.surah] ?? 0)) done[p.surah] = p.to;
    }
    for (final s in goal.surahs) {
      final last = done[s] ?? 0;
      if (last < q.surah(s).ayahCount) return AyahRef(s, last + 1);
    }
    return null;
  }

  /// Today's new passage: [perDay] ayat from the cursor, never crossing into the next surah.
  ({int surah, int from, int to})? today(QuranData q) {
    final c = cursor(q);
    if (c == null) return null;
    final end = (c.ayah + perDay - 1).clamp(c.ayah, q.surah(c.surah).ayahCount);
    return (surah: c.surah, from: c.ayah, to: end);
  }

  bool memorisedToday(DateTime today) => portions.any((p) => _sameDay(p.memorisedOn, today));

  HifzPlan memorise(QuranData q, DateTime today) {
    final t = this.today(q);
    if (t == null) return this;
    final day = DateTime(today.year, today.month, today.day);
    final portion = HifzPortion(
      surah: t.surah,
      from: t.from,
      to: t.to,
      memorisedOn: day,
      // First review tomorrow — new memorisation is fragile.
      review: ReviewState(intervalDays: 1, due: Zoned.addDays(day, 1)),
    );
    return copyWith(portions: [...portions, portion], activeDays: {...activeDays, _iso(day)});
  }

  List<HifzPortion> due(DateTime today) =>
      portions.where((p) => ReviewScheduler.isDue(p.review, today)).toList()..sort((a, b) => a.review.due.compareTo(b.review.due));

  /// Not due yet — shown with «غداً / بعد N أيام».
  List<HifzPortion> upcoming(DateTime today) =>
      portions.where((p) => !ReviewScheduler.isDue(p.review, today)).toList()..sort((a, b) => a.review.due.compareTo(b.review.due));

  HifzPlan rate(String portionId, ReviewGrade g, DateTime today) => copyWith(
        portions: [for (final p in portions) p.id == portionId ? p.rated(g, today) : p],
        activeDays: {...activeDays, _iso(today)},
      );

  double progress(QuranData q) => (memorisedAyat() / goal.ayat(q)).clamp(0, 1);

  /// Finish date at the current rate (remaining ÷ perDay), or null when complete.
  DateTime? finishEstimate(QuranData q, DateTime today) {
    final remaining = goal.ayat(q) - memorisedAyat();
    if (remaining <= 0) return null;
    return Zoned.addDays(DateTime(today.year, today.month, today.day), (remaining / perDay).ceil());
  }

  int activeInLast(int days, DateTime today) {
    var n = 0;
    for (var i = 0; i < days; i++) {
      if (activeDays.contains(_iso(Zoned.addDays(today, -i)))) n++;
    }
    return n;
  }

  /// Days on which a review falls due (local notifications, spec §6.5).
  Set<DateTime> dueDates() => {for (final p in portions) p.review.due};

  HifzPlan copyWith({HifzGoal? goal, int? perDay, List<HifzPortion>? portions, Set<String>? activeDays}) => HifzPlan(
        goal: goal ?? this.goal,
        perDay: (perDay ?? this.perDay).clamp(minPerDay, maxPerDay),
        portions: portions ?? this.portions,
        activeDays: activeDays ?? this.activeDays,
      );

  Map<String, dynamic> toJson() => {
        'goal': goal.name,
        'perDay': perDay,
        'portions': [for (final p in portions) p.toJson()],
        'days': (activeDays.toList()..sort()).reversed.take(60).toList(),
      };

  static HifzPlan? tryParse(Object? j) {
    if (j is! Map || j['goal'] is! String) return null;
    final goal = HifzGoal.values.asNameMap()[j['goal']];
    if (goal == null) return null;
    return HifzPlan(
      goal: goal,
      perDay: ((j['perDay'] as int?) ?? 5).clamp(minPerDay, maxPerDay),
      portions: [for (final p in (j['portions'] as List?) ?? const []) HifzPortion.fromJson((p as Map).cast<String, dynamic>())],
      activeDays: {...((j['days'] as List?) ?? const []).cast<String>()},
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
