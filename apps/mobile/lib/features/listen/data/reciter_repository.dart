import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/audio_models.dart';
import 'audio_downloads.dart';

/// Reciter catalogue (spec §5.14) — cached for offline, plus per-surah ayah timings.
class ReciterRepository {
  ReciterRepository({required this.api, required this.cache, required this.downloads, http.Client? client})
      : _http = client ?? http.Client();

  final ApiClient api;
  final KvStore cache;
  final AudioDownloads downloads;
  final http.Client _http;
  static const _key = 'cache.reciters';
  final _timings = <String, Map<String, dynamic>>{};

  Future<List<Reciter>> list() async {
    try {
      final res = await api.get('/v1/content/reciters');
      final raw = res is Map ? res['reciters'] : res;
      final list = _parse(raw);
      await cache.write(_key, jsonEncode([for (final r in list) r.toJson()]));
      return list;
    } on Exception {
      return cached();
    }
  }

  Future<List<Reciter>> cached() async {
    final raw = await cache.read(_key);
    if (raw == null) return const [];
    try {
      return _parse(jsonDecode(raw));
    } on FormatException {
      return const [];
    }
  }

  static List<Reciter> _parse(Object? raw) => raw is List ? raw.map(Reciter.tryParse).whereType<Reciter>().toList() : const <Reciter>[];

  /// Timings for [surah], from the downloaded copy first, then the network (kept for offline).
  /// Null when the reciter publishes none — the player still works, without ayah sync.
  Future<AyahTimings?> timings(Reciter r, int surah) async {
    final url = r.timingUrl;
    if (url == null) return null;
    var doc = _timings[r.id];
    if (doc == null) {
      final file = await downloads.timingsFile(r.id);
      try {
        if (await file.exists()) {
          doc = (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
        } else {
          final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return null;
          doc = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
          await file.parent.create(recursive: true);
          await file.writeAsBytes(res.bodyBytes);
        }
      } on Exception {
        return null;
      }
      _timings[r.id] = doc;
    }
    return AyahTimings.fromJson(doc['$surah']);
  }
}
