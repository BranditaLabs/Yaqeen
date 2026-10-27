import '../../calendar/domain/hijri_day.dart';
import '../../prayer/domain/prayer_calculator.dart';

/// Ramadan mode (spec §5.27): the imsakiyya, the fasting clock and the month's tracker. Shown only
/// while the admin flag `ramadan` is on and the (Egypt-adjusted) Hijri month is Ramadan — or
/// Sha'ban, as a countdown. Everything here is computed on the device.
const ramadanMonth = 9;
const shabanMonth = 8;

/// Imsak: the customary caution before Fajr printed on Egyptian imsakiyyas. Eating is permitted
/// until Fajr itself; the app shows both and never calls imsak the deadline.
const imsakMinutes = 10;

/// Where the user is in the month right now.
enum RamadanPhase { none, approaching, active }

class RamadanStatus {
  const RamadanStatus._(this.phase, {this.hijriDay = 0, this.hijriYear = 0, this.daysUntil});

  const RamadanStatus.none() : this._(RamadanPhase.none);

  /// [today] is the Hijri date of the place's today; [flag] the admin's `ramadan` switch.
  /// [daysUntil] (Sha'ban only) comes from the calendar when the first of Ramadan is known.
  factory RamadanStatus.of(HijriDay? today, {required bool flag, int? daysUntil}) {
    if (!flag || today == null) return const RamadanStatus.none();
    if (today.hijriMonth == ramadanMonth) {
      return RamadanStatus._(RamadanPhase.active, hijriDay: today.hijriDay, hijriYear: today.hijriYear);
    }
    if (today.hijriMonth == shabanMonth) {
      return RamadanStatus._(RamadanPhase.approaching, hijriDay: today.hijriDay, hijriYear: today.hijriYear, daysUntil: daysUntil);
    }
    return const RamadanStatus.none();
  }

  final RamadanPhase phase;

  /// Today's Hijri day (of Ramadan when active, of Sha'ban when approaching).
  final int hijriDay;
  final int hijriYear;
  final int? daysUntil;

  bool get active => phase == RamadanPhase.active;
  bool get visible => phase != RamadanPhase.none;

  /// The Hijri year whose Ramadan is shown (Sha'ban and Ramadan share it).
  int get ramadanYear => hijriYear;
}

/// One row of the imsakiyya: the Gregorian date (place's local midnight) of a Ramadan day.
class RamadanDay {
  const RamadanDay({required this.hijriDay, required this.hijriYear, required this.date, required this.weekday});

  final int hijriDay;
  final int hijriYear;
  final DateTime date;
  final int weekday; // 0 = Sunday, as the API sends it

  /// Ramadan of [hijriYear] from any run of calendar days (duplicates and other months ignored),
  /// in order. Empty when the calendar doesn't reach it yet.
  static List<RamadanDay> from(Iterable<HijriDay> days, int hijriYear) {
    final byDay = <int, RamadanDay>{};
    for (final d in days) {
      if (d.hijriMonth != ramadanMonth || d.hijriYear != hijriYear) continue;
      final p = d.gregorian.split('-').map(int.parse).toList();
      byDay[d.hijriDay] = RamadanDay(hijriDay: d.hijriDay, hijriYear: d.hijriYear, date: DateTime(p[0], p[1], p[2]), weekday: d.weekday);
    }
    return (byDay.values.toList()..sort((a, b) => a.hijriDay.compareTo(b.hijriDay)));
  }
}

/// The fasting clock on a Ramadan day.
enum FastPhase {
  /// Night before Fajr: suhoor time, counting down to Fajr.
  suhoor,

  /// Fajr → Maghrib: fasting, counting down to iftar.
  fasting,

  /// After Maghrib: iftar has come; counting down to tomorrow's Fajr when tomorrow is Ramadan too.
  evening,
}

class FastMoment {
  const FastMoment(this.phase, this.target, {required this.imsak, required this.progress});

  final FastPhase phase;

  /// Fajr (suhoor / evening) or Maghrib (fasting). Null in the last evening of the month.
  final DateTime? target;

