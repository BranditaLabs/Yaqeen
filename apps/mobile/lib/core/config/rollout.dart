import 'dart:convert';

/// Stable percentage rollout — mirror of packages/contracts/src/rollout.ts (FNV-1a over
/// `flag:userId`, mod 100). Keep the shared test vectors in sync.
int rolloutBucket(String userId, String flag) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode('$flag:$userId')) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h % 100;
}

bool inRollout(String? userId, String flag, int? percent) {
  if (percent == null || percent >= 100) return true;
  if (percent <= 0 || userId == null) return false;
  return rolloutBucket(userId, flag) < percent;
}

/// `1.10.0` > `1.9.3`. Non-numeric parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
