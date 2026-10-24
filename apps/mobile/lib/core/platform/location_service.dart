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

/// Device heading for the Qibla compass.
abstract interface class CompassService {
  Stream<HeadingReading>? get headings;
}

class PluginCompassService implements CompassService {
  @override
  Stream<HeadingReading>? get headings =>
      FlutterCompass.events?.where((e) => e.heading != null).map((e) => HeadingReading((e.heading! + 360) % 360, accuracy: e.accuracy));
}

class FakeCompassService implements CompassService {
  FakeCompassService([this.headings]);
  @override
  final Stream<HeadingReading>? headings;
}
