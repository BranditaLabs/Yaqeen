import 'prayer_calculator.dart';

/// The five obligatory prayers in order (sunrise is shown but never "next prayer").
const obligatory = [PrayerName.fajr, PrayerName.dhuhr, PrayerName.asr, PrayerName.maghrib, PrayerName.isha];

/// Display order on the prayer screen.
const displayOrder = [PrayerName.fajr, PrayerName.sunrise, PrayerName.dhuhr, PrayerName.asr, PrayerName.maghrib, PrayerName.isha];

/// What Home's hero shows right now (spec §5.9).
class PrayerMoment {
  const PrayerMoment({required this.next, required this.at, this.current, this.currentAt});

  /// The upcoming prayer and its instant (UTC).
  final PrayerName next;
  final DateTime at;

  /// Set during the 20 minutes after a prayer's time: «حان وقت صلاة …».
  final PrayerName? current;
  final DateTime? currentAt;

  bool get isPrayerTime => current != null;
}

abstract final class PrayerClock {
  static const adhanWindow = Duration(minutes: 20);

  /// [today] and [tomorrow] are the place's calendar days; [now] any instant.
  static PrayerMoment moment(PrayerDayTimes today, PrayerDayTimes tomorrow, DateTime now) {
    final instant = now.toUtc();
    PrayerName? current;
    DateTime? currentAt;
    for (final p in obligatory) {
      final t = today.of(p);
      if (!instant.isBefore(t) && instant.isBefore(t.add(adhanWindow))) {
        current = p;
        currentAt = t;
      }
    }
    for (final p in obligatory) {
      final t = today.of(p);
      if (t.isAfter(instant)) return PrayerMoment(next: p, at: t, current: current, currentAt: currentAt);
    }
    return PrayerMoment(next: PrayerName.fajr, at: tomorrow.fajr, current: current, currentAt: currentAt);
  }
}
