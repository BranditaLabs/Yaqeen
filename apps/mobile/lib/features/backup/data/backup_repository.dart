import '../../../core/network/api_client.dart';
import '../domain/backup_merge.dart';

/// One entry of `GET /v1/me/backup` (contracts `BackupManifest`).
class BackupEntry {
  const BackupEntry({required this.kind, required this.version, required this.updatedAt});
  final BackupKind kind;
  final int version;
  final DateTime updatedAt;
}

/// `GET /v1/me/backup/:kind` (contracts `BackupDocument`).
class BackupDocument {
  const BackupDocument({required this.kind, required this.version, required this.updatedAt, required this.data});
  final BackupKind kind;
  final int version;
  final DateTime updatedAt;
  final Json data;

  static BackupDocument? tryParse(Object? j) {
    final m = asJson(j);
    final kind = BackupKind.fromWire('${m?['kind']}');
    final data = asJson(m?['data']);
    if (m == null || kind == null || data == null || m['version'] is! num) return null;
    return BackupDocument(
      kind: kind,
      version: (m['version'] as num).toInt(),
      updatedAt: asTime(m['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      data: data,
    );
  }
}

/// 409 `backup_conflict`: another phone wrote first. [current] is null when the server didn't say.
class BackupConflict implements Exception {
  const BackupConflict(this.current);
  final BackupDocument? current;
}

/// The server said the backup is off for this account (403 `backup_off` / `account_required`).
class BackupOff implements Exception {
  const BackupOff(this.code);
  final String code;
}

/// `/v1/me/backup` — the opt-in cloud backup of device-first progress (consent `cloud_backup`).
class BackupRepository {
  BackupRepository(this.api);
  final ApiClient api;

  Future<T> _call<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on ApiException catch (e) {
      if (e.status == 403 && (e.code == 'backup_off' || e.code == 'account_required')) throw BackupOff(e.code);
      if (e.status == 409 && e.code == 'backup_conflict') throw BackupConflict(BackupDocument.tryParse(e.details));
      rethrow;
    }
  }

  Future<List<BackupEntry>> manifest() => _call(() async {
        final m = asJson(await api.get('/v1/me/backup')) ?? const {};
        return [
          for (final e in asList(m['kinds']))
            if (asJson(e) case final j?)
              if (BackupKind.fromWire('${j['kind']}') case final k?)
                BackupEntry(kind: k, version: (j['version'] as num).toInt(), updatedAt: asTime(j['updatedAt']) ?? DateTime(2000)),
        ];
      });

  Future<BackupDocument?> fetch(BackupKind kind) => _call(() async {
        try {
          return BackupDocument.tryParse(await api.get('/v1/me/backup/${kind.wire}'));
        } on ApiException catch (e) {
          if (e.status == 404) return null;
          rethrow;
        }
      });

  /// Returns the new version; throws [BackupConflict] when [baseVersion] is stale.
  Future<({int version, DateTime updatedAt})> push(BackupKind kind, int baseVersion, Json data, {String? deviceId}) => _call(() async {
        final r = asJson(
              await api.put('/v1/me/backup/${kind.wire}', {
                'baseVersion': baseVersion,
                'data': data,
                if (deviceId != null) 'deviceId': deviceId,
              }),
            ) ??
            const {};
        return (version: (r['version'] as num).toInt(), updatedAt: asTime(r['updatedAt']) ?? DateTime.now().toUtc());
      });
}
