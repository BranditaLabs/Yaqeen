enum RewardKind { fixedAmount, percentage, freeShipping }

class Reward {
  const Reward({
    required this.id,
    required this.titleAr,
    this.titleEn = '',
    required this.kind,
    required this.value,
    required this.costPoints,
    required this.available,
  });

  final String id;
  final String titleAr;
  final String titleEn;
  final RewardKind kind;
  final num value;
  final int costPoints;
  final bool available;

  String title(String locale) => locale == 'en' && titleEn.isNotEmpty ? titleEn : titleAr;

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
        id: j['id'] as String,
        titleAr: j['titleAr'] as String,
        titleEn: (j['titleEn'] as String?) ?? '',
        kind: switch (j['kind'] as String) {
          'percentage' => RewardKind.percentage,
          'free_shipping' => RewardKind.freeShipping,
          _ => RewardKind.fixedAmount,
        },
        value: j['value'] as num,
        costPoints: j['costPoints'] as int,
        available: j['available'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'kind': switch (kind) {
          RewardKind.percentage => 'percentage',
          RewardKind.freeShipping => 'free_shipping',
          RewardKind.fixedAmount => 'fixed_amount'
        },
        'value': value,
        'costPoints': costPoints,
        'available': available,
      };
}

enum RedemptionStatus { issued, used, expired, voided }

class Redemption {
  const Redemption({
    this.id = '',
    this.rewardId = '',
    required this.code,
    required this.expiresAt,
    this.balanceAfter = 0,
    this.status = RedemptionStatus.issued,
    this.costPoints = 0,
    this.createdAt,
  });

  final String id;
  final String rewardId;
  final String code;
  final DateTime expiresAt;
  final int balanceAfter;
  final RedemptionStatus status;
  final int costPoints;
  final DateTime? createdAt;

  bool isActive(DateTime now) => status == RedemptionStatus.issued && expiresAt.isAfter(now);

  factory Redemption.fromJson(Map<String, dynamic> j) => Redemption(
        id: (j['id'] as String?) ?? '',
        rewardId: (j['rewardId'] as String?) ?? '',
        code: j['code'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        balanceAfter: (j['balanceAfter'] as int?) ?? 0,
        status: switch (j['status'] as String?) {
          'used' => RedemptionStatus.used,
          'expired' => RedemptionStatus.expired,
          'void' => RedemptionStatus.voided,
          _ => RedemptionStatus.issued,
        },
        costPoints: (j['costPoints'] as int?) ?? 0,
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? ''),
      );
}

enum LedgerReason { task, bonus, milestone, grant, qada, redemption, adminAdjustment, reversal }

class LedgerEntry {
  const LedgerEntry({required this.id, required this.delta, required this.reason, required this.createdAt, this.note});

  final String id;
  final int delta;
  final LedgerReason reason;
  final DateTime createdAt;
  final String? note;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        delta: j['delta'] as int,
        reason: switch (j['reason'] as String) {
          'bonus' => LedgerReason.bonus,
          'milestone' => LedgerReason.milestone,
          'grant' => LedgerReason.grant,
          'qada' => LedgerReason.qada,
          'redemption' => LedgerReason.redemption,
          'admin_adjustment' => LedgerReason.adminAdjustment,
          'reversal' => LedgerReason.reversal,
          _ => LedgerReason.task,
        },
        createdAt: DateTime.parse(j['createdAt'] as String),
        note: j['note'] as String?,
      );
}

/// Error codes from `POST /v1/rewards/:id/redeem` (spec §5.23). UI maps each to its copy.
enum RedeemError { insufficientPoints, outOfStock, monthlyLimit, storeUnavailable, accountRequired, offline, unknown }

RedeemError redeemErrorFor(String code) => switch (code) {
      'insufficient_points' => RedeemError.insufficientPoints,
      'reward_out_of_stock' || 'reward_cap_reached' => RedeemError.outOfStock,
      'user_reward_limit_reached' => RedeemError.monthlyLimit,
      'shopify_unavailable' || 'shopify_not_configured' || 'shopify_upstream' || 'shopify_rejected' => RedeemError.storeUnavailable,
      'account_required' => RedeemError.accountRequired,
      _ => RedeemError.unknown,
    };

/// `STORE_URL/discount/<CODE>?redirect=/collections/all` + UTM (spec §6.12) — the code auto-applies.
Uri storeLinkFor(String storeUrl, String code) => Uri.parse(storeUrl).replace(
      path: '/discount/${Uri.encodeComponent(code)}',
      queryParameters: {'redirect': '/collections/all', 'utm_source': 'yaqeen_app', 'utm_medium': 'app', 'utm_campaign': 'rewards'},
    );
