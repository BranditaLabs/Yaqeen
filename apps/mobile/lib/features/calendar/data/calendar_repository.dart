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

  Future<List<HijriDay>> month(int year, int month, {int personalOffset = 0, int regionalOffset = 0}) async {
    final key = 'cache.hijri.$year-$month.r$regionalOffset.p$personalOffset';
    try {
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
    } on OfflineException {
      final raw = await cache.read(key);
      if (raw == null) rethrow;
      return (jsonDecode(raw) as List).map((e) => HijriDay.fromJson((e as Map).cast<String, dynamic>())).toList();
    }
  }
}
