import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/backup_merge.dart';
import 'backup_adapters.dart';
import 'backup_repository.dart';

/// Per kind: the server version this phone last agreed with and when this phone last changed it.
class _KindMeta {
  const _KindMeta({this.version = 0, this.changedAt});
  final int version;
  final DateTime? changedAt;

  Json toJson() => {'v': version, if (changedAt != null) 'at': changedAt!.toIso8601String()};
  static _KindMeta fromJson(Object? j) {
    final m = asJson(j) ?? const {};
    return _KindMeta(version: (m['v'] as num?)?.toInt() ?? 0, changedAt: asTime(m['at']));
  }
}

class _Meta {
  _Meta({required this.kinds, required this.dirty, this.lastSync, this.device});
  final Map<BackupKind, _KindMeta> kinds;
  final Set<BackupKind> dirty;
  DateTime? lastSync;
  String? device;

  Json toJson() => {
        'kinds': {for (final e in kinds.entries) e.key.wire: e.value.toJson()},
        'dirty': [for (final k in dirty) k.wire],
        if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
        if (device != null) 'device': device,
      };
  static _Meta fromJson(Json? j) => _Meta(
        kinds: {
          for (final e in (asJson(j?['kinds']) ?? const {}).entries)
            if (BackupKind.fromWire(e.key) case final k?) k: _KindMeta.fromJson(e.value),
        },
        dirty: {
          for (final w in asList(j?['dirty']))
            if (BackupKind.fromWire('$w') case final k?) k,
        },
        lastSync: asTime(j?['lastSync']),
        device: j?['device'] as String?,
      );
}

/// The cloud backup's sync, independent of Flutter: pull the manifest, merge what is newer on the
/// server into this phone's stores (adapters), push what changed here, and on a 409 merge with the
/// winner and retry once. The server copy only ever moves forward by version; the phone keeps the
/// last agreed copy per kind (`backup.base.<kind>`) so merges are three-way. Offline and server
/// errors leave kinds marked dirty for the next attempt — local data is never held back.
class BackupEngine {
  BackupEngine({required this.repo, required this.adapters, required this.kv, required this.now, this.onImported});

  final BackupRepository repo;
  final List<BackupAdapter> adapters;
  final KvStore kv;
  final DateTime Function() now;

  /// A merged document was written into this phone's stores (refresh what shows it).
  final void Function(BackupKind kind, Json doc)? onImported;

  static const metaKey = 'backup.meta.v1';
  static const offeredKey = 'backup.offered.v1';
  static String baseKey(BackupKind k) => 'backup.base.${k.wire}';

  /// Every key the backup keeps on the phone (wiped on sign-out and account deletion).
  static List<String> get storageKeys => [metaKey, for (final k in BackupKind.values) baseKey(k)];

  /// True while the backup writes a merged copy into the stores — those writes are not user changes.
  bool importing = false;

  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  List<BackupAdapter> adaptersFor(String key) => [
        for (final a in adapters)
          if (a.watches(key)) a,
      ];

  Future<_Meta> _meta() async {
    final raw = await kv.read(metaKey);
    if (raw == null) return _Meta(kinds: {}, dirty: {});
    try {
      return _Meta.fromJson(asJson(jsonDecode(raw)));
    } on FormatException {
      return _Meta(kinds: {}, dirty: {});
    }
  }

  Future<void> _save(_Meta m) => kv.write(metaKey, jsonEncode(m.toJson()));

