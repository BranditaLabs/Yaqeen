/// Plans LOCAL notifications (adhan, pre-prayer, azkar, wird, Kahf, hifz) — pure logic, no plugins.
///
/// Why local: prayer reminders must fire on time with no network, and the server
/// should not know when a user prays. Constraints handled here:
///  - iOS keeps at most 64 pending local notifications per app → we keep [iosLimit]
///    (60, leaving slack) and re-plan on every app open / background refresh.
///  - Android 12+ exact alarms need SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM; the
///    scheduler adapter falls back to inexact when not granted.
///  - Custom adhan sounds on iOS must be ≤ 30 s (bundled as .caf).
///  - Quiet hours silence reminders, never a prayer alert (spec §5.17).
enum Prayer { fajr, dhuhr, asr, maghrib, isha, sunrise }

enum ReminderKind { adhan, prePrayer, morningAzkar, eveningAzkar, wird, kahfFriday, wirdMissing, hifzDue, dhikr }

/// How a prayer alerts (mirrors the settings screen: «أذان | تنبيه | صامت»).
enum PrayerAlert { adhan, notify, silent }

/// Android notification channels (spec §6.5) — users can silence each one in the OS.
enum NotificationChannel { adhan, reminders, challenge, offers }

class PrayerDay {
  const PrayerDay(this.date, this.times);
  final DateTime date;
  final Map<Prayer, DateTime> times;
}

/// When a routine reminder fires each day: [minutes] after [prayer], or at [minutes] past local
/// midnight when [prayer] is null (the user's routine, spec §5.2).
class SlotTime {
  const SlotTime.after(Prayer this.prayer, this.minutes);
  const SlotTime.at(this.minutes) : prayer = null;

  final Prayer? prayer;
  final int minutes;

  DateTime? on(PrayerDay day) {
    final p = prayer;
    if (p == null) return day.date.add(Duration(minutes: minutes));
    return day.times[p]?.add(Duration(minutes: minutes));
  }
}

class ReminderPrefs {
  const ReminderPrefs({
    this.adhan = const {Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha},
    this.modes,
    this.prePrayerMinutes,
    this.morningAzkar = true,
    this.eveningAzkar = true,
    this.wird,
    this.morningAfterFajrMinutes = 30,
    this.eveningAfterAsrMinutes = 30,
    this.kahfFriday = false,
    this.kahfAtMinutes = 10 * 60,
    this.wirdMissing = false,
    this.wirdMissingBeforeIshaMinutes = 30,
    this.hifzDueDates = const {},
    this.hifz = const SlotTime.at(9 * 60),
    this.dhikr,
    this.quietStartMinutes,
    this.quietEndMinutes,
  });

  /// Prayers that alert with a full adhan (used when [modes] is null).
  final Set<Prayer> adhan;

  /// Per-prayer alert mode; overrides [adhan] when set.
  final Map<Prayer, PrayerAlert>? modes;

  /// e.g. 10 → "Dhuhr in 10 minutes". null/0 disables pre-prayer reminders.
  final int? prePrayerMinutes;
  final bool morningAzkar;
  final bool eveningAzkar;

  /// Daily Quran (wird) reminder at the user's routine time, or null.
  final SlotTime? wird;
  final int morningAfterFajrMinutes;
  final int eveningAfterAsrMinutes;

  /// «سورة الكهف · كل جمعة · 10:00 ص».
  final bool kahfFriday;
  final int kahfAtMinutes;

  /// «الورد اليومي · إذا لم يكتمل قبل العشاء» — the caller passes true only while today's goal is unmet.
  final bool wirdMissing;
  final int wirdMissingBeforeIshaMinutes;

  /// Dates (local midnight) on which a hifz review is due.
  final Set<DateTime> hifzDueDates;

  /// When a due hifz review reminds (the routine's hifz time, else the morning).
  final SlotTime hifz;

  /// Daily dhikr session reminder at the user's routine time, or null.
  final SlotTime? dhikr;

  /// Quiet window in minutes since midnight (may wrap past midnight). Null = off.
  final int? quietStartMinutes;
  final int? quietEndMinutes;

  PrayerAlert modeOf(Prayer p) => modes?[p] ?? (adhan.contains(p) ? PrayerAlert.adhan : PrayerAlert.silent);

  bool inQuietHours(DateTime t) {
    final s = quietStartMinutes;
    final e = quietEndMinutes;
    if (s == null || e == null || s == e) return false;
    final m = t.hour * 60 + t.minute;
    return s < e ? (m >= s && m < e) : (m >= s || m < e);
  }
}

class PlannedNotification {
  const PlannedNotification({required this.id, required this.at, required this.kind, this.prayer, this.alert, this.minutesBefore});

