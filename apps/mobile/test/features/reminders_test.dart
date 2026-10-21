import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/features/notifications/data/inbox_repository.dart';
import 'package:yaqeen/features/notifications/data/reminder_service.dart';
import 'package:yaqeen/features/notifications/domain/inbox_item.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(Zoned.ensureInitialized);
  final now = DateTime.utc(2026, 10, 20, 9); // 12:00 Cairo (Tuesday)
  late NoopLocalNotificationScheduler scheduler;
  late ReminderService service;
  late LocalStore store;

  setUp(() {
    scheduler = NoopLocalNotificationScheduler();
    store = LocalStore(MemoryKvStore());
    service = ReminderService(scheduler: scheduler, store: store, inbox: InboxRepository(store, now: () => now));
  });

  test('default plan: adhan for 4 prayers, notify for Isha, nothing for sunrise; within the iOS budget', () async {
    final plan = await service.replan(const AppSettings(place: Place.cairo), now: now, worshipConsent: true);
    expect(plan.items.length, lessThanOrEqualTo(NotificationPlanner.iosLimit));
    final prayers = plan.items.where((n) => n.kind == ReminderKind.adhan);
    expect(prayers.where((n) => n.prayer == Prayer.sunrise), isEmpty);
    expect(prayers.firstWhere((n) => n.prayer == Prayer.isha).alert, PrayerAlert.notify);
    expect(prayers.firstWhere((n) => n.prayer == Prayer.asr).channel, NotificationChannel.adhan);
    expect(scheduler.scheduled, plan.items);
  });

  test('times are on the place clock: Cairo Asr at 15:53 local', () async {
    final plan = await service.replan(const AppSettings(place: Place.cairo), now: now, worshipConsent: true);
    final asr = plan.items.firstWhere((n) => n.kind == ReminderKind.adhan && n.prayer == Prayer.asr);
    expect([asr.at.hour, asr.at.minute], [15, 53]);
  });

  test('quiet hours drop reminders but never a prayer alert', () async {
    // Quiet 18:00–08:00 covers Maghrib, Isha and Fajr, the wird reminder at 06:00 and morning azkar.
    const s = AppSettings(place: Place.cairo, quietStartMinutes: 18 * 60, quietEndMinutes: 8 * 60, preReminderMinutes: 10);
    final plan = await service.replan(s, now: now, worshipConsent: true);
    expect(plan.items.where((n) => n.kind == ReminderKind.adhan && n.prayer == Prayer.isha), isNotEmpty);
    expect(plan.items.where((n) => n.kind == ReminderKind.adhan && n.prayer == Prayer.fajr), isNotEmpty);
    expect(plan.items.where((n) => n.kind == ReminderKind.wird), isEmpty);
    expect(plan.items.where((n) => n.kind == ReminderKind.morningAzkar), isEmpty);
    expect(plan.items.where((n) => n.kind == ReminderKind.prePrayer && n.prayer == Prayer.isha), isEmpty);
  });

  test('Kahf on Friday at 10:00 and wird-missing only while the goal is unmet', () async {
    const s = AppSettings(place: Place.cairo, wirdMissing: true);
    final plan = await service.replan(s, now: now, worshipConsent: true);
    final kahf = plan.items.where((n) => n.kind == ReminderKind.kahfFriday).toList();
    expect(kahf.first.at.weekday, DateTime.friday);
    expect(kahf.first.at.hour, 10);
    expect(plan.items.where((n) => n.kind == ReminderKind.wirdMissing), hasLength(1));
    final done = await service.replan(s, now: now, worshipConsent: true, wirdDone: true);
    expect(done.items.where((n) => n.kind == ReminderKind.wirdMissing), isEmpty);
  });

  test('no worship consent → everything cancelled', () async {
    await service.replan(const AppSettings(), now: now, worshipConsent: true);
    await service.replan(const AppSettings(), now: now, worshipConsent: false);
    expect(scheduler.scheduled, isEmpty);
  });

  test('delivered reminders land in the inbox once, with localized copy', () async {
    const s = AppSettings(place: Place.cairo);
    await service.replan(s, now: now, worshipConsent: true);
    final t = lookupAppLocalizations(const Locale('ar'));
    final later = DateTime.utc(2026, 10, 20, 13, 5); // after Asr
    final moved = await service.collectDelivered(s, later, t);
    expect(moved, greaterThan(0));
    final inbox = await InboxRepository(store, now: () => later).all();
    expect(inbox.first.title, 'حان وقت صلاة العصر');
    expect(inbox.first.category, InboxCategory.worship);
    expect(await service.collectDelivered(s, later, t), 0);
  });

  test('inbox keeps 30 days and at most 200 items, newest first', () {
    final n = DateTime(2026, 10, 20);
    final items = [
      for (var i = 0; i < 250; i++)
        InboxItem(id: '$i', category: InboxCategory.worship, title: 't', body: 'b', at: n.subtract(Duration(hours: i))),
      InboxItem(id: 'old', category: InboxCategory.offers, title: 't', body: 'b', at: n.subtract(const Duration(days: 40))),
    ];
    final kept = pruneInbox(items, n);
    expect(kept, hasLength(200));
    expect(kept.first.id, '0');
    expect(kept.any((i) => i.id == 'old'), isFalse);
  });

  test('prayer alerts map from settings modes', () {
    final p = service.prefsFor(
      AppSettings(alertModes: Map.of(AppSettings.defaultAlertModes)..[PrayerName.fajr] = AlertMode.silent),
      wirdDone: false,
    );
    expect(p.modeOf(Prayer.fajr), PrayerAlert.silent);
    expect(p.modeOf(Prayer.dhuhr), PrayerAlert.adhan);
  });
}
