import 'dart:convert';
import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/quran_data.dart';

/// A tafsir the user can pick (from `GET /v1/content/tafsirs`).
class TafsirInfo {
  const TafsirInfo({required this.id, required this.nameAr, required this.nameEn, required this.language, this.attribution});
  final String id;
  final String nameAr;
  final String nameEn;
  final String language;
  final String? attribution;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;

  static TafsirInfo? tryParse(Object? j) {
    if (j is! Map || j['id'] is! String || j['nameAr'] is! String || j['nameEn'] is! String) return null;
    return TafsirInfo(
      id: j['id'] as String,
      nameAr: j['nameAr'] as String,
      nameEn: j['nameEn'] as String,
      language: (j['language'] as String?) ?? 'ar',
      attribution: j['attribution'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'nameAr': nameAr, 'nameEn': nameEn, 'language': language, 'attribution': attribution};
}

enum TafsirSource { pack, qf }

/// Text for one ayah plus where it came from (the UI credits the source every time it is shown).
class TafsirText {
  const TafsirText({required this.text, required this.source, this.tafsirId});
  final String text;
  final TafsirSource source;
  final String? tafsirId;
}

/// Tafsir text for an ayah (spec §6.6, §10):
///  1. an installed, checksum-verified pack (`tafsir_<id>.json`, `{"s:a": text}`);
///  2. Quran.com / Quran Foundation through our API, one surah at a time
///     (`GET /v1/content/tafsirs/:id/surahs/:n`), kept on the device so it opens offline later.
///     A copy older than a week is refreshed when online (QF terms); offline the older copy is used.
/// Null only when neither is available (offline with nothing cached) — the UI then shows the
/// bracketed placeholder.
class TafsirRepository {
  TafsirRepository({this.packFile, this.api, this.store, this.root, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// `tafsir_<id>.json` downloaded by the pack manager: {"<surah>:<ayah>": "<text>"}.
  final Future<File?> Function()? packFile;
  final ApiClient? api;
  final KvStore? store;
  final Future<Directory> Function()? root;
  final DateTime Function() _now;

  static const defaultTafsir = 'muyassar';
  static const freshFor = Duration(days: 7);
  static const _selectedKey = 'tafsir.selected';
  static const _listKey = 'cache.tafsirs';

  Map<String, String>? _pack;
  final _surahs = <String, Map<String, String>>{};

  Future<String> selected() async => (await store?.read(_selectedKey)) ?? defaultTafsir;
  Future<void> select(String id) async {
    await store?.write(_selectedKey, id);
    _surahs.clear();
  }

  /// Curated tafsirs (cached for offline); empty when never fetched and offline.
  Future<List<TafsirInfo>> list() async {
    List<TafsirInfo> parse(Object? raw) => raw is List ? raw.map(TafsirInfo.tryParse).whereType<TafsirInfo>().toList() : const [];
    final client = api;
    if (client != null) {
      try {
        final res = await client.get('/v1/content/tafsirs');
        final out = parse(res);
        if (out.isNotEmpty) await store?.write(_listKey, jsonEncode([for (final t in out) t.toJson()]));
        return out;
      } on Exception {
        // fall through to the cached list
      }
    }
    final raw = await store?.read(_listKey);
    if (raw == null) return const [];
    try {
      return parse(jsonDecode(raw));
    } on FormatException {
      return const [];
    }
  }

  Future<String?> forAyah(AyahRef r) async => (await lookup(r))?.text;

  Future<TafsirText?> lookup(AyahRef r) async {
    final pack = await _packText(r);
    if (pack != null) return TafsirText(text: pack, source: TafsirSource.pack);
    final id = await selected();
    final ayat = await _surah(id, r.surah);
    if (ayat == null) return null;
    // A commentary covering several ayat sits on the first of them.
    for (var a = r.ayah; a >= 1; a--) {
      final t = ayat['${r.surah}:$a'];
      if (t != null && t.isNotEmpty) return TafsirText(text: t, source: TafsirSource.qf, tafsirId: id);
    }
    return null;
  }

  Future<String?> _packText(AyahRef r) async {
    if (_pack == null) {
      final f = await packFile?.call();
      if (f == null || !f.existsSync()) return null;
      _pack = (jsonDecode(await f.readAsString()) as Map).cast<String, String>();
    }
    return _pack!['${r.surah}:${r.ayah}'];
  }

  Future<File?> _file(String id, int surah) async {
    final dir = await root?.call();
    return dir == null ? null : File('${dir.path}/tafsir/$id/$surah.json');
  }

  Future<Map<String, String>?> _surah(String id, int surah) async {
    final mem = _surahs['$id:$surah'];
    if (mem != null) return mem;
    final file = await _file(id, surah);
    Map<String, String>? held;
    DateTime? fetchedAt;
    if (file != null && await file.exists()) {
      try {
        final doc = jsonDecode(await file.readAsString()) as Map;
        held = (doc['ayat'] as Map).cast<String, String>();
        fetchedAt = DateTime.tryParse('${doc['fetchedAt']}');
      } on Object {
        held = null;
      }
    }
    if (held != null && fetchedAt != null && _now().difference(fetchedAt) < freshFor) return _surahs['$id:$surah'] = held;
    final client = api;
    if (client != null) {
      try {
        final res = await client.get('/v1/content/tafsirs/${Uri.encodeComponent(id)}/surahs/$surah');
        final ayat = res is Map && res['ayat'] is Map ? (res['ayat'] as Map).cast<String, String>() : null;
        if (ayat != null && ayat.isNotEmpty) {
          if (file != null) {
            await file.parent.create(recursive: true);
            await file.writeAsString(jsonEncode({'fetchedAt': _now().toUtc().toIso8601String(), 'ayat': ayat}));
          }
          return _surahs['$id:$surah'] = ayat;
        }
      } on Exception {
        // offline / unavailable: the older copy (if any) still reads
      }
    }
    if (held != null) _surahs['$id:$surah'] = held;
    return held;
  }
}
