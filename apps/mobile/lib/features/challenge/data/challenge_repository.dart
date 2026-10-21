import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/challenge_models.dart';

/// Offline-first: reads fall back to the last cached summary; writes go through the
/// outbox so a completion made without network is never lost or double-counted.
class ChallengeRepository {
  ChallengeRepository({required this.api, required this.outbox, required this.cache});

  final ApiClient api;
  final Outbox outbox;
  final KvStore cache;
  static const _cacheKey = 'cache.challenge.summary';

  Future<ChallengeSummary> summary() async {
    await syncPending();
    try {
      final json = (await api.get('/v1/challenge/summary') as Map).cast<String, dynamic>();
      await cache.write(_cacheKey, jsonEncode(json));
      return ChallengeSummary.fromJson(json);
    } on OfflineException {
      final cached = await cache.read(_cacheKey);
      if (cached == null) rethrow;
      var s = ChallengeSummary.fromJson((jsonDecode(cached) as Map).cast<String, dynamic>());
      // Re-apply completions still waiting in the outbox.
      for (final item in await outbox.items()) {
        final m = RegExp(r'/v1/challenge/tasks/(\w+)/complete').firstMatch(item.path);
        if (m != null && item.body?['date'] == s.today?.date) s = s.completeLocally(TaskKey.fromWire(m.group(1)!));
      }
      return s;
    }
  }

  Future<void> enroll() => api.post('/v1/challenge/enroll');

  Future<List<ChallengeDay>> days(String from, String to) async {
    final list = await api.get('/v1/challenge/days', query: {'from': from, 'to': to}) as List;
    return list.map((e) => ChallengeDay.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Queues the completion, then tries to send immediately.
  Future<void> complete(TaskKey task, String date) async {
    final id = Outbox.newEventId();
    await outbox.add(OutboxItem(
      id: id,
      method: 'POST',
      path: '/v1/challenge/tasks/${task.wire}/complete',
      body: {'date': date, 'clientEventId': id},
    ),);
    await syncPending();
  }

  Future<int> syncPending() => outbox.flush((item) async {
        if (item.method == 'POST') await api.post(item.path, item.body);
      });
}
