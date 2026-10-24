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
}
