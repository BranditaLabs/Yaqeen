/// Plans LOCAL notifications (adhan, pre-prayer, azkar, wird) — pure logic, no plugins.
///
/// Why local: prayer reminders must fire on time with no network, and the server
/// should not know when a user prays. Constraints handled here:
///  - iOS keeps at most 64 pending local notifications per app → we keep [iosLimit]
///    (60, leaving slack) and re-plan on every app open / background refresh.
///  - Android 12+ exact alarms need SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM; the
///    scheduler adapter falls back to inexact when not granted.
///  - Custom adhan sounds on iOS must be ≤ 30 s (bundled as .caf).
enum Prayer { fajr, dhuhr, asr, maghrib, isha }

enum ReminderKind { adhan, prePrayer, morningAzkar, eveningAzkar, wird }

class PrayerDay {
  const PrayerDay(this.date, this.times);
  final DateTime date;
  final Map<Prayer, DateTime> times;
}

class ReminderPrefs {
  const ReminderPrefs({
    this.adhan = const {Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha},
    this.prePrayerMinutes,
    this.morningAzkar = true,
    this.eveningAzkar = true,
    this.wirdAt,
    this.morningAfterFajrMinutes = 30,
    this.eveningAfterAsrMinutes = 30,
  });

  final Set<Prayer> adhan;

  /// e.g. 10 → "Dhuhr in 10 minutes". null disables pre-prayer reminders.
  final int? prePrayerMinutes;
  final bool morningAzkar;
  final bool eveningAzkar;

  /// Daily wird reminder as minutes since midnight, or null.
  final int? wirdAt;
  final int morningAfterFajrMinutes;
  final int eveningAfterAsrMinutes;
}

class PlannedNotification {
  const PlannedNotification({required this.id, required this.at, required this.kind, this.prayer});

  /// Stable id (same reminder → same id) so re-planning replaces instead of duplicating.
  final int id;
  final DateTime at;
  final ReminderKind kind;
  final Prayer? prayer;

  @override
  String toString() => 'Planned($kind${prayer != null ? ' ${prayer!.name}' : ''} @ $at)';
}

class NotificationPlan {
  const NotificationPlan(this.items, this.replanBefore);
  final List<PlannedNotification> items;

  /// Re-plan before this moment so the queue never runs dry.
  final DateTime? replanBefore;
}

abstract final class NotificationPlanner {
  static const iosLimit = 60;
  static const androidLimit = 200;

  static int stableId(DateTime day, ReminderKind kind, [Prayer? prayer]) {
    final d = day.year * 10000 + day.month * 100 + day.day; // 8 digits
    return (d % 1000000) * 100 + kind.index * 10 + (prayer?.index ?? 9);
  }

  static NotificationPlan plan({
    required List<PrayerDay> days,
    required ReminderPrefs prefs,
    required DateTime now,
    int limit = iosLimit,
  }) {
    final out = <PlannedNotification>[];
    for (final day in days) {
      final d = DateTime(day.date.year, day.date.month, day.date.day);
      for (final p in Prayer.values) {
        final t = day.times[p];
        if (t == null) continue;
        if (prefs.adhan.contains(p)) {
          out.add(PlannedNotification(id: stableId(d, ReminderKind.adhan, p), at: t, kind: ReminderKind.adhan, prayer: p));
        }
        final pre = prefs.prePrayerMinutes;
        if (pre != null && pre > 0) {
          out.add(PlannedNotification(
            id: stableId(d, ReminderKind.prePrayer, p),
            at: t.subtract(Duration(minutes: pre)),
            kind: ReminderKind.prePrayer,
            prayer: p,
          ));
        }
      }
      final fajr = day.times[Prayer.fajr];
      final asr = day.times[Prayer.asr];
      if (prefs.morningAzkar && fajr != null) {
        out.add(PlannedNotification(
          id: stableId(d, ReminderKind.morningAzkar),
          at: fajr.add(Duration(minutes: prefs.morningAfterFajrMinutes)),
          kind: ReminderKind.morningAzkar,
        ));
      }
      if (prefs.eveningAzkar && asr != null) {
        out.add(PlannedNotification(
          id: stableId(d, ReminderKind.eveningAzkar),
          at: asr.add(Duration(minutes: prefs.eveningAfterAsrMinutes)),
          kind: ReminderKind.eveningAzkar,
        ));
      }
      final wird = prefs.wirdAt;
      if (wird != null) {
        out.add(PlannedNotification(
          id: stableId(d, ReminderKind.wird),
          at: d.add(Duration(minutes: wird)),
          kind: ReminderKind.wird,
        ));
      }
    }

    final future = out.where((n) => n.at.isAfter(now)).toList()..sort((a, b) => a.at.compareTo(b.at));
    final kept = future.take(limit).toList();
    final truncated = future.length > kept.length;
    // Re-plan a day before the last kept reminder (or when it fires if the window is short).
    final last = kept.isEmpty ? null : kept.last.at;
    final replan = last == null ? null : (truncated ? last.subtract(const Duration(hours: 24)) : last);
    return NotificationPlan(kept, replan != null && replan.isBefore(now) ? now : replan);
  }
}

/// Platform adapter (flutter_local_notifications). Implemented in
/// `local_notifications_adapter.dart` when the plugin is added.
abstract interface class LocalNotificationScheduler {
  Future<bool> requestPermission();
  Future<void> replaceAll(List<PlannedNotification> plan);
  Future<void> cancelAll();
}

class NoopLocalNotificationScheduler implements LocalNotificationScheduler {
  List<PlannedNotification> scheduled = [];

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async => scheduled = List.of(plan);
  @override
  Future<void> cancelAll() async => scheduled = [];
}
