import 'package:timezone/timezone.dart' as tz;

import '../../../core/settings/app_settings.dart';
import '../../../core/time/zoned.dart';
import '../domain/prayer_calculator.dart';
import '../domain/prayer_clock.dart';

/// Prayer times for the user's place, computed on-device for any date (spec §6.4). Never cached
/// on the server; the only inputs are the device's own settings.
class PrayerRepository {
  const PrayerRepository([this.calculator = const AstronomicalPrayerCalculator()]);

  final PrayerTimesCalculator calculator;

  /// Times for a calendar date at [place] (y/m/d are the place's local date).
  PrayerDayTimes forDate(AppSettings s, DateTime localDate, {bool ramadan = false}) {
    final p = s.placeOrDefault;
    return calculator.compute(
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
      latitude: p.lat,
      longitude: p.lng,
      params: s.prayerParams(ramadan: ramadan),
    );
  }

  /// The place's "today" for [now].
  DateTime today(AppSettings s, DateTime now) => Zoned.today(s.placeOrDefault.timezone, now);

  List<PrayerDayTimes> range(AppSettings s, DateTime fromLocalDate, int days, {bool ramadan = false}) => [
        for (var i = 0; i < days; i++)
          forDate(s, DateTime(fromLocalDate.year, fromLocalDate.month, fromLocalDate.day + i), ramadan: ramadan),
      ];

  PrayerMoment moment(AppSettings s, DateTime now, {bool ramadan = false}) {
    final d = today(s, now);
    return PrayerClock.moment(forDate(s, d, ramadan: ramadan), forDate(s, DateTime(d.year, d.month, d.day + 1), ramadan: ramadan), now);
  }

  /// Wall-clock time of a prayer instant in the place's zone.
  tz.TZDateTime local(AppSettings s, DateTime utc) => Zoned.local(utc, s.placeOrDefault.timezone);
}
