import 'package:timezone/timezone.dart' as tz;

import '../../../core/format.dart';
import '../../../core/notifications/notification_planner.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/time/zoned.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../prayer/data/prayer_repository.dart';
import '../../prayer/domain/prayer_calculator.dart';
import '../domain/inbox_item.dart';
import 'inbox_repository.dart';

/// Turns settings + on-device prayer times into the local notification schedule (spec §6.5)
/// and mirrors delivered reminders into the inbox.
///
/// Re-plan on: app start, settings change, location change, wird done, hifz change, resume.
class ReminderService {
  ReminderService({required this.scheduler, required this.store, required this.inbox, this.prayers = const PrayerRepository()});

  final LocalNotificationScheduler scheduler;
  final LocalStore store;
  final InboxRepository inbox;
  final PrayerRepository prayers;

  /// Days planned ahead (iOS: the 60-item budget covers ~5 days of prayers + reminders).
  static const daysAhead = 6;

  static Prayer _prayer(PrayerName p) => switch (p) {
        PrayerName.fajr => Prayer.fajr,
        PrayerName.sunrise => Prayer.sunrise,
        PrayerName.dhuhr => Prayer.dhuhr,
        PrayerName.asr => Prayer.asr,
        PrayerName.maghrib => Prayer.maghrib,
        PrayerName.isha => Prayer.isha,
      };

  /// The routine slot as the planner's daily time (null = off).
  static SlotTime? _slot(RoutineSlot r) => switch (r.kind) {
        SlotKind.off => null,
        SlotKind.at => SlotTime.at(r.minutes),
        SlotKind.afterPrayer => SlotTime.after(_prayer(r.prayer!), r.minutes),
      };

  static PrayerAlert _alert(AlertMode m) => switch (m) {
        AlertMode.adhan => PrayerAlert.adhan,
        AlertMode.notify => PrayerAlert.notify,
        AlertMode.silent => PrayerAlert.silent,
      };

  ReminderPrefs prefsFor(
    AppSettings s, {
    required bool wirdDone,
    Set<DateTime> hifzDue = const {},
    Set<DateTime> ramadanDates = const {},
  }) =>
      ReminderPrefs(
        modes: {for (final e in s.alertModes.entries) _prayer(e.key): _alert(e.value)},
        prePrayerMinutes: s.preReminderMinutes,
        morningAzkar: s.morningAzkar,
        eveningAzkar: s.eveningAzkar,
        wird: _slot(s.quranSlot),
        dhikr: _slot(s.dhikrSlot),
        hifz: _slot(s.hifzSlot) ?? const SlotTime.at(9 * 60),
        kahfFriday: s.kahfFriday,
        wirdMissing: s.wirdMissing && !wirdDone,
        hifzDueDates: s.hifzDue ? hifzDue : const {},
        ramadanDates: ramadanDates,
        suhoorMinutes: s.suhoorReminder ? s.suhoorMinutes : null,
        iftarMinutes: s.iftarReminder ? s.iftarMinutes : null,
        quietStartMinutes: s.quietHours ? s.quietStartMinutes : null,
        quietEndMinutes: s.quietHours ? s.quietEndMinutes : null,
      );

  /// [ramadanDates]: days on which Ramadan timings apply (Umm al-Qura's later Isha).
  List<PrayerDay> daysFor(AppSettings s, DateTime now, {Set<DateTime> ramadanDates = const {}}) {
    final loc = Zoned.location(s.placeOrDefault.timezone);
    final today = prayers.today(s, now);
    final out = <PrayerDay>[];
    for (var i = 0; i < daysAhead; i++) {
      final date = DateTime(today.year, today.month, today.day + i);
      final times = prayers.forDate(s, date, ramadan: ramadanDates.contains(date));
      out.add(
        PrayerDay(tz.TZDateTime(loc, times.year, times.month, times.day), {
          for (final p in PrayerName.values) _prayer(p): tz.TZDateTime.from(times.of(p), loc),
        }),
      );
    }
    return out;
  }

