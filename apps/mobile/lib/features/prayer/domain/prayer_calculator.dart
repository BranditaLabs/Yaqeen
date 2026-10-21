import 'astronomy.dart';

/// Calculation methods offered in prayer setup (spec §6.4). Wire names match the API's
/// `PrayerMethod` where it has one (`egypt`, `mwl`, `umm_al_qura`).
enum CalcMethod {
  egypt('egypt', 19.5, 17.5, dhuhrAdj: 1),
  mwl('mwl', 18, 17, dhuhrAdj: 1),
  ummAlQura('umm_al_qura', 18.5, 0, ishaInterval: 90),
  karachi('karachi', 18, 18, dhuhrAdj: 1),
  isna('isna', 15, 15, dhuhrAdj: 1),
  dubai('dubai', 18.2, 18.2, sunriseAdj: -3, dhuhrAdj: 3, asrAdj: 3, maghribAdj: 3),
  kuwait('kuwait', 18, 17.5),
  qatar('qatar', 18, 0, ishaInterval: 90),
  singapore('singapore', 20, 18, dhuhrAdj: 1, roundUp: true),
  turkey('turkey', 18, 17, sunriseAdj: -7, dhuhrAdj: 5, asrAdj: 4, maghribAdj: 7);

  const CalcMethod(
    this.wire,
    this.fajrAngle,
    this.ishaAngle, {
    this.ishaInterval = 0,
    this.sunriseAdj = 0,
    this.dhuhrAdj = 0,
    this.asrAdj = 0,
    this.maghribAdj = 0,
    this.roundUp = false,
  });

  final String wire;
  final double fajrAngle;
  final double ishaAngle;

  /// Minutes after Maghrib (Umm al-Qura, Qatar). > 0 means Isha ignores [ishaAngle].
  final int ishaInterval;
  final int sunriseAdj;
  final int dhuhrAdj;
  final int asrAdj;
  final int maghribAdj;
  final bool roundUp;

  static CalcMethod fromWire(String? s) => values.firstWhere((m) => m.wire == s, orElse: () => egypt);

  /// The method we recommend for a country (spec §5.5): EG → Egyptian, SA → Umm al-Qura, else MWL.
  static CalcMethod recommendedFor(String? iso2) => switch (iso2) {
        'EG' => egypt,
        'SA' => ummAlQura,
        'AE' => dubai,
        'KW' => kuwait,
        'QA' => qatar,
        'TR' => turkey,
        'PK' || 'IN' || 'BD' || 'AF' => karachi,
        'US' || 'CA' => isna,
        'SG' || 'MY' || 'ID' => singapore,
        _ => mwl,
      };

  /// The API only stores these three; others are kept on the device and sent as the closest one.
  String get apiWire => switch (this) { egypt => 'egypt', ummAlQura => 'umm_al_qura', _ => 'mwl' };
}

enum AsrSchool {
  standard('standard', 1),
  hanafi('hanafi', 2);

  const AsrSchool(this.wire, this.shadowLength);
  final String wire;
  final double shadowLength;

  static AsrSchool fromWire(String? s) => s == 'hanafi' ? hanafi : standard;
}

/// Bounds Fajr/Isha where twilight never ends (high latitudes). Spec default: twilight angle.
enum HighLatitudeRule { middleOfTheNight, seventhOfTheNight, twilightAngle }

enum PrayerName { fajr, sunrise, dhuhr, asr, maghrib, isha }

/// Per-prayer minute offsets (hidden advanced setting).
class PrayerAdjustments {
  const PrayerAdjustments({this.fajr = 0, this.sunrise = 0, this.dhuhr = 0, this.asr = 0, this.maghrib = 0, this.isha = 0});
  final int fajr;
  final int sunrise;
  final int dhuhr;
  final int asr;
  final int maghrib;
  final int isha;

  int of(PrayerName p) => switch (p) {
        PrayerName.fajr => fajr,
        PrayerName.sunrise => sunrise,
        PrayerName.dhuhr => dhuhr,
        PrayerName.asr => asr,
        PrayerName.maghrib => maghrib,
        PrayerName.isha => isha,
      };

  Map<String, int> toJson() => {'fajr': fajr, 'sunrise': sunrise, 'dhuhr': dhuhr, 'asr': asr, 'maghrib': maghrib, 'isha': isha};
  factory PrayerAdjustments.fromJson(Map<String, dynamic> j) => PrayerAdjustments(
        fajr: (j['fajr'] as int?) ?? 0,
        sunrise: (j['sunrise'] as int?) ?? 0,
        dhuhr: (j['dhuhr'] as int?) ?? 0,
        asr: (j['asr'] as int?) ?? 0,
        maghrib: (j['maghrib'] as int?) ?? 0,
        isha: (j['isha'] as int?) ?? 0,
      );
}