  Future<Json?> _base(BackupKind k) async {
    final raw = await kv.read(baseKey(k));
    if (raw == null) return null;
    try {
      return asJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> _setBase(BackupKind k, Json doc) => kv.write(baseKey(k), jsonEncode(doc));

  /// This phone changed [kinds]: remember when, and that they need uploading.
  Future<void> noteChange(Iterable<BackupKind> kinds) => _serial(() async {
        final m = await _meta();
        final at = now().toUtc();
        for (final k in kinds) {
          m.kinds[k] = _KindMeta(version: m.kinds[k]?.version ?? 0, changedAt: at);
          m.dirty.add(k);
        }
        await _save(m);
      });

  Future<DateTime?> lastBackupAt() async => (await _meta()).lastSync;
  Future<bool> hasPending() async => (await _meta()).dirty.isNotEmpty;

  /// Pull + merge + push every kind. Throws [BackupOff] or an offline error; per-kind server errors
  /// leave that kind dirty and carry on.
  Future<void> syncAll() => _serial(() async {
        final m = await _meta();
        final manifest = {for (final e in await repo.manifest()) e.kind: e};
        try {
          for (final a in adapters) {
            await _guardKind(m, () => _syncKind(m, a, manifest[a.kind], manifestKnown: true));
          }
          m.lastSync = now().toUtc();
        } finally {
          await _save(m);
        }
      });

  /// Upload what changed here since the last sync (a 409 still merges and retries once).
  Future<void> pushDirty() => _serial(() async {
        final m = await _meta();
        if (m.dirty.isEmpty) return;
        try {
          for (final a in adapters.where((a) => m.dirty.contains(a.kind))) {
            await _guardKind(m, () => _syncKind(m, a, null, manifestKnown: false));
          }
          if (m.dirty.isEmpty) m.lastSync = now().toUtc();
        } finally {
          await _save(m);
        }
      });

  Future<void> _guardKind(_Meta m, Future<void> Function() op) async {
    try {
      await op();
    } on BackupOff {
      rethrow;
    } on OfflineException {
      rethrow;
    } on BackupConflict {
      // Lost twice in a row: stays dirty, the next sync tries again.
    } on FormatException {
      // A document this build can't read: leave it alone.
    } on ApiException {
      // 413 / 5xx: the kind stays dirty.
    }
  }

  Future<void> _syncKind(_Meta m, BackupAdapter a, BackupEntry? remote, {required bool manifestKnown}) async {
    final k = a.kind;
    final st = m.kinds[k] ?? const _KindMeta();
    final local = await a.export();
    var base = await _base(k);
    if (manifestKnown && remote != null && remote.version != st.version) {
      final doc = await repo.fetch(k);
      if (doc != null) return _reconcile(m, a, local, base, doc, retry: true);
    }
    var version = st.version;
    if (manifestKnown && remote == null && version > 0) {
      // The server copy is gone (switched off and on again elsewhere): start over from this phone.
      version = 0;
      base = null;
    }
    if (version > 0 && base != null && sameJson(local, base)) {
      m.dirty.remove(k);
      return;
    }
    if (version == 0 && a.isEmpty(local)) {
      m.dirty.remove(k);
      return;
    }
    await _push(m, a, version, local, retry: true);
  }

  Future<void> _push(_Meta m, BackupAdapter a, int baseVersion, Json data, {required bool retry}) async {
    final k = a.kind;
    m.device ??= Outbox.newEventId();
    try {
      final r = await repo.push(k, baseVersion, data, deviceId: m.device);
      m.kinds[k] = _KindMeta(version: r.version, changedAt: m.kinds[k]?.changedAt);
      await _setBase(k, data);
      m.dirty.remove(k);
    } on BackupConflict catch (c) {
      if (!retry) rethrow;
      final doc = c.current ?? await repo.fetch(k);
      if (doc == null) rethrow;
      await _reconcile(m, a, await a.export(), await _base(k), doc, retry: false);
    }
  }

  Future<void> _reconcile(_Meta m, BackupAdapter a, Json local, Json? base, BackupDocument doc, {required bool retry}) async {
    final k = a.kind;
    final changedAt = m.kinds[k]?.changedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final merged = a.merge(local, doc.data, base: base, localAt: changedAt, remoteAt: doc.updatedAt);
    var settled = local;
    if (!sameJson(merged, local)) {
      importing = true;
      try {
        await a.import(merged);
      } finally {
        importing = false;
      }
      // Read back what the store now holds, so later comparisons are like for like.
      settled = await a.export();
      onImported?.call(k, settled);
    }
    if (sameJson(settled, doc.data)) {
      m.kinds[k] = _KindMeta(version: doc.version, changedAt: m.kinds[k]?.changedAt);
      await _setBase(k, settled);
      m.dirty.remove(k);
      return;
    }
    await _push(m, a, doc.version, settled, retry: retry);
  }

  /// Switched off, signed out or deleted: forget versions, bases and pending uploads.
  Future<void> forget() => _serial(() async {
        for (final key in storageKeys) {
          await kv.delete(key);
        }
      });

  Future<bool> wasOffered(String userId) async => (await kv.read(offeredKey))?.split(',').contains(userId) ?? false;

  Future<void> markOffered(String userId) async {
    final ids = {...?(await kv.read(offeredKey))?.split(',').where((s) => s.isNotEmpty), userId};
    await kv.write(offeredKey, ids.join(','));
  }
}
