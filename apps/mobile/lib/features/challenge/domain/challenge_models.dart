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

  /// null for a task this app version doesn't know (the admin may add one later).
  static TaskKey? tryWire(String s) => values.where((t) => t.wire == s).firstOrNull;
}

enum BonusKind {
  whiteDaysFast('white_days_fast'),
  monThuFast('mon_thu_fast'),
  fridayKahf('friday_kahf'),
  ramadanFast('ramadan_fast'),
  taraweeh('taraweeh'),
  ramadanJuz('ramadan_juz');

  const BonusKind(this.wire);
  final String wire;
  static BonusKind? tryWire(String s) => values.where((b) => b.wire == s).firstOrNull;
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
  const ChallengeDay({
    required this.date,
    required this.dayNumber,
    required this.status,
    required this.points,
    required this.completed,
    this.bonuses = const {},
  });

  final String date; // YYYY-MM-DD
  final int dayNumber;
  final DayStatus status;
  final int points;
  final Set<TaskKey> completed;
  final Set<BonusKind> bonuses;

  factory ChallengeDay.fromJson(Map<String, dynamic> j) => ChallengeDay(
        date: j['date'] as String,
        dayNumber: j['dayNumber'] as int,
        status: DayStatus.values.byName(j['status'] as String),
        points: j['points'] as int,
        completed: (j['completedTasks'] as List).map((e) => TaskKey.tryWire(e as String)).whereType<TaskKey>().toSet(),
        bonuses: ((j['bonuses'] as List?) ?? const []).map((e) => BonusKind.tryWire(e as String)).whereType<BonusKind>().toSet(),
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
      bonuses: bonuses,
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
    this.qadaDays = 0,
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

  /// Days kept through qada over the journey.
  final int qadaDays;

  double get progress => challengeLengthDays == 0 ? 0 : dayNumber / challengeLengthDays;
  bool get todayComplete => today != null && tasks.every((t) => today!.completed.contains(t.key));

  factory ChallengeSummary.fromJson(Map<String, dynamic> j) => ChallengeSummary(
        enrolled: j['enrolled'] as bool,
        startedOn: j['startedOn'] as String?,
        dayNumber: j['dayNumber'] as int,
        streak: j['streak'] as int,
        balance: j['balance'] as int,
        today: j['today'] == null ? null : ChallengeDay.fromJson((j['today'] as Map).cast<String, dynamic>()),
        tasks: [
          for (final e in j['tasks'] as List)
            if (TaskKey.tryWire((e as Map)['key'] as String) != null) ChallengeTask.fromJson(e.cast<String, dynamic>()),
        ],
        challengeLengthDays: (j['challengeLengthDays'] as int?) ?? 365,
        nextMilestone: j['nextMilestone'] == null
            ? null
            : Milestone(
                days: (j['nextMilestone'] as Map)['days'] as int,
                points: (j['nextMilestone'] as Map)['points'] as int,
              ),
        qadaDays: (j['qadaDays'] as int?) ?? 0,
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
      qadaDays: qadaDays,
    );
  }
}

/// Calendar pips (spec §5.21), computed server-side from the Hijri date.
enum SpecialDay {
  whiteDay('white_day'),
  friday('friday'),
  monThu('mon_thu'),
  ramadan('ramadan'),
  eidFitr('eid_fitr'),
  eidAdha('eid_adha'),
  arafah('arafah'),
  ashura('ashura');

  const SpecialDay(this.wire);
  final String wire;
  static SpecialDay? tryWire(String s) => values.where((d) => d.wire == s).firstOrNull;
}

/// One day of `GET /v1/challenge/calendar`.
class CalendarCell {
  const CalendarCell({
    required this.gregorian,
    required this.hijriDay,
    required this.hijriMonth,
    required this.hijriYear,
    required this.hijriMonthNameAr,
    required this.weekday,
    required this.challenge,
    required this.special,
  });

  final String gregorian;
  final int hijriDay;
  final int hijriMonth;
  final int hijriYear;
  final String hijriMonthNameAr;

  /// 0 = Sunday … 6 = Saturday.
  final int weekday;

  /// null when the day is outside the user's 365-day journey.
  final ChallengeDay? challenge;
  final Set<SpecialDay> special;

  factory CalendarCell.fromJson(Map<String, dynamic> j) => CalendarCell(
        gregorian: j['gregorian'] as String,
        hijriDay: j['hijriDay'] as int,
        hijriMonth: j['hijriMonth'] as int,
        hijriYear: j['hijriYear'] as int,
        hijriMonthNameAr: j['hijriMonthNameAr'] as String,
        weekday: j['weekday'] as int,
        challenge: j['challenge'] == null ? null : ChallengeDay.fromJson((j['challenge'] as Map).cast<String, dynamic>()),
        special: ((j['special'] as List?) ?? const []).map((e) => SpecialDay.tryWire(e as String)).whereType<SpecialDay>().toSet(),
      );
}

class ChallengeCalendar {
  const ChallengeCalendar({
    required this.month,
    required this.enrolled,
    required this.startedOn,
    required this.endsOn,
    required this.today,
    required this.dayNumber,
    required this.streak,
    required this.balance,
    required this.qadaWindowDays,
    required this.qadaDayPoints,
    required this.dailyTotal,
    required this.days,
  });

  final String month;
  final bool enrolled;
  final String? startedOn;
  final String? endsOn;
  final String today;
  final int dayNumber;
  final int streak;
  final int balance;
  final int qadaWindowDays;
  final int qadaDayPoints;
  final int dailyTotal;
  final List<CalendarCell> days;

  factory ChallengeCalendar.fromJson(Map<String, dynamic> j) => ChallengeCalendar(
        month: j['month'] as String,
        enrolled: j['enrolled'] as bool,
        startedOn: j['startedOn'] as String?,
        endsOn: j['endsOn'] as String?,
        today: j['today'] as String,
        dayNumber: j['dayNumber'] as int,
        streak: j['streak'] as int,
        balance: j['balance'] as int,
        qadaWindowDays: j['qadaWindowDays'] as int,
        qadaDayPoints: j['qadaDayPoints'] as int,
        dailyTotal: j['dailyTotal'] as int,
        days: (j['days'] as List).map((e) => CalendarCell.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );

  /// Rule: qada only for past, not-complete days inside the window (spec §5.21).
  bool canMakeUp(CalendarCell cell) {
    final c = cell.challenge;
    if (c == null || qadaWindowDays <= 0) return false;
    if (c.status != DayStatus.missed && c.status != DayStatus.partial) return false;
    final age = DateTime.parse(today).difference(DateTime.parse(cell.gregorian)).inDays;
    return age >= 1 && age <= qadaWindowDays;
  }
}
