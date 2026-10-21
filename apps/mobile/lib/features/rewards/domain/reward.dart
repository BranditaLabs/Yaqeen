enum RewardKind { fixedAmount, percentage, freeShipping }

class Reward {
  const Reward({required this.id, required this.titleAr, required this.kind, required this.value, required this.costPoints, required this.available});

  final String id;
  final String titleAr;
  final RewardKind kind;
  final num value;
  final int costPoints;
  final bool available;

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
        id: j['id'] as String,
        titleAr: j['titleAr'] as String,
        kind: switch (j['kind'] as String) {
          'percentage' => RewardKind.percentage,
          'free_shipping' => RewardKind.freeShipping,
          _ => RewardKind.fixedAmount,
        },
        value: j['value'] as num,
        costPoints: j['costPoints'] as int,
        available: j['available'] as bool,
      );
}

class Redemption {
  const Redemption({required this.code, required this.expiresAt, required this.balanceAfter});
  final String code;
  final DateTime expiresAt;
  final int balanceAfter;

  factory Redemption.fromJson(Map<String, dynamic> j) => Redemption(
        code: j['code'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        balanceAfter: j['balanceAfter'] as int,
      );
}
