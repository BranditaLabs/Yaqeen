import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/challenge_models.dart';

enum TickOutcome { synced, queued, rejected }

class TickResult {
  const TickResult(this.outcome, [this.code]);
  final TickOutcome outcome;

  /// API error code when rejected (`outside_qada_window`, `already_completed`, …).
  final String? code;
}

/// Offline-first: reads fall back to the last cached summary; writes go through the
/// outbox so a completion made without network is never lost or double-counted.
class ChallengeRepository {
  ChallengeRepository({required this.api, required this.outbox, required this.sync, required this.cache});

  final ApiClient api;
  final Outbox outbox;
  final OutboxSync sync;
  final KvStore cache;
  static const _cacheKey = 'cache.challenge.summary';
  static const _calendarPrefix = 'cache.challenge.calendar.';
  static const _calendarMonthsKey = 'cache.challenge.calendar.months';
  static final _taskPath = RegExp(r'^/v1/challenge/tasks/(\w+)/complete$');

  Future<List<String>> _cachedMonths() async {
    final raw = await cache.read(_calendarMonthsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// Forgets this account's summary and calendar months (sign-out, expired session): the next
  /// account on this phone never sees them, even offline.
  Future<void> clearCache() async {
    for (final month in await _cachedMonths()) {
      await cache.delete('$_calendarPrefix$month');
    }
    await cache.delete(_calendarMonthsKey);
    await cache.delete(_cacheKey);
  }

  Future<ChallengeSummary> summary() async {
    await sync.flush();
    try {
      final json = (await api.get('/v1/challenge/summary') as Map).cast<String, dynamic>();
      await cache.write(_cacheKey, jsonEncode(json));
      return await _withPending(ChallengeSummary.fromJson(json));
    } on OfflineException {
      final cached = await cachedSummary();
      if (cached == null) rethrow;
      return cached;
    }
  }

  /// Last known summary (+ ticks still in the outbox), for instant paint and offline use.
  Future<ChallengeSummary?> cachedSummary() async {
    final raw = await cache.read(_cacheKey);
    if (raw == null) return null;
    return _withPending(ChallengeSummary.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>()));
  }

  /// Re-applies completions still waiting in the outbox.
  Future<ChallengeSummary> _withPending(ChallengeSummary s) async {
    var out = s;
    for (final item in await outbox.items()) {
      final m = _taskPath.firstMatch(item.path);
      if (m != null && item.body?['date'] == out.today?.date) {
        final key = TaskKey.tryWire(m.group(1)!);
        if (key != null) out = out.completeLocally(key);
      }
    }
    return out;
  }

  Future<void> enroll() async {
    await api.post('/v1/challenge/enroll');
    await cache.delete(_cacheKey);
  }

  Future<List<ChallengeDay>> days(String from, String to) async {
    final list = await api.get('/v1/challenge/days', query: {'from': from, 'to': to}) as List;
    return list.map((e) => ChallengeDay.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Merged month (Hijri + statuses + special days), cached for offline (spec §5.21).
  Future<ChallengeCalendar> calendar(String month) async {
    final key = '$_calendarPrefix$month';
    try {
      final json = (await api.get('/v1/challenge/calendar', query: {'month': month}) as Map).cast<String, dynamic>();
      await cache.write(key, jsonEncode(json));
      final months = await _cachedMonths();
      if (!months.contains(month)) await cache.write(_calendarMonthsKey, jsonEncode([...months, month]));
      return ChallengeCalendar.fromJson(json);
    } on OfflineException {
      final raw = await cache.read(key);
      if (raw == null) rethrow;
      return ChallengeCalendar.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    }
  }

  /// Queues the completion with its own local [date] (offline ticks keep their day), then
  /// tries to send. Idempotent on the server via `clientEventId`.
  Future<TickResult> complete(TaskKey task, String date) async {
    final id = Outbox.newEventId();
    final path = '/v1/challenge/tasks/${task.wire}/complete';
    // A second tap before the first synced never queues a duplicate.
    final existing = await outbox.items();
    if (existing.any((i) => i.path == path && i.body?['date'] == date)) return const TickResult(TickOutcome.queued);
    await outbox.add(OutboxItem(id: id, method: 'POST', path: path, body: {'date': date, 'clientEventId': id}));

    String? rejectedCode;
    final sub = sync.rejected.listen((r) {
      if (r.$1.id == id) rejectedCode = r.$2.code;
    });
    try {
      await sync.flush(force: true);
    } finally {
      await sub.cancel();
    }
    if (rejectedCode != null) return TickResult(TickOutcome.rejected, rejectedCode);
    final stillQueued = (await outbox.items()).any((i) => i.id == id);
    return TickResult(stillQueued ? TickOutcome.queued : TickOutcome.synced);
  }

  /// Self-reported bonus for today (e.g. Ramadan's fast). Queued like a tick so it survives being
  /// offline; the server checks the day, the admin switch and once-per-day. Never queued twice.
  /// [date] is the place's today: a claim that only syncs on a later day is refused by the server.
  Future<void> claimBonus(String kindWire, String date) async {
    final path = '/v1/challenge/bonuses/$kindWire/claim';
    if ((await outbox.items()).any((i) => i.path == path && i.body?['date'] == date)) return;
    await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'POST', path: path, body: {'date': date}));
    await sync.flush(force: true);
    await cache.delete(_cacheKey); // the balance changed
  }

  Future<int> syncPending() => sync.flush();
}
