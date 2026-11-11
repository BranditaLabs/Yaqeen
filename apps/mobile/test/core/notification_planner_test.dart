import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';

PrayerDay cairoDay(DateTime d) => PrayerDay(d, {
      Prayer.fajr: DateTime(d.year, d.month, d.day, 4, 30),
      Prayer.dhuhr: DateTime(d.year, d.month, d.day, 11, 40),
      Prayer.asr: DateTime(d.year, d.month, d.day, 14, 50),
      Prayer.maghrib: DateTime(d.year, d.month, d.day, 17, 15),
      Prayer.isha: DateTime(d.year, d.month, d.day, 18, 35),
    });

void main() {
  final now = DateTime(2026, 10, 20, 12, 0);
  List<PrayerDay> days(int n) => [for (var i = 0; i < n; i++) cairoDay(DateTime(2026, 10, 20).add(Duration(days: i)))];

  test('drops reminders in the past', () {
    final plan = NotificationPlanner.plan(days: days(1), prefs: const ReminderPrefs(), now: now);
    expect(plan.items.every((n) => n.at.isAfter(now)), isTrue);
    // After 12:00: asr, maghrib, isha adhan + evening azkar.
    expect(plan.items.length, 4);
  });

  test('never exceeds the iOS budget and keeps the earliest reminders', () {
    final plan = NotificationPlanner.plan(
      days: days(14),
      prefs: const ReminderPrefs(prePrayerMinutes: 10, wird: SlotTime.at(21 * 60)),
      now: now,
    );
    expect(plan.items.length, NotificationPlanner.iosLimit);
    for (var i = 1; i < plan.items.length; i++) {
      expect(plan.items[i].at.isBefore(plan.items[i - 1].at), isFalse);
    }
    expect(plan.replanBefore!.isBefore(plan.items.last.at), isTrue);
  });

  test('ids are stable and unique', () {
    final a = NotificationPlanner.plan(days: days(3), prefs: const ReminderPrefs(prePrayerMinutes: 10), now: now);
    final b = NotificationPlanner.plan(days: days(3), prefs: const ReminderPrefs(prePrayerMinutes: 10), now: now);
    expect(a.items.map((e) => e.id).toList(), b.items.map((e) => e.id).toList());
    expect(a.items.map((e) => e.id).toSet().length, a.items.length);
  });

  test('respects disabled prayers', () {
    final plan = NotificationPlanner.plan(
      days: days(2),
      prefs: const ReminderPrefs(adhan: {Prayer.fajr}, morningAzkar: false, eveningAzkar: false),
      now: now,
    );
    expect(plan.items.map((e) => e.prayer).toSet(), {Prayer.fajr});
  });
  test('a missed hifz review keeps reminding every day until it is rated', () {
    final plan = NotificationPlanner.plan(
      days: days(3),
      prefs: ReminderPrefs(hifzDueDates: {DateTime(2026, 10, 18)}, hifz: const SlotTime.at(13 * 60)),
      now: now,
    );
    final hifz = plan.items.where((n) => n.kind == ReminderKind.hifzDue).map((n) => n.at).toList();
    expect(hifz, [DateTime(2026, 10, 20, 13), DateTime(2026, 10, 21, 13), DateTime(2026, 10, 22, 13)]);
  });

  test('a hifz review due later reminds from its due day on', () {
    final plan = NotificationPlanner.plan(
      days: days(3),
      prefs: ReminderPrefs(hifzDueDates: {DateTime(2026, 10, 22)}, hifz: const SlotTime.at(13 * 60)),
      now: now,
    );
    expect(plan.items.where((n) => n.kind == ReminderKind.hifzDue).map((n) => n.at).toList(), [DateTime(2026, 10, 22, 13)]);
  });
}
