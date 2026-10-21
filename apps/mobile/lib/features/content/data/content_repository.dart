import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/content_item.dart';

/// Religious content sync (spec §6.11): cached copy → bundled reviewed seed on first launch, then a
/// full refresh from `GET /v1/content` (small; ETag/304 server-side). A full replace also drops items
/// that were unpublished.
class ContentRepository {
  ContentRepository({required this.api, required this.cache, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final ApiClient api;
  final KvStore cache;
  final AssetBundle _bundle;
  static const _key = 'cache.content';
  static const _taskKey = 'cache.dailyTask';

  Future<List<ContentItem>> local() async {
    final raw = await cache.read(_key);
    if (raw != null) {
      try {
        return _parse(jsonDecode(raw));
      } on FormatException {
        // fall through to the seed
      }
    }
    try {
      final seed = jsonDecode(await _bundle.loadString('assets/content/seed.json')) as Map;
      return _parse(seed['items']);
    } on Object {
      return const [];
    }
  }

  /// Returns the fresh list, or null when offline (the cached copy stays).
  Future<List<ContentItem>?> sync() async {
    try {
      final res = await api.get('/v1/content');
      final list = _parse(res);
      await cache.write(_key, jsonEncode([for (final i in list) i.toJson()]));
      return list;
    } on OfflineException {
      return null;
    } on ApiException {
      return null;
    }
  }

  static List<ContentItem> _parse(Object? raw) =>
      raw is List ? raw.map(ContentItem.tryParse).whereType<ContentItem>().toList() : const <ContentItem>[];

  /// «مهمة اليوم» (published only, spec §6.11) — cached per date for offline.
  Future<({String ar, String en})?> dailyTask(String isoDate) async {
    try {
      final res = await api.get('/v1/daily-task', query: {'date': isoDate});
      if (res is Map && res['taskAr'] is String) {
        await cache.write(_taskKey, jsonEncode({'date': isoDate, 'ar': res['taskAr'], 'en': res['taskEn']}));
        return (ar: res['taskAr'] as String, en: (res['taskEn'] as String?) ?? '');
      }
      return null;
    } on Exception {
      final raw = await cache.read(_taskKey);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map;
      return j['date'] == isoDate ? (ar: j['ar'] as String, en: (j['en'] as String?) ?? '') : null;
    }
  }
}
