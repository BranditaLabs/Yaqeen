import 'package:yaqeen/core/time/zoned.dart';

/// Spaced review for Hifz (memorisation) — pure logic.
///
/// The three buttons on the review card map to first intervals of 1 / 3 / 14 days
/// (as in the design). Later reviews grow from the previous interval; "hard" always
/// brings the passage back tomorrow.
enum ReviewGrade { hard, good, easy }

class ReviewState {
  const ReviewState({required this.intervalDays, required this.due, this.reps = 0});

  final int intervalDays;
  final DateTime due;
  final int reps;

  Map<String, dynamic> toJson() => {'i': intervalDays, 'd': due.toIso8601String(), 'r': reps};
  factory ReviewState.fromJson(Map<String, dynamic> j) =>
      ReviewState(intervalDays: j['i'] as int, due: DateTime.parse(j['d'] as String), reps: j['r'] as int);
}

abstract final class ReviewScheduler {
  static const maxIntervalDays = 120;

  static int nextInterval(ReviewGrade grade, int previous) {
    final next = switch (grade) {
      ReviewGrade.hard => 1,
      ReviewGrade.good => previous < 3 ? 3 : (previous * 2),
      ReviewGrade.easy => previous < 14 ? 14 : (previous * 2.5).round(),
    };
    return next > maxIntervalDays ? maxIntervalDays : next;
  }

  static ReviewState review(ReviewState? current, ReviewGrade grade, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    final interval = nextInterval(grade, current?.intervalDays ?? 0);
    return ReviewState(intervalDays: interval, due: Zoned.addDays(day, interval), reps: (current?.reps ?? 0) + 1);
  }

  static bool isDue(ReviewState s, DateTime today) => !DateTime(today.year, today.month, today.day).isBefore(s.due);
}
