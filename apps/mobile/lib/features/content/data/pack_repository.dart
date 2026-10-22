import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/resumable_download.dart';
import '../../../core/storage/kv_store.dart';
import '../../../core/storage/local_store.dart';
import '../domain/content_pack.dart';

class PackChecksumMismatch implements Exception {
  const PackChecksumMismatch();
}

/// Downloads, verifies and installs content packs (spec §6.6). A pack is visible to the app only
/// after its SHA-256 matches the catalogue; until then the UI keeps the bracketed placeholder.
class PackRepository {
  PackRepository({
    required this.api,
    required this.cache,
    required this.store,
    required this.root,
    required this.isUnmetered,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final ApiClient api;
  final KvStore cache;
  final LocalStore store;
  final Future<Directory> Function() root;
  final Future<bool> Function() isUnmetered;
  final http.Client _http;

  static const _cacheKey = 'cache.packs';
  static const _doc = 'packs';
  static const weeklyCheck = Duration(days: 7);

  Future<List<ContentPack>> catalogue() async {
    try {
      final res = await api.get('/v1/content/packs');
      final list = _parse(res);
      await cache.write(_cacheKey, jsonEncode([for (final p in list) p.toJson()]));
      return list;
    } on Exception {
      final raw = await cache.read(_cacheKey);
      if (raw == null) return const [];
      try {
        return _parse(jsonDecode(raw));
      } on FormatException {
        return const [];
      }
    }
  }

  static List<ContentPack> _parse(Object? raw) =>
      raw is List ? raw.map(ContentPack.tryParse).whereType<ContentPack>().toList() : const <ContentPack>[];

  Future<Directory> _dir() async => Directory('${(await root()).path}/packs');
  Future<File> _fileFor(String id) async => File('${(await _dir()).path}/$id.json');

  /// `{id: {kind, version}}` of installed packs.
  Future<Map<String, dynamic>> installed() async => ((await store.readMap(_doc))['installed'] as Map?)?.cast<String, dynamic>() ?? {};

  Future<int?> installedVersion(String id) async => ((await installed())[id] as Map?)?['version'] as int?;

  /// The active pack file of [kind], if one is installed and present on disk.
  Future<File?> installedFile(PackKind kind) async {
    for (final e in (await installed()).entries) {
      if ((e.value as Map)['kind'] == kind.name) {
        final f = await _fileFor(e.key);
        if (await f.exists()) return f;
      }
    }
    return null;
  }

  /// Static so the isolate closure captures only [path], never this repository.
  static Future<String> _sha256Of(String path) => Isolate.run(() => sha256.convert(File(path).readAsBytesSync()).toString());

  Future<void> install(
    ContentPack pack, {
    CancelToken? cancel,
    bool allowMetered = false,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (!allowMetered && !await isUnmetered()) throw const WifiRequired();
    final dir = await _dir();
    final staging = File('${dir.path}/${pack.id}.v${pack.version}.download');
    await downloadResumable(_http, Uri.parse(pack.url), staging, cancel: cancel, onProgress: onProgress);
    // Hash on a background isolate: a multi-MB pack would otherwise stall the UI thread.
    final digest = await _sha256Of(staging.path);
    if (digest != pack.sha256) {
      await staging.delete();
      throw const PackChecksumMismatch();
    }
    // Only now does it replace the active pack (an update never leaves a broken one behind).
    final target = await _fileFor(pack.id);
    if (await target.exists()) await target.delete();
    await staging.rename(target.path);
    await _setInstalled(pack.id, {'kind': pack.kind.name, 'version': pack.version});
  }

  Future<void> remove(String id) async {
    final f = await _fileFor(id);
    if (await f.exists()) await f.delete();
    await _setInstalled(id, null);
  }

  Future<void> _setInstalled(String id, Map<String, Object>? value) async {
    final doc = await store.readMap(_doc);
    final map = {...((doc['installed'] as Map?)?.cast<String, dynamic>() ?? {})};
    value == null ? map.remove(id) : map[id] = value;
    doc['installed'] = map;
    await store.write(_doc, doc);
  }

  Future<int> bytesOnDisk() async {
    final d = await _dir();
    if (!await d.exists()) return 0;
    var total = 0;
    await for (final f in d.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  /// At most once per [weeklyCheck]: installed packs that have a newer version in the catalogue.
  Future<List<ContentPack>> checkWeekly(DateTime now) async {
    final doc = await store.readMap(_doc);
    final last = DateTime.tryParse((doc['checkedAt'] as String?) ?? '');
    if (last != null && now.difference(last) < weeklyCheck) return const [];
    final cat = await catalogue();
    doc['checkedAt'] = now.toIso8601String();
    await store.write(_doc, doc);
    final inst = await installed();
    return [
      for (final p in cat)
        if (needsUpdate((inst[p.id] as Map?)?['version'] as int?, p)) p,
    ];
  }
}
