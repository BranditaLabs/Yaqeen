/// Mirrors contracts `PackKind`. Only tafsir packs are installed today.
enum PackKind { tafsir, font, audio, translation }

/// A downloadable pack from `GET /v1/content/packs` (spec §6.6). Installed only after its
/// SHA-256 matches.
class ContentPack {
  const ContentPack({
    required this.id,
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    required this.version,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final String id;
  final PackKind kind;
  final String titleAr;
  final String titleEn;
  final int version;
  final String url;
  final String sha256;
  final int sizeBytes;

  String title(String locale) => locale == 'ar' ? titleAr : titleEn;

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  static ContentPack? tryParse(Object? j) {
    if (j is! Map) return null;
    final kind = PackKind.values.asNameMap()[j['kind']];
    final sha = j['sha256'];
    if (kind == null || sha is! String || !_hex64.hasMatch(sha) || j['id'] is! String || j['url'] is! String) return null;
    return ContentPack(
      id: j['id'] as String,
      kind: kind,
      titleAr: (j['titleAr'] as String?) ?? '',
      titleEn: (j['titleEn'] as String?) ?? '',
      version: (j['version'] as num?)?.toInt() ?? 1,
      url: j['url'] as String,
      sha256: sha,
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'version': version,
        'url': url,
        'sha256': sha256,
        'sizeBytes': sizeBytes,
      };
}

/// An installed pack is replaced only by a strictly newer version.
bool needsUpdate(int? installedVersion, ContentPack pack) => installedVersion != null && pack.version > installedVersion;
