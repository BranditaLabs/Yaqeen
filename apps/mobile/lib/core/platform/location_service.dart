import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';

enum LocationStatus { granted, denied, deniedForever, serviceOff }

class LocationFix {
  const LocationFix(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// When-in-use location, requested only from prayer setup / Qibla (spec §5.5). Never sent to the API.
abstract interface class LocationService {
  Future<LocationStatus> requestPermission();
  Future<LocationFix?> current();
  Future<String> deviceTimezone();
}

class PluginLocationService implements LocationService {
  @override
  Future<LocationStatus> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationStatus.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.always || LocationPermission.whileInUse => LocationStatus.granted,
      LocationPermission.deniedForever => LocationStatus.deniedForever,
      _ => LocationStatus.denied,
    };
  }

  @override
  Future<LocationFix?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
      );
      return LocationFix(p.latitude, p.longitude);
    } on Exception {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : LocationFix(last.latitude, last.longitude);
    }
  }

  @override
  Future<String> deviceTimezone() async => (await FlutterTimezone.getLocalTimezone()).identifier;
}

class FakeLocationService implements LocationService {
  FakeLocationService({this.status = LocationStatus.denied, this.fix, this.timezone = 'Africa/Cairo'});
  LocationStatus status;
  LocationFix? fix;
  String timezone;

  @override
  Future<LocationStatus> requestPermission() async => status;
  @override
  Future<LocationFix?> current() async => status == LocationStatus.granted ? fix : null;
  @override
  Future<String> deviceTimezone() async => timezone;
}

class HeadingReading {
  const HeadingReading(this.degrees, {this.accuracy});

  /// Degrees clockwise from north.
  final double degrees;

  /// Estimated error in degrees (null when the platform doesn't report it).
  final double? accuracy;

  bool get needsCalibration => accuracy != null && accuracy! > 25;
}

/// Device heading for the Qibla compass, from TRUE north (the Qibla bearing is a true bearing).
abstract interface class CompassService {
  /// Headings at the place [lat], [lng] (where the magnetic declination is taken when the platform
  /// reports magnetic north); null when the device has no compass.
  Stream<HeadingReading>? headingsAt(double lat, double lng);
}

class PluginCompassService implements CompassService {
  PluginCompassService({Future<double?> Function(double lat, double lng)? declination})
      : _declination = declination ?? _platformDeclination;

  final Future<double?> Function(double lat, double lng) _declination;

  /// MainActivity.kt answers `declination` from android.hardware.GeomagneticField (WMM).
  static const _android = MethodChannel('com.yaqinbrand.yaqeen/device');

  @override
  Stream<HeadingReading>? headingsAt(double lat, double lng) {
    final raw = FlutterCompass.events?.where((e) => e.heading != null).map((e) => HeadingReading(e.heading!, accuracy: e.accuracy));
    return raw == null ? null : trueHeadings(raw, _declination(lat, lng));
  }

  /// flutter_compass on Android derives the heading from the rotation vector, i.e. magnetic north
  /// with no declination applied; on iOS it already sends CLHeading.trueHeading (null → unchanged).
  static Future<double?> _platformDeclination(double lat, double lng) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _android.invokeMethod<double>('declination', {'lat': lat, 'lng': lng});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Magnetic → true north: adds [declination] (degrees, east positive) to every heading. When it is
/// unknown (iOS, no answer within 2 s) the headings pass through unchanged.
Stream<HeadingReading> trueHeadings(Stream<HeadingReading> headings, Future<double?> declination) {
  final offset = declination.timeout(const Duration(seconds: 2)).then((d) => d ?? 0.0, onError: (Object _) => 0.0);
  return Stream.fromFuture(offset)
      .asyncExpand((d) => headings.map((h) => HeadingReading((h.degrees + d) % 360, accuracy: h.accuracy)));
}

class FakeCompassService implements CompassService {
  FakeCompassService([this.headings]);
  final Stream<HeadingReading>? headings;

  @override
  Stream<HeadingReading>? headingsAt(double lat, double lng) => headings;
}
