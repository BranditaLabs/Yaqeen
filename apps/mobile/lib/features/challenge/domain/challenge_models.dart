/// Mirrors `ChallengeSummary` / `ChallengeDay` in packages/contracts/src/api.ts.
enum TaskKey {
  wird('wird'),
  morningAzkar('morning_azkar'),
  fivePrayers('five_prayers'),
  eveningAzkar('evening_azkar'),
  listen('listen'),
  dailyTask('daily_task');

  const TaskKey(this.wire);
  final String wire;

  static TaskKey fromWire(String s) => values.firstWhere((t) => t.wire == s);
}

enum DayStatus { done, partial, qada, missed, today, future }

class ChallengeTask {
  const ChallengeTask({required this.key, required this.labelAr, required this.labelEn, required this.points});
  final TaskKey key;
  final String labelAr;
  final String labelEn;
  final int points;

  factory ChallengeTask.fromJson(Map<String, dynamic> j) => ChallengeTask(
        key: TaskKey.fromWire(j['key'] as String),
        labelAr: j['labelAr'] as String,
        labelEn: j['labelEn'] as String,
        points: j['points'] as int,
      );
}

class ChallengeDay {
  const ChallengeDay({required this.date, required this.dayNumber, required this.status, required this.points, required this.completed});

  final String date; // YYYY-MM-DD
  final int dayNumber;
  final DayStatus status;
  final int points;
  final Set<TaskKey> completed;

  factory ChallengeDay.fromJson(Map<String, dynamic> j) => ChallengeDay(
        date: j['date'] as String,
        dayNumber: j['dayNumber'] as int,
        status: DayStatus.values.byName(j['status'] as String),
        points: j['points'] as int,
        completed: (j['completedTasks'] as List).map((e) => TaskKey.fromWire(e as String)).toSet(),
      );

  /// [activeTasks] = how many tasks the admin has switched on (may be fewer than six).
  ChallengeDay withCompleted(TaskKey task, int addPoints, {int activeTasks = 6}) {
    final next = {...completed, task};
    return ChallengeDay(
      date: date,
      dayNumber: dayNumber,
      status: next.length >= activeTasks && status == DayStatus.today ? DayStatus.done : status,
      points: points + addPoints,
      completed: next,
    );
  }
}

/// Next automatic streak bonus (set by the admin), e.g. 30 days → +200.
class Milestone {
  const Milestone({required this.days, required this.points});
  final int days;
  final int points;
}

class ChallengeSummary {
  const ChallengeSummary({
    required this.enrolled,
    required this.startedOn,
    required this.dayNumber,
    required this.streak,
    required this.balance,
    required this.today,
    required this.tasks,
    this.challengeLengthDays = 365,
    this.nextMilestone,
  });

  final bool enrolled;
  final String? startedOn;
  final int dayNumber;
  final int streak;
  final int balance;
  final ChallengeDay? today;
  final List<ChallengeTask> tasks;

  /// Admin-controlled (dashboard → النقاط والمكافآت). Only the API's active tasks are listed.
  final int challengeLengthDays;
  final Milestone? nextMilestone;

  double get progress => challengeLengthDays == 0 ? 0 : dayNumber / challengeLengthDays;
  bool get todayComplete => today != null && tasks.every((t) => today!.completed.contains(t.key));

  factory ChallengeSummary.fromJson(Map<String, dynamic> j) => ChallengeSummary(
        enrolled: j['enrolled'] as bool,
        startedOn: j['startedOn'] as String?,
        dayNumber: j['dayNumber'] as int,
        streak: j['streak'] as int,
        balance: j['balance'] as int,
        today: j['today'] == null ? null : ChallengeDay.fromJson((j['today'] as Map).cast<String, dynamic>()),
        tasks: (j['tasks'] as List).map((e) => ChallengeTask.fromJson((e as Map).cast<String, dynamic>())).toList(),
        challengeLengthDays: (j['challengeLengthDays'] as int?) ?? 365,
        nextMilestone: j['nextMilestone'] == null
            ? null
            : Milestone(
                days: (j['nextMilestone'] as Map)['days'] as int,
                points: (j['nextMilestone'] as Map)['points'] as int,
              ),
      );

  /// Optimistic update after a local completion (server confirms later via the outbox).
  ChallengeSummary completeLocally(TaskKey task) {
    final t = today;
    if (t == null || t.completed.contains(task)) return this;
    final pts = tasks.firstWhere((x) => x.key == task).points;
    return ChallengeSummary(
      enrolled: enrolled,
      startedOn: startedOn,
      dayNumber: dayNumber,
      streak: streak,
      balance: balance + pts,
      today: t.withCompleted(task, pts, activeTasks: tasks.length),
      tasks: tasks,
      challengeLengthDays: challengeLengthDays,
      nextMilestone: nextMilestone,
    );
  }
}