  /// Stable id (same reminder → same id) so re-planning replaces instead of duplicating.
  final int id;
  final DateTime at;
  final ReminderKind kind;
  final Prayer? prayer;

  /// For prayer alerts: adhan sound vs. a plain notification.
  final PrayerAlert? alert;

  /// For pre-prayer reminders.
  final int? minutesBefore;

  NotificationChannel get channel =>
      kind == ReminderKind.adhan && alert == PrayerAlert.adhan ? NotificationChannel.adhan : NotificationChannel.reminders;

  /// Where a tap opens (spec §4.2 deep links).
  String get link => switch (kind) {
        ReminderKind.adhan || ReminderKind.prePrayer => 'yaqeen://prayer',
        ReminderKind.morningAzkar || ReminderKind.eveningAzkar => 'yaqeen://azkar',
        ReminderKind.wird || ReminderKind.wirdMissing || ReminderKind.kahfFriday => 'yaqeen://quran',
        ReminderKind.hifzDue => 'yaqeen://hifz',
        ReminderKind.dhikr => 'yaqeen://home',
      };

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
    void reminder(DateTime day, ReminderKind kind, DateTime at) {
      // Quiet hours apply to reminders only — never to a prayer alert.
      if (prefs.inQuietHours(at)) return;
      out.add(PlannedNotification(id: stableId(day, kind), at: at, kind: kind));
    }

    for (final day in days) {
      // The caller's midnight (a zoned TZDateTime in the app), so minute-of-day reminders land on
      // the place's wall clock even when the device is set to another zone.
      final d = day.date;
      for (final p in Prayer.values) {
        final t = day.times[p];
        if (t == null) continue;
        final mode = prefs.modeOf(p);
        if (mode == PrayerAlert.silent) continue;
        out.add(PlannedNotification(id: stableId(d, ReminderKind.adhan, p), at: t, kind: ReminderKind.adhan, prayer: p, alert: mode));
        final pre = prefs.prePrayerMinutes;
        if (pre != null && pre > 0 && p != Prayer.sunrise) {
          final at = t.subtract(Duration(minutes: pre));
          if (!prefs.inQuietHours(at)) {
            out.add(
              PlannedNotification(
                id: stableId(d, ReminderKind.prePrayer, p),
                at: at,
                kind: ReminderKind.prePrayer,
                prayer: p,
                minutesBefore: pre,
              ),
            );
          }
        }
      }
      final fajr = day.times[Prayer.fajr];
      final asr = day.times[Prayer.asr];
      final isha = day.times[Prayer.isha];
      if (prefs.morningAzkar && fajr != null) {
        reminder(d, ReminderKind.morningAzkar, fajr.add(Duration(minutes: prefs.morningAfterFajrMinutes)));
      }
      if (prefs.eveningAzkar && asr != null) {
        reminder(d, ReminderKind.eveningAzkar, asr.add(Duration(minutes: prefs.eveningAfterAsrMinutes)));
      }
      final wirdAt = prefs.wird?.on(day);
      if (wirdAt != null) reminder(d, ReminderKind.wird, wirdAt);
      final dhikrAt = prefs.dhikr?.on(day);
      if (dhikrAt != null) reminder(d, ReminderKind.dhikr, dhikrAt);
      if (prefs.kahfFriday && d.weekday == DateTime.friday) {
        reminder(d, ReminderKind.kahfFriday, d.add(Duration(minutes: prefs.kahfAtMinutes)));
      }
      // Only today's: tomorrow's goal is not "missing" yet; re-planned when the wird is done.
      if (prefs.wirdMissing && isha != null && d.year == now.year && d.month == now.month && d.day == now.day) {
        reminder(d, ReminderKind.wirdMissing, isha.subtract(Duration(minutes: prefs.wirdMissingBeforeIshaMinutes)));
      }
      if (prefs.hifzDueDates.any((h) => h.year == d.year && h.month == d.month && h.day == d.day)) {
        final hifzAt = prefs.hifz.on(day);
        if (hifzAt != null) reminder(d, ReminderKind.hifzDue, hifzAt);
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

/// Platform adapter (flutter_local_notifications) — see local_notifier.dart.
abstract interface class LocalNotificationScheduler {
  Future<bool> requestPermission();
  Future<void> replaceAll(List<PlannedNotification> plan);
  Future<void> cancelAll();
}

class NoopLocalNotificationScheduler implements LocalNotificationScheduler {
  List<PlannedNotification> scheduled = [];
  bool permission = true;

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async => scheduled = List.of(plan);
  @override
  Future<void> cancelAll() async => scheduled = [];
}
