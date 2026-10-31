import 'dart:convert';

import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../prayer/data/prayer_repository.dart';
import '../../prayer/domain/prayer_clock.dart';
import '../../prayer/presentation/prayer_labels.dart';

/// What the home-screen widgets show (spec §5.28), as one JSON document. Times are UTC epoch
/// milliseconds; every label is already localised and every time already formatted (Western digits,
/// the place's zone), so the native widgets only pick the first future prayer and count down to it.
///
/// A week of prayers keeps the widget right even if the app isn't opened for days; after that it
/// shows [staleText]. Device-only: nothing here leaves the phone.
abstract final class WidgetSnapshot {
  static const version = 1;
  static const days = 7;

  static String build({
    required AppSettings settings,
    required PrayerRepository prayers,
    required DateTime now,
    required AppLocalizations t,
    String? hijri,
    int wirdPages = 0,
    int? ramadanDay,
    Set<DateTime> ramadanDates = const {},
  }) {
    final s = settings;
    final today = prayers.today(s, now);
    final list = <Map<String, Object>>[];
    for (var i = 0; i < days; i++) {
      final date = DateTime(today.year, today.month, today.day + i);
      final times = prayers.forDate(s, date, ramadan: ramadanDates.contains(date));
      final friday = date.weekday == DateTime.friday;
      for (final p in obligatory) {
        final at = times.of(p);
        list.add({
          'key': p.name,
          'label': prayerLabel(t, p, friday: friday),
          'at': at.millisecondsSinceEpoch,
          'time': YqFormat.time(prayers.local(s, at), s.locale),
        });
      }
    }
    final goal = s.wirdGoalPages;
    return jsonEncode({
      'v': version,
      'locale': s.locale,
      'rtl': s.locale == 'ar',
      'place': s.placeOrDefault.name(s.locale),
      'hijri': hijri,
      'nextLabel': t.nextPrayer,
      'prayers': list,
      'wird': {'label': t.widgetWird, 'pages': wirdPages.clamp(0, goal), 'goal': goal, 'text': t.pagesOf(wirdPages.clamp(0, goal), goal)},
      'ramadan': ramadanDay == null ? null : t.ramadanHomeChip(YqFormat.number(ramadanDay)),
      'staleText': t.widgetStale,
      'updatedAt': now.toUtc().millisecondsSinceEpoch,
    });
  }
}
