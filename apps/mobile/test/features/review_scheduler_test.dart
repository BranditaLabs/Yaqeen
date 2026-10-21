import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/hifz/domain/review_scheduler.dart';

void main() {
  final today = DateTime(2026, 10, 20, 9);

  test('first review: hard 1 / good 3 / easy 14 days', () {
    expect(ReviewScheduler.review(null, ReviewGrade.hard, today).intervalDays, 1);
    expect(ReviewScheduler.review(null, ReviewGrade.good, today).intervalDays, 3);
    expect(ReviewScheduler.review(null, ReviewGrade.easy, today).intervalDays, 14);
  });

  test('intervals grow and cap at 120 days; hard resets', () {
    var s = ReviewScheduler.review(null, ReviewGrade.good, today);
    s = ReviewScheduler.review(s, ReviewGrade.good, today);
    expect(s.intervalDays, 6);
    s = ReviewScheduler.review(s, ReviewGrade.easy, today);
    expect(s.intervalDays, 14);
    for (var i = 0; i < 10; i++) {
      s = ReviewScheduler.review(s, ReviewGrade.easy, today);
    }
    expect(s.intervalDays, ReviewScheduler.maxIntervalDays);
    expect(ReviewScheduler.review(s, ReviewGrade.hard, today).intervalDays, 1);
  });

  test('due dates are whole days', () {
    final s = ReviewScheduler.review(null, ReviewGrade.good, today);
    expect(s.due, DateTime(2026, 10, 23));
    expect(ReviewScheduler.isDue(s, DateTime(2026, 10, 22, 23)), isFalse);
    expect(ReviewScheduler.isDue(s, DateTime(2026, 10, 23, 0, 1)), isTrue);
  });
}
