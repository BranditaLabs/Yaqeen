import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/audio_models.dart';
import 'audio_downloads.dart';

/// Reciter catalogue (spec §5.14) — cached for offline — plus each surah's audio URL and per-ayah
/// timings. Quran Foundation (`qf`) reciters resolve every surah through
/// `GET /v1/content/reciters/:id/surahs/:n`; the answer is kept in KV so a downloaded file still
/// plays with ayah sync offline. Cached answers are refreshed once they are a week old (QF terms,
/// spec §10) — when the refresh fails (offline) the older copy keeps working.
class ReciterRepository {
  ReciterRepository({
    required this.api,
    required this.cache,
    required this.root,
    http.Client? client,
    DateTime Function()? now,
  })  : _http = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final ApiClient api;
  final KvStore cache;

  /// App files root (the same one [AudioDownloads] uses) — for the offline `timings.json`.
  final Future<Directory> Function() root;
  final http.Client _http;
  final DateTime Function() _now;
  static const _key = 'cache.reciters';
  static const freshFor = Duration(days: 7);
  final _timings = <String, Map<String, dynamic>>{};
  final _audio = <String, SurahAudio>{};

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

  Future<File> _timingsFile(String reciterId) async => AudioDownloads.timingsFileIn(await root(), reciterId);

  static String audioKey(String reciterId, int surah) => 'cache.qf.audio.$reciterId.$surah';

  bool _fresh(DateTime fetchedAt) => _now().difference(fetchedAt) < freshFor;

  /// Audio URL + timings for one surah. `own` reciters build the URL locally; `qf` ones ask the API
  /// (cached; a stale copy is used when offline). Null when there's no way to play it right now.
  Future<SurahAudio?> surahAudio(Reciter r, int surah) async {
    if (!r.isQf) {
      final url = r.surahUrl(surah);
      return url == null ? null : SurahAudio(url: url, fetchedAt: _now());
    }
    final key = audioKey(r.id, surah);
    var held = _audio[key];
    if (held == null) {
      final raw = await cache.read(key);
      if (raw != null) {
        try {
          held = SurahAudio.tryParse(jsonDecode(raw));
        } on FormatException {
          held = null;
        }
      }
    }
    if (held != null && _fresh(held.fetchedAt)) return _audio[key] = held;
    try {
      final res = await api.get('/v1/content/reciters/${Uri.encodeComponent(r.id)}/surahs/$surah');
      final got = SurahAudio.tryParse(res, fetchedAt: _now());
      if (got == null) return held;
      await cache.write(key, jsonEncode(got.toJson()));
      return _audio[key] = got;
    } on Exception {
      return held;
    }
  }

  /// Streaming URL for [surah] (throws [OfflineException] when it can't be resolved).
  Future<Uri> surahUri(Reciter r, int surah) async {
    final a = await surahAudio(r, surah);
    if (a == null) throw const OfflineException();
    return a.url;
  }

  /// Saves every surah's timings next to a full download (`timings.json`), so a downloaded
  /// reciter keeps ayah sync offline. Best effort: false when it couldn't be fetched.
  Future<bool> saveOfflineTimings(Reciter r) async {
    if (!r.isQf) return false;
    try {
      final res = await api.get('/v1/content/reciters/${Uri.encodeComponent(r.id)}/timings');
      if (res is! Map || res.isEmpty) return false;
      final file = await _timingsFile(r.id);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(res));
      _timings[r.id] = res.cast<String, dynamic>();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Timings for [surah]: the downloaded `timings.json` first, then the resolved surah (`qf`) or the
  /// reciter's timing file (`own`, kept for offline). Null when there are none — the player still
  /// works, without ayah sync.
  Future<AyahTimings?> timings(Reciter r, int surah) async {
    final local = await _localTimings(r);
    final fromFile = local == null ? null : AyahTimings.fromJson(local['$surah']);
    if (fromFile != null) return fromFile;
    if (r.isQf) return (await surahAudio(r, surah))?.timings;
    final url = r.timingUrl;
    if (url == null) return null;
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final doc = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
      final file = await _timingsFile(r.id);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(res.bodyBytes);
      _timings[r.id] = doc;
      return AyahTimings.fromJson(doc['$surah']);
    } on Exception {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _localTimings(Reciter r) async {
    final mem = _timings[r.id];
    if (mem != null) return mem;
    final file = await _timingsFile(r.id);
    try {
      if (!await file.exists()) return null;
      final doc = (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
      _timings[r.id] = doc;
      // A week-old QF copy is refreshed in the background when online; offline it keeps working.
      if (r.isQf && !_fresh(await file.lastModified())) unawaited(saveOfflineTimings(r));
      return doc;
    } on Exception {
      return null;
    }
  }
}
