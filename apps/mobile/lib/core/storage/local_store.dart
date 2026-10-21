import 'dart:convert';

import 'kv_store.dart';

/// On-device user data (spec §9.3 "user.db"): bookmarks, last read, wird log, azkar progress,
/// hifz plan and reviews, inbox, content cache. Each collection is one JSON document in [KvStore]
/// under `db.<name>`, with a schema version and ordered migrations (ADR 0006).
///
/// Never synced to the server (spec §6.13) — sign-out wipes only the synced caches, not this.
class LocalStore {
  LocalStore(this._kv);

  final KvStore _kv;

  static const schemaVersion = 2;
  static const _versionKey = 'db.version';

  /// version → migration that brings the store from version-1 to version.
  static final Map<int, Future<void> Function(KvStore kv)> migrations = {
    // v1: first versioned schema — collections start empty.
    1: (kv) async {},
    // v2: the old prefs-only last-read key moves into the reading collection.
    2: (kv) async {
      final legacy = await kv.read('quran.lastRead');
      if (legacy != null) {
        await kv.write('db.reading', jsonEncode({'lastRead': jsonDecode(legacy)}));
        await kv.delete('quran.lastRead');
      }
    },
  };

  Future<int> get version async => int.tryParse(await _kv.read(_versionKey) ?? '') ?? 0;

  /// Runs pending migrations in order. Safe to call on every start.
  Future<void> migrate() async {
    for (var v = await version + 1; v <= schemaVersion; v++) {
      await migrations[v]!(_kv);
      await _kv.write(_versionKey, '$v');
    }
  }

  Future<Object?> read(String collection) async {
    final raw = await _kv.read('db.$collection');
    return raw == null ? null : jsonDecode(raw);
  }

  Future<Map<String, dynamic>> readMap(String collection) async => ((await read(collection)) as Map?)?.cast<String, dynamic>() ?? {};

  Future<List<dynamic>> readList(String collection) async => ((await read(collection)) as List?) ?? [];

  Future<void> write(String collection, Object value) => _kv.write('db.$collection', jsonEncode(value));

  Future<void> delete(String collection) => _kv.delete('db.$collection');
}