  /// Fajr − [imsakMinutes] of the upcoming Fajr (null when [target] is not a Fajr).
  final DateTime? imsak;

  /// 0–1 through today's fast (0 before Fajr, 1 after Maghrib) — the liquid orb's level.
  final double progress;

  /// [today] / [tomorrow] are the place's prayer days; [tomorrowIsRamadan] false on the last day.
  static FastMoment at({
    required PrayerDayTimes today,
    required PrayerDayTimes tomorrow,
    required DateTime now,
    bool tomorrowIsRamadan = true,
  }) {
    final t = now.toUtc();
    if (t.isBefore(today.fajr)) {
      return FastMoment(FastPhase.suhoor, today.fajr, imsak: today.fajr.subtract(const Duration(minutes: imsakMinutes)), progress: 0);
    }
    if (t.isBefore(today.maghrib)) {
      final span = today.maghrib.difference(today.fajr).inSeconds;
      final done = t.difference(today.fajr).inSeconds;
      return FastMoment(FastPhase.fasting, today.maghrib, imsak: null, progress: span <= 0 ? 0 : (done / span).clamp(0.0, 1.0));
    }
    return FastMoment(
      FastPhase.evening,
      tomorrowIsRamadan ? tomorrow.fajr : null,
      imsak: tomorrowIsRamadan ? tomorrow.fajr.subtract(const Duration(minutes: imsakMinutes)) : null,
      progress: 1,
    );
  }
}

/// The month's personal tracker — on this device only (worship data never leaves it, spec §6.13).
class RamadanLog {
  const RamadanLog({this.fasted = const {}, this.taraweeh = const {}, this.juz = const {}});

  /// Hijri days of Ramadan fasted / prayed taraweeh.
  final Set<int> fasted;
  final Set<int> taraweeh;

  /// Juz (1–30) read towards this Ramadan's khatma.
  final Set<int> juz;

  static const juzCount = 30;

  double get khatmaProgress => juz.length / juzCount;
  bool get khatmaDone => juz.length >= juzCount;

  /// The juz to read next (lowest not yet read), or null when the khatma is complete.
  int? get nextJuz {
    for (var j = 1; j <= juzCount; j++) {
      if (!juz.contains(j)) return j;
    }
    return null;
  }

  RamadanLog toggle(RamadanTrack track, int value) {
    Set<int> flip(Set<int> s) => s.contains(value) ? ({...s}..remove(value)) : {...s, value};
    return switch (track) {
      RamadanTrack.fast => RamadanLog(fasted: flip(fasted), taraweeh: taraweeh, juz: juz),
      RamadanTrack.taraweeh => RamadanLog(fasted: fasted, taraweeh: flip(taraweeh), juz: juz),
      RamadanTrack.juz => RamadanLog(fasted: fasted, taraweeh: taraweeh, juz: flip(juz)),
    };
  }

  bool has(RamadanTrack track, int value) => switch (track) {
        RamadanTrack.fast => fasted.contains(value),
        RamadanTrack.taraweeh => taraweeh.contains(value),
        RamadanTrack.juz => juz.contains(value),
      };

  Map<String, dynamic> toJson() => {'fasted': fasted.toList()..sort(), 'taraweeh': taraweeh.toList()..sort(), 'juz': juz.toList()..sort()};

  factory RamadanLog.fromJson(Map<String, dynamic> j) {
    Set<int> ints(String k, int max) => {
          for (final v in (j[k] as List? ?? const []))
            if (v is int && v >= 1 && v <= max) v,
        };
    return RamadanLog(fasted: ints('fasted', 30), taraweeh: ints('taraweeh', 30), juz: ints('juz', juzCount));
  }
}

enum RamadanTrack {
  fast('ramadan_fast'),
  taraweeh('taraweeh'),
  juz('ramadan_juz');

  const RamadanTrack(this.bonusWire);

  /// The server bonus this tick may claim (when the admin enabled it).
  final String bonusWire;
}
