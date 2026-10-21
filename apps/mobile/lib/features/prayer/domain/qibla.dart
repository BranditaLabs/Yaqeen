import 'dart:math' as math;

import 'astronomy.dart';

/// The Kaaba (spec §5.16).
const kaabaLat = 21.4225;
const kaabaLng = 39.8262;

/// Great-circle initial bearing from the user to the Kaaba, degrees clockwise from true north.
double qiblaBearing(double lat, double lng) {
  final dLng = degToRad(kaabaLng - lng);
  final y = math.sin(dLng);
  final x = math.cos(degToRad(lat)) * math.tan(degToRad(kaabaLat)) - math.sin(degToRad(lat)) * math.cos(dLng);
  return unwindAngle(radToDeg(math.atan2(y, x)));
}

/// Great-circle distance to the Kaaba in kilometres (haversine, mean Earth radius).
double distanceToKaabaKm(double lat, double lng) => haversineKm(lat, lng, kaabaLat, kaabaLng);

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0088;
  final dLat = degToRad(lat2 - lat1);
  final dLng = degToRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(degToRad(lat1)) * math.cos(degToRad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Signed turn from the device heading to the Qibla, in (-180, 180]. Positive = turn right.
double turnToQibla(double heading, double qibla) {
  final d = unwindAngle(qibla - heading);
  return d > 180 ? d - 360 : d;
}

enum QiblaGuidance { turnRight, turnLeft, aligned }

/// ±3° counts as facing the Qibla (spec §5.16).
QiblaGuidance guidanceFor(double turn, {double tolerance = 3}) {
  if (turn.abs() <= tolerance) return QiblaGuidance.aligned;
  return turn > 0 ? QiblaGuidance.turnRight : QiblaGuidance.turnLeft;
}

/// 8-point compass label for a bearing (used in «من الشمال باتجاه الجنوب الشرقي»).
enum CompassPoint { n, ne, e, se, s, sw, w, nw }

CompassPoint compassPoint(double bearing) => CompassPoint.values[((unwindAngle(bearing) + 22.5) ~/ 45) % 8];
