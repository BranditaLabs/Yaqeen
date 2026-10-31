import 'dart:convert';

import '../../../core/storage/kv_store.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../calendar/domain/hijri_day.dart';
import '../domain/ramadan.dart';

/// The imsakiyya's days (from the cached Hijri calendar, so it works offline once seen) and the
/// month's tracker, device first (optional encrypted cloud backup, consent `cloud_backup`).
class RamadanRepository {
  RamadanRepository({required this.calendar, required this.store});

  final CalendarRepository calendar;
  final KvStore store;

  static String _key(int hijriYear) => logKey(hijriYear);
  static String logKey(int hijriYear) => 'ramadan.log.$hijriYear.v1';

  /// Ramadan of [hijriYear], read from the Gregorian months around [today] (Ramadan spans at most
  /// two of them; the previous one covers its first days when today is late in the month).
  Future<List<RamadanDay>> month(int hijriYear, DateTime today, {int personalOffset = 0, int regionalOffset = 0}) async {
    final days = <HijriDay>[];
    for (final delta in const [-1, 0, 1, 2]) {
      final m = DateTime(today.year, today.month + delta);
      try {
        days.addAll(
          await calendar.month(m.year, m.month, personalOffset: personalOffset, regionalOffset: regionalOffset, preferCache: true),
        );
      } on Exception {
        // A month we can't reach offline just leaves a gap; the rest still shows.
      }
    }
    return RamadanDay.from(days, hijriYear);
  }

  /// Ramadan dates (local midnight) among the [days] days from [today] — the reminder planner's
  /// window. Empty offline with nothing cached.
  Future<Set<DateTime>> ramadanDatesAhead(DateTime today, int days, {int personalOffset = 0, int regionalOffset = 0}) async {
    final last = DateTime(today.year, today.month, today.day + days);
    final out = <DateTime>{};
    for (var m = DateTime(today.year, today.month); !m.isAfter(last); m = DateTime(m.year, m.month + 1)) {
      try {
        for (final d
            in await calendar.month(m.year, m.month, personalOffset: personalOffset, regionalOffset: regionalOffset, preferCache: true)) {
          if (d.hijriMonth != ramadanMonth) continue;
          final p = d.gregorian.split('-').map(int.parse).toList();
          final date = DateTime(p[0], p[1], p[2]);
          if (!date.isBefore(today) && date.isBefore(last)) out.add(date);
        }
      } on Exception {
        // Offline and not cached: no Ramadan reminders for that month yet.
      }
    }
    return out;
  }

  Future<RamadanLog> log(int hijriYear) async {
    final raw = await store.read(_key(hijriYear));
    if (raw == null) return const RamadanLog();
    try {
      return RamadanLog.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const RamadanLog();
    }
  }

  Future<void> save(int hijriYear, RamadanLog log) => store.write(_key(hijriYear), jsonEncode(log.toJson()));
}
