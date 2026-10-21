import 'dart:math' as math;

/// Solar astronomy for prayer times — a line-for-line port of the `adhan` library (MIT,
/// batoulapps/adhan-js 4.4.6, the same code the API uses for its marketing guardrails),
/// itself from Jean Meeus, *Astronomical Algorithms*. Pure Dart, no I/O.

double degToRad(double d) => d * math.pi / 180.0;
double radToDeg(double r) => r * 180.0 / math.pi;
double normalizeToScale(double n, double max) => n - max * (n / max).floorToDouble();
double unwindAngle(double a) => normalizeToScale(a, 360.0);
double quadrantShiftAngle(double a) => (a >= -180 && a <= 180) ? a : a - 360 * (a / 360).roundToDouble();

abstract final class Astronomical {
  static double meanSolarLongitude(double t) => unwindAngle(280.4664567 + 36000.76983 * t + 0.0003032 * t * t);

  static double meanLunarLongitude(double t) => unwindAngle(218.3165 + 481267.8813 * t);

  static double ascendingLunarNodeLongitude(double t) =>
      unwindAngle(125.04452 - 1934.136261 * t + 0.0020708 * t * t + t * t * t / 450000);

  static double meanSolarAnomaly(double t) => unwindAngle(357.52911 + 35999.05029 * t - 0.0001537 * t * t);

  static double solarEquationOfTheCenter(double t, double meanAnomaly) {
    final m = degToRad(meanAnomaly);
    return (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(m) +
        (0.019993 - 0.000101 * t) * math.sin(2 * m) +
        0.000289 * math.sin(3 * m);
  }

  static double apparentSolarLongitude(double t, double meanLongitude) {
    final longitude = meanLongitude + solarEquationOfTheCenter(t, meanSolarAnomaly(t));
    final omega = 125.04 - 1934.136 * t;
    return unwindAngle(longitude - 0.00569 - 0.00478 * math.sin(degToRad(omega)));
  }

  static double meanObliquityOfTheEcliptic(double t) =>
      23.439291 - 0.013004167 * t - 0.0000001639 * t * t + 0.0000005036 * t * t * t;

  static double apparentObliquityOfTheEcliptic(double t, double meanObliquity) =>
      meanObliquity + 0.00256 * math.cos(degToRad(125.04 - 1934.136 * t));

  static double meanSiderealTime(double t) {
    final jd = t * 36525 + 2451545.0;
    return unwindAngle(280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * t * t - t * t * t / 38710000);
  }

  static double nutationInLongitude(double l0, double lp, double omega) =>
      -17.2 / 3600 * math.sin(degToRad(omega)) -
      1.32 / 3600 * math.sin(2 * degToRad(l0)) -
      0.23 / 3600 * math.sin(2 * degToRad(lp)) +
      0.21 / 3600 * math.sin(2 * degToRad(omega));

  static double nutationInObliquity(double l0, double lp, double omega) =>
      9.2 / 3600 * math.cos(degToRad(omega)) +
      0.57 / 3600 * math.cos(2 * degToRad(l0)) +
      0.1 / 3600 * math.cos(2 * degToRad(lp)) -
      0.09 / 3600 * math.cos(2 * degToRad(omega));

  static double altitudeOfCelestialBody(double latitude, double declination, double hourAngle) => radToDeg(
        math.asin(
          math.sin(degToRad(latitude)) * math.sin(degToRad(declination)) +
              math.cos(degToRad(latitude)) * math.cos(degToRad(declination)) * math.cos(degToRad(hourAngle)),
        ),
      );

  static double approximateTransit(double longitude, double siderealTime, double rightAscension) {
    final lw = -longitude;
    final m0 = normalizeToScale((rightAscension + lw - siderealTime) / 360, 1);
    // Near the date line m0 can land on the wrong day; compare with the longitude-based transit.
    final expected = normalizeToScale((12.0 - longitude / 15.0) / 24.0, 1);
    if (m0 - expected > 0.5) return m0 - 1.0;
    if (expected - m0 > 0.5) return m0 + 1.0;
    return m0;
  }

  /// Solar noon in UT hours.
  static double correctedTransit(double m0, double longitude, double siderealTime, double ra, double prevRa, double nextRa) {
    final lw = -longitude;
    final theta = unwindAngle(siderealTime + 360.985647 * m0);
    final a = unwindAngle(interpolateAngles(ra, prevRa, nextRa, m0));
    final h = quadrantShiftAngle(theta - lw - a);
    return (m0 + h / -360) * 24;
  }

  /// UT hours when the sun is at altitude [angle] before (or after) transit; NaN when it never is.
  static double correctedHourAngle({
    required double m0,
    required double angle,
    required double latitude,
    required double longitude,
    required bool afterTransit,
    required double siderealTime,
    required double ra,
    required double prevRa,
    required double nextRa,
    required double decl,
    required double prevDecl,
    required double nextDecl,
  }) {
    final lw = -longitude;
    final term1 = math.sin(degToRad(angle)) - math.sin(degToRad(latitude)) * math.sin(degToRad(decl));
    final term2 = math.cos(degToRad(latitude)) * math.cos(degToRad(decl));
    final h0 = radToDeg(math.acos(term1 / term2));
    final m = afterTransit ? m0 + h0 / 360 : m0 - h0 / 360;
    final theta = unwindAngle(siderealTime + 360.985647 * m);
    final a = unwindAngle(interpolateAngles(ra, prevRa, nextRa, m));
    final delta = interpolate(decl, prevDecl, nextDecl, m);
    final h = theta - lw - a;
    final alt = altitudeOfCelestialBody(latitude, delta, h);
    final dm = (alt - angle) / (360 * math.cos(degToRad(delta)) * math.cos(degToRad(latitude)) * math.sin(degToRad(h)));
    return (m + dm) * 24;
  }

  static double interpolate(double y2, double y1, double y3, double n) {
    final a = y2 - y1;
    final b = y3 - y2;
    return y2 + n / 2 * (a + b + n * (b - a));
  }

  static double interpolateAngles(double y2, double y1, double y3, double n) {
    final a = unwindAngle(y2 - y1);
    final b = unwindAngle(y3 - y2);
    return y2 + n / 2 * (a + b + n * (b - a));
  }

  static double julianDay(int year, int month, int day, [double hours = 0]) {
    final y = month > 2 ? year : year - 1;
    final m = month > 2 ? month : month + 12;
    final d = day + hours / 24;
    final a = (y / 100).truncate();
    final b = (2 - a + (a / 4).truncate()).truncate();
    final i0 = (365.25 * (y + 4716)).truncate();
    final i1 = (30.6001 * (m + 1)).truncate();
    return i0 + i1 + d + b - 1524.5;
  }

  static double julianCentury(double jd) => (jd - 2451545.0) / 36525;
}

class SolarCoordinates {
  factory SolarCoordinates(double julianDay) {
    final t = Astronomical.julianCentury(julianDay);
    final l0 = Astronomical.meanSolarLongitude(t);
    final lp = Astronomical.meanLunarLongitude(t);
    final omega = Astronomical.ascendingLunarNodeLongitude(t);
    final lambda = degToRad(Astronomical.apparentSolarLongitude(t, l0));
    final theta0 = Astronomical.meanSiderealTime(t);
    final dPsi = Astronomical.nutationInLongitude(l0, lp, omega);
    final dEpsilon = Astronomical.nutationInObliquity(l0, lp, omega);
    final epsilon0 = Astronomical.meanObliquityOfTheEcliptic(t);
    final epsilonApparent = degToRad(Astronomical.apparentObliquityOfTheEcliptic(t, epsilon0));
    return SolarCoordinates._(
      declination: radToDeg(math.asin(math.sin(epsilonApparent) * math.sin(lambda))),
      rightAscension: unwindAngle(radToDeg(math.atan2(math.cos(epsilonApparent) * math.sin(lambda), math.cos(lambda)))),
      apparentSiderealTime: theta0 + dPsi * 3600 * math.cos(degToRad(epsilon0 + dEpsilon)) / 3600,
    );
  }

