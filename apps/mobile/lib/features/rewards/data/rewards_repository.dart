import '../../../core/network/api_client.dart';
import '../domain/reward.dart';

/// Redemption is online-only by design: it spends points and creates a Shopify code.
class RewardsRepository {
  RewardsRepository(this.api);
  final ApiClient api;

  Future<List<Reward>> list() async {
    final list = await api.get('/v1/rewards') as List;
    return list.map((e) => Reward.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<Redemption> redeem(String rewardId) async =>
      Redemption.fromJson((await api.post('/v1/rewards/$rewardId/redeem') as Map).cast<String, dynamic>());
}
