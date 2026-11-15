import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/calendar/domain/hijri_day.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';
import 'package:yaqeen/features/ramadan/data/ramadan_repository.dart';
import 'package:yaqeen/features/ramadan/domain/ramadan.dart';
import 'package:yaqeen/features/ramadan/presentation/ramadan_controller.dart';
import 'package:yaqeen/features/calendar/data/calendar_repository.dart';
import 'package:yaqeen/core/network/api_client.dart';

HijriDay h(String g, int d, int m, {int y = 1448, int weekday = 1}) =>
    HijriDay(gregorian: g, hijriDay: d, hijriMonth: m, hijriYear: y, monthNameAr: 'رمضان', weekday: weekday);

PrayerDayTimes times(int y, int m, int d) => PrayerDayTimes(
      year: y,
      month: m,
      day: d,
      // Cairo in February, as UTC instants.
      fajr: DateTime.utc(y, m, d, 3, 10),
      sunrise: DateTime.utc(y, m, d, 4, 35),
      dhuhr: DateTime.utc(y, m, d, 10, 5),
      asr: DateTime.utc(y, m, d, 13, 10),
      maghrib: DateTime.utc(y, m, d, 15, 40),
      isha: DateTime.utc(y, m, d, 17, 0),
    );

void main() {
  group('status', () {
    test('needs the admin flag; Ramadan is active, Sha\'ban approaches, other months hide', () {
      expect(RamadanStatus.of(h('2027-02-12', 5, 9), flag: false).visible, isFalse);
      final on = RamadanStatus.of(h('2027-02-12', 5, 9), flag: true);
      expect(on.active, isTrue);
      expect(on.hijriDay, 5);
      expect(on.ramadanYear, 1448);
      expect(RamadanStatus.of(h('2027-01-30', 21, 8), flag: true).phase, RamadanPhase.approaching);
      expect(RamadanStatus.of(h('2027-03-12', 3, 10), flag: true).visible, isFalse);
      expect(RamadanStatus.of(null, flag: true).visible, isFalse);
    });
  });

  test('imsakiyya days: only that Ramadan, ordered, de-duplicated', () {
    final days = RamadanDay.from(
      [
        h('2027-02-09', 2, 9),
        h('2027-02-08', 1, 9),
        h('2027-02-07', 30, 8),
        h('2027-02-09', 2, 9), // overlapping month fetches
        h('2028-01-29', 1, 9, y: 1449),
      ],
      1448,
    );
    expect(days.map((d) => d.hijriDay), [1, 2]);
    expect(days.first.date, DateTime(2027, 2, 8));
  });

  group('fasting clock', () {
    final today = times(2027, 2, 12);
    final tomorrow = times(2027, 2, 13);
    test('before Fajr: suhoor, to Fajr, with imsak 10 minutes earlier', () {
      final m = FastMoment.at(today: today, tomorrow: tomorrow, now: DateTime.utc(2027, 2, 12, 2));
      expect(m.phase, FastPhase.suhoor);
      expect(m.target, today.fajr);
      expect(m.imsak, today.fajr.subtract(const Duration(minutes: 10)));
      expect(m.progress, 0);
    });
    test('during the day: fasting, to Maghrib, filling', () {
      final m = FastMoment.at(today: today, tomorrow: tomorrow, now: DateTime.utc(2027, 2, 12, 9, 25));
      expect(m.phase, FastPhase.fasting);
      expect(m.target, today.maghrib);
      expect(m.progress, closeTo(0.5, 0.01));
    });
    test('after Maghrib: evening, to tomorrow\'s Fajr — or nothing on the last night', () {
      final m = FastMoment.at(today: today, tomorrow: tomorrow, now: DateTime.utc(2027, 2, 12, 18));
      expect(m.phase, FastPhase.evening);
      expect(m.target, tomorrow.fajr);
      final last = FastMoment.at(today: today, tomorrow: tomorrow, now: DateTime.utc(2027, 2, 12, 18), tomorrowIsRamadan: false);
      expect(last.target, isNull);
    });
  });

  group('log', () {
    test('toggles, next juz, khatma, and survives a round-trip (rejecting junk)', () {
      var log = const RamadanLog();
      log = log.toggle(RamadanTrack.fast, 5).toggle(RamadanTrack.taraweeh, 5).toggle(RamadanTrack.juz, 1);
      expect(log.has(RamadanTrack.fast, 5), isTrue);
      expect(log.nextJuz, 2);
      log = log.toggle(RamadanTrack.fast, 5);
      expect(log.fasted, isEmpty);
      for (var j = 1; j <= 30; j++) {
        if (!log.juz.contains(j)) log = log.toggle(RamadanTrack.juz, j);
      }
      expect(log.khatmaDone, isTrue);
      expect(log.nextJuz, isNull);
      final back = RamadanLog.fromJson({
        ...log.toJson(),
        'fasted': [3, 'x', 99, -1],
      });
      expect(back.juz.length, 30);
      expect(back.fasted, {3});
    });

    test('is stored per Hijri year on the device', () async {
      final kv = MemoryKvStore();
      final api = ApiClient(baseUrl: 'http://localhost', tokens: TokenStore(kv));
      final repo = RamadanRepository(calendar: CalendarRepository(api: api, cache: kv), store: kv);
      await repo.save(1448, const RamadanLog(fasted: {1, 2}));
      expect((await repo.log(1448)).fasted, {1, 2});
      expect((await repo.log(1449)).fasted, isEmpty);
    });
  });

  test('bonus points only when bonuses and that bonus are on', () {
    const off = RemoteConfig(bonusPoints: {'ramadan_fast': 30});
    expect(bonusPointsFor(off, RamadanTrack.fast), isNull);
    final on = RemoteConfig.fromJson({
      'features': {'bonuses': true},
      'points': {
        'bonuses': [
          {'kind': 'ramadan_fast', 'points': 30},
          {'kind': 'bad'},
        ],
      },
    });
    expect(on.bonusPoints, {'ramadan_fast': 30});
    expect(bonusPointsFor(on, RamadanTrack.fast), 30);
    expect(bonusPointsFor(on, RamadanTrack.taraweeh), isNull);
  });

  group('reminders', () {
    PrayerDay day(DateTime d) => PrayerDay(d, {
          Prayer.fajr: DateTime(d.year, d.month, d.day, 5, 10),
          Prayer.dhuhr: DateTime(d.year, d.month, d.day, 12, 5),
          Prayer.asr: DateTime(d.year, d.month, d.day, 15, 10),
          Prayer.maghrib: DateTime(d.year, d.month, d.day, 17, 40),
          Prayer.isha: DateTime(d.year, d.month, d.day, 19, 0),
        });
    final now = DateTime(2027, 2, 12, 0, 30);
    final days = [day(DateTime(2027, 2, 12)), day(DateTime(2027, 2, 13))];

    test('suhoor and iftar only on Ramadan days; suhoor ignores quiet hours', () {
      final plan = NotificationPlanner.plan(
        days: days,
        prefs: ReminderPrefs(
          ramadanDates: {DateTime(2027, 2, 12)},
          suhoorMinutes: 45,
          iftarMinutes: 15,
          quietStartMinutes: 21 * 60,
          quietEndMinutes: 6 * 60,
        ),
        now: now,
      );
      final suhoor = plan.items.where((n) => n.kind == ReminderKind.suhoor).toList();
      final iftar = plan.items.where((n) => n.kind == ReminderKind.iftar).toList();
      expect(suhoor.map((n) => n.at), [DateTime(2027, 2, 12, 4, 25)]);
      expect(iftar.map((n) => n.at), [DateTime(2027, 2, 12, 17, 25)]);
      expect(suhoor.single.link, 'yaqeen://ramadan');
      expect(plan.items.map((e) => e.id).toSet().length, plan.items.length);
    });

    test('off when the user turns them off', () {
      final plan = NotificationPlanner.plan(days: days, prefs: ReminderPrefs(ramadanDates: {DateTime(2027, 2, 12)}), now: now);
      expect(plan.items.where((n) => n.kind == ReminderKind.suhoor || n.kind == ReminderKind.iftar), isEmpty);
    });

    test('ids stay unique across days for every kind', () {
      final ids = <int>{};
      for (var d = 1; d <= 31; d++) {
        for (final k in ReminderKind.values) {
          for (final p in [...Prayer.values, null]) {
            expect(ids.add(NotificationPlanner.stableId(DateTime(2027, 3, d), k, p)), isTrue);
          }
        }
      }
      expect(ids.every((id) => id < 0x7fffffff), isTrue);
    });
  });
}
