import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/hijri_day.dart';

/// Hijri months are cached per Gregorian month so the calendar works offline.
/// The cache key includes the regional offset so an admin adjustment invalidates it.
class CalendarRepository {
  CalendarRepository({required this.api, required this.cache});

  final ApiClient api;
  final KvStore cache;

  /// [preferCache]: answer from the cached month at once and refresh it in the background
  /// (Home's Hijri line); otherwise network first with the cache as the offline fallback.
  Future<List<HijriDay>> month(int year, int month, {int personalOffset = 0, int regionalOffset = 0, bool preferCache = false}) async {
    final key = 'cache.hijri.$year-$month.r$regionalOffset.p$personalOffset';
    if (preferCache) {
      final cached = await _cached(key);
      if (cached != null) {
        _fetch(key, year, month, personalOffset).ignore();
        return cached;
      }
    }
    try {
      return await _fetch(key, year, month, personalOffset);
    } on OfflineException {
      final cached = await _cached(key);
      if (cached == null) rethrow;
      return cached;
    }
  }

  Future<List<HijriDay>> _fetch(String key, int year, int month, int personalOffset) async {
    final json = (await api.get(
      '/v1/calendar/hijri',
      query: {
        'year': '$year',
        'month': '$month',
        'offset': '$personalOffset',
      },
    ) as Map)
        .cast<String, dynamic>();
    final days = (json['days'] as List).map((e) => HijriDay.fromJson((e as Map).cast<String, dynamic>())).toList();
    await cache.write(key, jsonEncode(days.map((d) => d.toJson()).toList()));
    return days;
  }

  Future<List<HijriDay>?> _cached(String key) async {
    final raw = await cache.read(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).map((e) => HijriDay.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return null;
    }
  }
}
