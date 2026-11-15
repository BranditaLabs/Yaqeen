import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/home/home_screen.dart';
import 'package:yaqeen/features/prayer/data/prayer_repository.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/routine/domain/routine.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(Zoned.ensureInitialized);

  group('routine slot', () {
    const s = AppSettings(place: Place.cairo);
    final times = const PrayerRepository().forDate(s, DateTime(2026, 10, 20));

    test('after a prayer = that prayer + minutes; a set time = local wall clock; off = none', () {
      final afterMaghrib = resolveSlot(const RoutineSlot.afterPrayer(PrayerName.maghrib, 15), times, 'Africa/Cairo');
      expect(afterMaghrib, times.maghrib.add(const Duration(minutes: 15)));
      // 21:30 Cairo (UTC+3 in October 2026) = 18:30 UTC.
      expect(resolveSlot(const RoutineSlot.at(21 * 60 + 30), times, 'Africa/Cairo'), DateTime.utc(2026, 10, 20, 18, 30));
      expect(resolveSlot(RoutineSlot.off, times, 'Africa/Cairo'), isNull);
    });

    test('settings round-trip; a legacy fixed wird time is kept; unreadable falls back', () {
      const custom = AppSettings(
        quranSlot: RoutineSlot.at(5 * 60),
        hifzSlot: RoutineSlot.afterPrayer(PrayerName.isha, 20),
        dhikrSlot: RoutineSlot.off,
      );
      final back = AppSettings.fromJson(jsonDecode(jsonEncode(custom.toJson())) as Map<String, dynamic>);
      expect(back.quranSlot, custom.quranSlot);
      expect(back.hifzSlot, custom.hifzSlot);
      expect(back.dhikrSlot, RoutineSlot.off);

      expect(AppSettings.fromJson({'wirdReminderMinutes': 21 * 60}).quranSlot, const RoutineSlot.at(21 * 60));
      expect(AppSettings.fromJson({'wirdReminderMinutes': 6 * 60}).quranSlot, AppSettings.defaultQuranSlot);
      final unreadable = AppSettings.fromJson({
        'quranSlot': {'k': 'after', 'p': 'nope'},
      });
      expect(unreadable.quranSlot, AppSettings.defaultQuranSlot);
    });

    test('the routine never syncs to the server', () {
      final patch = const AppSettings(dhikrSlot: RoutineSlot.at(60)).serverPatch();
      expect(patch.keys.where((k) => k.contains('Slot') || k.contains('wird')), isEmpty);
    });
  });

  group('planner follows the routine', () {
    PrayerDay day(DateTime d) => PrayerDay(d, {
          Prayer.fajr: DateTime(d.year, d.month, d.day, 4, 30),
          Prayer.dhuhr: DateTime(d.year, d.month, d.day, 11, 40),
          Prayer.asr: DateTime(d.year, d.month, d.day, 14, 50),
          Prayer.maghrib: DateTime(d.year, d.month, d.day, 17, 15),
          Prayer.isha: DateTime(d.year, d.month, d.day, 18, 35),
        });
    final now = DateTime(2026, 10, 20, 12);
    List<PlannedNotification> plan(ReminderPrefs p) =>
        NotificationPlanner.plan(days: [day(DateTime(2026, 10, 20))], prefs: p, now: now).items;

    test('wird after Maghrib, dhikr at a set time, both off', () {
      final items = plan(const ReminderPrefs(wird: SlotTime.after(Prayer.maghrib, 15), dhikr: SlotTime.at(21 * 60)));
      expect(items.firstWhere((n) => n.kind == ReminderKind.wird).at, DateTime(2026, 10, 20, 17, 30));
      expect(items.firstWhere((n) => n.kind == ReminderKind.dhikr).at, DateTime(2026, 10, 20, 21));
      final none = plan(const ReminderPrefs());
      expect(none.where((n) => n.kind == ReminderKind.wird || n.kind == ReminderKind.dhikr), isEmpty);
    });

    test('quiet hours silence routine reminders', () {
      final items = plan(const ReminderPrefs(dhikr: SlotTime.at(22 * 60), quietStartMinutes: 21 * 60, quietEndMinutes: 5 * 60));
      expect(items.where((n) => n.kind == ReminderKind.dhikr), isEmpty);
    });
  });

  testWidgets('«Your day» places the routine at its times, in order', (tester) async {
    await loadAppFonts();
    YqGlassConfig.enableBlur = false;
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final q = QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: HomeScreen()),
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 12)), // 15:00 Cairo
          initialSettingsProvider.overrideWithValue(
            const AppSettings(
              place: Place.cairo,
              quranSlot: RoutineSlot.afterPrayer(PrayerName.maghrib, 15),
              dhikrSlot: RoutineSlot.afterPrayer(PrayerName.dhuhr, 15),
            ),
          ),
          quranDataProvider.overrideWith((_) async => q),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    double y(String text) => tester.getTopLeft(find.text(text).last).dy;
    // Dhikr 15 min after Dhuhr (12:56) is due from then until the next prayer (Asr 15:53): at 15:00 it is.
    expect(find.text('ورد الذكر'), findsOneWidget);
    expect(find.text('حان وقته'), findsOneWidget);
    expect(y('ورد الذكر'), lessThan(y('الآن')));
    // Quran after Maghrib sits between Maghrib and Isha.
    expect(y('وردك من القرآن'), greaterThan(y('المغرب')));
    expect(y('وردك من القرآن'), lessThan(y('العشاء')));
    await tester.pumpWidget(const SizedBox());
  });
}
