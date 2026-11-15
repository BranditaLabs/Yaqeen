/// Levels (contracts `LEVELS` / `levelFor`, APP_SPEC §5.26): six steps on **lifetime earned** points
/// (task, qada, bonus, milestone, grant and positive admin adjustments — reversals excluded), so
/// spending points never lowers a level. The caller's own level is live; every public ring uses the
/// nightly snapshot. Parity with the contracts is tested against `test/fixtures/community/constants.json`.
class CardLevel {
  const CardLevel({required this.level, required this.nameAr, required this.nameEn, required this.progress, this.nextAt});
  final int level;
  final String nameAr;
  final String nameEn;

  /// 0…1 toward the next level (1 at the top).
  final double progress;

  /// Lifetime points needed for the next level; null at the top.
  final int? nextAt;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;

  /// The top level («منارة») — the only level whose ring is gold.
  bool get isTop => level >= cardLevels.length;

  factory CardLevel.fromJson(Map<String, dynamic> j) => CardLevel(
        level: (j['level'] as num).toInt(),
        nameAr: j['nameAr'] as String,
        nameEn: j['nameEn'] as String,
        progress: (j['progress'] as num).toDouble(),
        nextAt: (j['nextAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {'level': level, 'nameAr': nameAr, 'nameEn': nameEn, 'progress': progress, 'nextAt': nextAt};

  @override
  bool operator ==(Object other) =>
      other is CardLevel &&
      other.level == level &&
      other.nameAr == nameAr &&
      other.nameEn == nameEn &&
      other.progress == progress &&
      other.nextAt == nextAt;

  @override
  int get hashCode => Object.hash(level, nameAr, nameEn, progress, nextAt);
}

/// Mirrors `LEVELS` in contracts: (minimum lifetime points, Arabic name, English name).
const cardLevels = [
  (0, 'بداية الطريق', 'Setting out'),
  (500, 'على الطريق', 'On the path'),
  (2000, 'مواظب', 'Steadfast'),
  (5000, 'ثابت', 'Unwavering'),
  (12000, 'راسخ', 'Rooted'),
  (25000, 'منارة', 'Beacon'),
];

CardLevel levelFor(int lifetimePoints) {
  final pts = lifetimePoints < 0 ? 0 : lifetimePoints;
  var i = 0;
  while (i + 1 < cardLevels.length && pts >= cardLevels[i + 1].$1) {
    i++;
  }
  final cur = cardLevels[i];
  final next = i + 1 < cardLevels.length ? cardLevels[i + 1] : null;
  return CardLevel(
    level: i + 1,
    nameAr: cur.$2,
    nameEn: cur.$3,
    progress: next == null ? 1 : (pts - cur.$1) / (next.$1 - cur.$1),
    nextAt: next?.$1,
  );
}
