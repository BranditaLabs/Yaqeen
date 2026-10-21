import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// IANA time zone helpers. Prayer times are computed as UTC instants and shown in the place's zone,
/// so a Cairo user travelling abroad keeps correct times and Egypt's DST switches are exact.
abstract final class Zoned {
  static bool _ready = false;

  static void ensureInitialized() {
    if (_ready) return;
    tzdata.initializeTimeZones();
    _ready = true;
  }

  static tz.Location location(String name) {
    ensureInitialized();
    try {
      return tz.getLocation(name);
    } on Exception {
      return tz.getLocation('Africa/Cairo');
    }
  }

  /// Wall-clock time of [utc] in [zone].
  static tz.TZDateTime local(DateTime utc, String zone) => tz.TZDateTime.from(utc, location(zone));

  /// The calendar date (midnight, as a plain DateTime) of [now] in [zone].
  static DateTime today(String zone, DateTime now) {
    final l = local(now.toUtc(), zone);
    return DateTime(l.year, l.month, l.day);
  }

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