  Future<NotificationPlan> replan(
    AppSettings s, {
    required DateTime now,
    required bool worshipConsent,
    bool wirdDone = false,
    Set<DateTime> hifzDue = const {},
    Set<DateTime> ramadanDates = const {},
  }) async {
    if (!worshipConsent) {
      await scheduler.cancelAll();
      await store.write('notifications.plan', []);
      return const NotificationPlan([], null);
    }
    final nowZoned = tz.TZDateTime.from(now.toUtc(), Zoned.location(s.placeOrDefault.timezone));
    final plan = NotificationPlanner.plan(
      days: daysFor(s, now, ramadanDates: ramadanDates),
      prefs: prefsFor(s, wirdDone: wirdDone, hifzDue: hifzDue, ramadanDates: ramadanDates),
      now: nowZoned,
    );
    await scheduler.replaceAll(plan.items);
    await store.write('notifications.plan', [
      for (final n in plan.items)
        {'id': n.id, 'at': n.at.toUtc().toIso8601String(), 'k': n.kind.name, 'p': n.prayer?.name, 'a': n.alert?.name, 'm': n.minutesBefore},
    ]);
    return plan;
  }

  /// Moves reminders whose time has passed into the inbox (spec §5.18: "local notifications write
  /// their entry when delivered"). Called on start and resume.
  Future<int> collectDelivered(AppSettings s, DateTime now, AppLocalizations t) async {
    final raw = (await store.readList('notifications.plan')).cast<Map<String, dynamic>>();
    final due = <InboxItem>[];
    final pending = <Map<String, dynamic>>[];
    for (final r in raw) {
      final at = DateTime.parse(r['at'] as String);
      if (at.isAfter(now)) {
        pending.add(r);
        continue;
      }
      final n = PlannedNotification(
        id: r['id'] as int,
        at: at,
        kind: ReminderKind.values.byName(r['k'] as String),
        prayer: r['p'] == null ? null : Prayer.values.byName(r['p'] as String),
        alert: r['a'] == null ? null : PrayerAlert.values.byName(r['a'] as String),
        minutesBefore: r['m'] as int?,
      );
      final (title, body) = NotificationCopy(t, s).of(n);
      due.add(InboxItem(id: 'local:${n.id}', category: InboxCategory.worship, title: title, body: body, at: at, link: n.link));
    }
    if (due.isEmpty) return 0;
    await inbox.addAll(due);
    await store.write('notifications.plan', pending);
    return due.length;
  }
}

/// Localised title/body for a planned notification. Tone: invitations, never guilt (spec §11.2).
class NotificationCopy {
  NotificationCopy(this.t, this.s);
  final AppLocalizations t;
  final AppSettings s;

  String prayerName(Prayer p, {bool friday = false}) => switch (p) {
        Prayer.fajr => t.prayerFajr,
        Prayer.sunrise => t.prayerSunrise,
        Prayer.dhuhr => friday ? t.prayerJumuah : t.prayerDhuhr,
        Prayer.asr => t.prayerAsr,
        Prayer.maghrib => t.prayerMaghrib,
        Prayer.isha => t.prayerIsha,
      };

  (String, String) of(PlannedNotification n) {
    final local = Zoned.local(n.at.toUtc(), s.placeOrDefault.timezone);
    final friday = local.weekday == DateTime.friday;
    final place = s.placeOrDefault.name(s.locale);
    return switch (n.kind) {
      ReminderKind.adhan when n.prayer == Prayer.sunrise => (t.notifSunriseTitle, t.notifAdhanBody(YqFormat.time(local, s.locale), place)),
      ReminderKind.adhan => (
          t.notifAdhanTitle(prayerName(n.prayer!, friday: friday)),
          t.notifAdhanBody(YqFormat.time(local, s.locale), place)
        ),
      ReminderKind.prePrayer => (
          t.notifPreTitle(prayerName(n.prayer!, friday: friday), n.minutesBefore ?? s.preReminderMinutes),
          t.notifPreBody(YqFormat.time(local.add(Duration(minutes: n.minutesBefore ?? 0)), s.locale)),
        ),
      ReminderKind.morningAzkar => (t.notifMorningTitle, t.notifMorningBody),
      ReminderKind.eveningAzkar => (t.notifEveningTitle, t.notifEveningBody),
      ReminderKind.wird => (t.notifWirdTitle, t.notifWirdBody),
      ReminderKind.kahfFriday => (t.notifKahfTitle, t.notifKahfBody),
      ReminderKind.wirdMissing => (t.notifWirdMissingTitle, t.notifWirdMissingBody),
      ReminderKind.hifzDue => (t.notifHifzTitle, t.notifHifzBody),
      ReminderKind.dhikr => (t.notifDhikrTitle, t.notifDhikrBody),
      ReminderKind.suhoor => (t.notifSuhoorTitle, t.notifSuhoorBody(n.minutesBefore ?? s.suhoorMinutes)),
      ReminderKind.iftar => (t.notifIftarTitle, t.notifIftarBody(n.minutesBefore ?? s.iftarMinutes)),
    };
  }
}
