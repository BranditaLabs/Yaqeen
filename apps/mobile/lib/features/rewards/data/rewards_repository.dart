import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/reward.dart';

/// Redemption is online-only by design: it spends points and creates a Shopify code.
/// The catalogue and «أكوادي» are cached so they can still be *seen* offline.
class RewardsRepository {
  RewardsRepository(this.api, {required this.cache});
  final ApiClient api;
  final KvStore cache;

  Future<List<Reward>> list() async {
    try {
      final list = await api.get('/v1/rewards') as List;
      await cache.write('cache.rewards', jsonEncode(list));
      return list.map((e) => Reward.fromJson((e as Map).cast<String, dynamic>())).toList();
    } on OfflineException {
      final raw = await cache.read('cache.rewards');
      if (raw == null) rethrow;
      return (jsonDecode(raw) as List).map((e) => Reward.fromJson((e as Map).cast<String, dynamic>())).toList();
    }
  }

  /// Same key for retries of one confirm tap (the API is also rate-limited per user).
  Future<Redemption> redeem(String rewardId) async =>
      Redemption.fromJson((await api.post('/v1/rewards/$rewardId/redeem') as Map).cast<String, dynamic>());

  Future<List<Redemption>> codes() async {
    try {
      final list = await api.get('/v1/me/redemptions') as List;
      await cache.write('cache.redemptions', jsonEncode(list));
      return list.map((e) => Redemption.fromJson((e as Map).cast<String, dynamic>())).toList();
    } on OfflineException {
      final raw = await cache.read('cache.redemptions');
      if (raw == null) rethrow;
      return (jsonDecode(raw) as List).map((e) => Redemption.fromJson((e as Map).cast<String, dynamic>())).toList();
    }
  }

  Future<List<LedgerEntry>> ledger() async {
    final list = await api.get('/v1/me/ledger') as List;
    return list.map((e) => LedgerEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }
}