class PrayerParams {
  const PrayerParams({
    this.method = CalcMethod.egypt,
    this.asr = AsrSchool.standard,
    this.highLatitude = HighLatitudeRule.twilightAngle,
    this.adjustments = const PrayerAdjustments(),
    this.ramadan = false,
  });

  final CalcMethod method;
  final AsrSchool asr;
  final HighLatitudeRule highLatitude;
  final PrayerAdjustments adjustments;

  /// Umm al-Qura adds 30 minutes to Isha in Ramadan.
  final bool ramadan;

  int get ishaInterval => method.ishaInterval > 0 && ramadan && method == CalcMethod.ummAlQura ? method.ishaInterval + 30 : method.ishaInterval;

  (double fajr, double isha) get nightPortions => switch (highLatitude) {
        HighLatitudeRule.middleOfTheNight => (0.5, 0.5),
        HighLatitudeRule.seventhOfTheNight => (1 / 7, 1 / 7),
        HighLatitudeRule.twilightAngle => (method.fajrAngle / 60, method.ishaAngle / 60),
      };
}

/// The six times for one calendar date, as UTC instants (convert with the location's time zone).
class PrayerDayTimes {
  const PrayerDayTimes({
    required this.year,
    required this.month,
    required this.day,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final int year;
  final int month;
  final int day;
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  DateTime of(PrayerName p) => switch (p) {
        PrayerName.fajr => fajr,
        PrayerName.sunrise => sunrise,
        PrayerName.dhuhr => dhuhr,
        PrayerName.asr => asr,
        PrayerName.maghrib => maghrib,
        PrayerName.isha => isha,
      };
}

/// Spec §6.4 seam: everything (Home, Prayer, notifications) reads times through this.
abstract interface class PrayerTimesCalculator {
  PrayerDayTimes compute({required int year, required int month, required int day, required double latitude, required double longitude, required PrayerParams params});
}

/// Fully offline calculator (port of adhan-js, see astronomy.dart). Rounds to the nearest minute.
class AstronomicalPrayerCalculator implements PrayerTimesCalculator {
  const AstronomicalPrayerCalculator();

  @override
  PrayerDayTimes compute({required int year, required int month, required int day, required double latitude, required double longitude, required PrayerParams params}) {
    final m = params.method;
    final solar = SolarTime(year, month, day, latitude, longitude);
    final next = DateTime.utc(year, month, day + 1);
    final tomorrow = SolarTime(next.year, next.month, next.day, latitude, longitude);

    final dhuhr = utcFromHours(year, month, day, solar.transit);
    final sunrise = utcFromHours(year, month, day, solar.sunrise);
    final sunset = utcFromHours(year, month, day, solar.sunset);
    final asr = utcFromHours(year, month, day, solar.afternoon(params.asr.shadowLength));
    final tomorrowSunrise = utcFromHours(next.year, next.month, next.day, tomorrow.sunrise);
    final nightSeconds = tomorrowSunrise.difference(sunset).inMilliseconds / 1000;
    final (fajrPortion, ishaPortion) = params.nightPortions;

    // Fajr: the angle, unless the night is so short that it would be earlier than the portion allows.
    final fajrHours = solar.hourAngle(-m.fajrAngle, afterTransit: false);
    final safeFajr = sunrise.subtract(Duration(milliseconds: (fajrPortion * nightSeconds * 1000).round()));
    var fajr = fajrHours.isNaN ? safeFajr : utcFromHours(year, month, day, fajrHours);
    if (safeFajr.isAfter(fajr)) fajr = safeFajr;

    DateTime isha;
    if (params.ishaInterval > 0) {
      isha = sunset.add(Duration(minutes: params.ishaInterval));
    } else {
      final ishaHours = solar.hourAngle(-m.ishaAngle, afterTransit: true);
      final safeIsha = sunset.add(Duration(milliseconds: (ishaPortion * nightSeconds * 1000).round()));
      isha = ishaHours.isNaN ? safeIsha : utcFromHours(year, month, day, ishaHours);
      if (safeIsha.isBefore(isha)) isha = safeIsha;
    }

    final adj = params.adjustments;
    DateTime round(DateTime t, int minutes) => _round(t.add(Duration(minutes: minutes)), up: m.roundUp);
    return PrayerDayTimes(
      year: year,
      month: month,
      day: day,
      fajr: round(fajr, adj.fajr),
      sunrise: round(sunrise, adj.sunrise + m.sunriseAdj),
      dhuhr: round(dhuhr, adj.dhuhr + m.dhuhrAdj),
      asr: round(asr, adj.asr + m.asrAdj),
      maghrib: round(sunset, adj.maghrib + m.maghribAdj),
      isha: round(isha, adj.isha),
    );
  }

  static DateTime _round(DateTime t, {required bool up}) {
    final s = t.second;
    final offset = up ? 60 - s : (s >= 30 ? 60 - s : -s);
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second).add(Duration(seconds: offset));
  }
}
