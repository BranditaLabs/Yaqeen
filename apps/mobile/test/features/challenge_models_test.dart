import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/challenge/domain/challenge_models.dart';

void main() {
  final json = {
    'enrolled': true,
    'startedOn': '2026-09-03',
    'dayNumber': 48,
    'streak': 5,
    'balance': 3240,
    'today': {
      'date': '2026-10-20',
      'dayNumber': 48,
      'status': 'today',
      'points': 20,
      'completedTasks': ['wird'],
      'bonuses': [],
    },
    'tasks': [
      for (final (k, p) in [
        ('wird', 20),
        ('morning_azkar', 10),
        ('five_prayers', 25),
        ('evening_azkar', 10),
        ('listen', 10),
        ('daily_task', 25),
      ])
        {'key': k, 'labelAr': k, 'labelEn': k, 'points': p},
    ],
  };

  test('parses the API summary', () {
    final s = ChallengeSummary.fromJson(json);
    expect(s.today!.completed, {TaskKey.wird});
    expect(s.tasks.fold<int>(0, (a, t) => a + t.points), 100);
  });

  test('reads admin-controlled length and next milestone', () {
    final s = ChallengeSummary.fromJson({
      ...json,
      'challengeLengthDays': 100,
      'nextMilestone': {'days': 7, 'points': 50},
    });
    expect(s.progress, closeTo(0.48, 0.001));
    expect(s.nextMilestone!.points, 50);
    expect(ChallengeSummary.fromJson(json).challengeLengthDays, 365); // older API → default
  });

  test('a day with a task switched off completes with the remaining tasks', () {
    final five = {...json, 'tasks': (json['tasks'] as List).where((t) => (t as Map)['key'] != 'listen').toList()};
    var s = ChallengeSummary.fromJson(five);
    for (final k in s.tasks.map((t) => t.key)) {
      s = s.completeLocally(k);
    }
    expect(s.today!.status, DayStatus.done);
    expect(s.todayComplete, isTrue);
  });

  test('optimistic completion adds points once and finishes the day', () {
    var s = ChallengeSummary.fromJson(json);
    s = s.completeLocally(TaskKey.wird); // already done → no change
    expect(s.balance, 3240);
    for (final k in TaskKey.values.where((k) => k != TaskKey.wird)) {
      s = s.completeLocally(k);
    }
    expect(s.balance, 3320);
    expect(s.today!.status, DayStatus.done);
  });

  test('a summary from an earlier day rolls on to the local today, empty', () {
    final s = ChallengeSummary.fromJson(json);
    final next = s.rolledTo('2026-10-22');
    expect(next.today!.date, '2026-10-22');
    expect(next.today!.dayNumber, 50);
    expect(next.dayNumber, 50);
    expect(next.today!.completed, isEmpty);
    expect(next.today!.status, DayStatus.today);
    expect(next.today!.points, 0);
    expect(next.balance, s.balance);
    // Same day or an earlier one: unchanged.
    expect(identical(s.rolledTo('2026-10-20'), s), isTrue);
    expect(identical(s.rolledTo('2026-10-19'), s), isTrue);
  });

  test('calendar journey length follows the server span, not a fixed 365', () {
    ChallengeCalendar cal(String? start, String? end) => ChallengeCalendar.fromJson({
          'month': '2026-10',
          'enrolled': true,
          'startedOn': start,
          'endsOn': end,
          'today': '2026-10-20',
          'dayNumber': 47,
          'streak': 0,
          'balance': 0,
          'qadaWindowDays': 7,
          'qadaDayPoints': 80,
          'dailyTotal': 100,
          'days': <Object>[],
        });
    expect(cal('2026-09-04', '2027-09-03').lengthDays, 365);
    expect(cal('2026-09-04', '2026-12-12').lengthDays, 100);
    expect(cal(null, null).lengthDays, 365);
  });
}
