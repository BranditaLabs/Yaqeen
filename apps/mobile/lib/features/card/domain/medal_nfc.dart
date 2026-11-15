import 'public_card.dart';

/// What a medal's NFC chip may carry: only our own permanent link `<site>/t/<CODE>` (spec §5.26).
///
/// Strict on purpose — a chip can hold anything, and the app must never be steered by a stranger's
/// tag: https only (or exactly the configured site, for dev builds on http), no user info, no query
/// or fragment, and a path of exactly `/t/<8-character code>` from the tag alphabet.
/// Returns the code (upper case) or null.
String? tagCodeFromChipUri(String raw, {required String siteUrl}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  final site = Uri.tryParse(siteUrl);
  final isSite = site != null && site.host.isNotEmpty && uri.scheme == site.scheme && uri.host == site.host && uri.port == site.port;
  if (!isSite && (uri.scheme != 'https' || uri.port != 443)) return null;
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments[0] != 't') return null;
  final code = segments[1].toUpperCase();
  return code.length == tagCodeLength && isTagCode(code) && normalizeTagCode(code) == code ? code : null;
}

/// The link written into a chip for [code] under [baseUrl] (the API's `PUBLIC_PROFILE_BASE_URL`).
String chipUrl(String baseUrl, String code) => '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/t/$code';

/* ------------------------------------------------------------ staff encoding (GET /v1/encode/:token) */

/// 32 random bytes, base64url (contracts `ENCODE_TOKEN`).
final encodeTokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

class EncodeCode {
  const EncodeCode(this.code, this.encodedAt);
  final String code;
  final DateTime? encodedAt;
  bool get encoded => encodedAt != null;
}

/// A staff encoding session for one batch: the URL base and its working codes, in print order.
class EncodeSession {
  const EncodeSession({required this.batch, required this.kind, required this.baseUrl, required this.expiresAt, required this.codes});

  final String batch;
  final TagKind kind;
  final String baseUrl;
  final DateTime expiresAt;
  final List<EncodeCode> codes;

  factory EncodeSession.fromJson(Map<String, dynamic> j) => EncodeSession(
        batch: j['batch'] as String,
        kind: TagKind.values.asNameMap()[j['kind']] ?? TagKind.medal,
        baseUrl: j['baseUrl'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
        codes: [
          for (final c in (j['codes'] as List? ?? const []))
            EncodeCode((c as Map)['code'] as String, DateTime.tryParse(c['encodedAt'] as String? ?? '')?.toLocal()),
        ],
      );

  int get total => codes.length;
  int get encoded => codes.where((c) => c.encoded).length;

  /// The first code not written yet (print order), or null when the batch is done.
  String? get next {
    for (final c in codes) {
      if (!c.encoded) return c.code;
    }
    return null;
  }

  bool contains(String code) => codes.any((c) => c.code == code);
  String urlFor(String code) => chipUrl(baseUrl, code);

  EncodeSession markEncoded(String code, DateTime at) => EncodeSession(
        batch: batch,
        kind: kind,
        baseUrl: baseUrl,
        expiresAt: expiresAt,
        codes: [for (final c in codes) c.code == code ? EncodeCode(c.code, at) : c],
      );
}