  const SolarCoordinates._({required this.declination, required this.rightAscension, required this.apparentSiderealTime});

  final double declination;
  final double rightAscension;
  final double apparentSiderealTime;
}

/// Transit, sunrise, sunset and arbitrary sun-altitude times for one calendar date (UT hours).
class SolarTime {
  factory SolarTime(int year, int month, int day, double latitude, double longitude) {
    final jd = Astronomical.julianDay(year, month, day);
    final solar = SolarCoordinates(jd);
    final prev = SolarCoordinates(jd - 1);
    final next = SolarCoordinates(jd + 1);
    final m0 = Astronomical.approximateTransit(longitude, solar.apparentSiderealTime, solar.rightAscension);
    final st = SolarTime._(latitude, longitude, solar, prev, next, m0);
    st.transit = Astronomical.correctedTransit(m0, longitude, solar.apparentSiderealTime, solar.rightAscension, prev.rightAscension, next.rightAscension);
    st.sunrise = st.hourAngle(-50.0 / 60.0, afterTransit: false);
    st.sunset = st.hourAngle(-50.0 / 60.0, afterTransit: true);
    return st;
  }

  SolarTime._(this.latitude, this.longitude, this.solar, this.prev, this.next, this.approxTransit);

  final double latitude;
  final double longitude;
  final SolarCoordinates solar;
  final SolarCoordinates prev;
  final SolarCoordinates next;
  final double approxTransit;
  late final double transit;
  late final double sunrise;
  late final double sunset;

  double hourAngle(double angle, {required bool afterTransit}) => Astronomical.correctedHourAngle(
        m0: approxTransit,
        angle: angle,
        latitude: latitude,
        longitude: longitude,
        afterTransit: afterTransit,
        siderealTime: solar.apparentSiderealTime,
        ra: solar.rightAscension,
        prevRa: prev.rightAscension,
        nextRa: next.rightAscension,
        decl: solar.declination,
        prevDecl: prev.declination,
        nextDecl: next.declination,
      );

  /// Asr: shadow = [shadowLength] × object height + noon shadow.
  double afternoon(double shadowLength) {
    final tangent = (latitude - solar.declination).abs();
    final inverse = shadowLength + math.tan(degToRad(tangent));
    return hourAngle(radToDeg(math.atan(1.0 / inverse)), afterTransit: true);
  }
}

/// UT hours (may be negative or ≥ 24) on a calendar date → UTC instant, as adhan's TimeComponents.
DateTime utcFromHours(int year, int month, int day, double hours) {
  final h = hours.floor();
  final m = ((hours - h) * 60).floor();
  final s = ((hours - (h + m / 60)) * 3600).floor();
  return DateTime.utc(year, month, day, h, m, s);
}
