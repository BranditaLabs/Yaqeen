import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../network/api_client.dart';
import '../storage/kv_store.dart';

/// A write the user made while offline (or that failed). Replayed in order.
class OutboxItem {
  OutboxItem({required this.id, required this.method, required this.path, this.body, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  /// Also used as `clientEventId` so the API can de-duplicate replays.
  final String id;
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {'id': id, 'method': method, 'path': path, 'body': body, 'createdAt': createdAt.toIso8601String()};

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String,
        method: j['method'] as String,
        path: j['path'] as String,
        body: (j['body'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

typedef OutboxSender = Future<void> Function(OutboxItem item);

/// Persistent FIFO of pending writes. Worship tracking must work in airplane mode,
/// in the mosque, on the metro — the outbox makes that safe.
class Outbox {
  Outbox(this._store);

  final KvStore _store;
  static const _key = 'outbox.v1';
  static final _rand = Random.secure();

  static String newEventId() => List.generate(16, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  Future<List<OutboxItem>> items() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => OutboxItem.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> _save(List<OutboxItem> items) => _store.write(_key, jsonEncode(items.map((e) => e.toJson()).toList()));

  Future<void> add(OutboxItem item) async => _save([...await items(), item]);

  Future<void> removeWhere(bool Function(OutboxItem item) test) async => _save((await items()).where((i) => !test(i)).toList());

  Future<int> get length async => (await items()).length;

  /// Sends items in order. Stops at the first offline error (keeps the rest);
  /// drops items the server rejects permanently (e.g. already completed).
  /// Returns the number of items removed from the queue.
  Future<int> flush(OutboxSender send, {void Function(OutboxItem item, ApiException error)? onRejected}) async {
    final queue = await items();
    var removed = 0;
    for (final item in queue) {
      try {
        await send(item);
        removed++;
      } on ApiException catch (e) {
        if (!e.isPermanent) break;
        onRejected?.call(item, e);
        removed++;
      } on OfflineException {
        break;
      }
    }
    if (removed > 0) await _save(queue.sublist(removed));
    return removed;
  }
}

/// Sends any queued request through the API client. One flush for the whole app, so challenge
/// ticks, settings and inbox opens replay in the order they were made (spec §6.16).
class OutboxSync {
  OutboxSync({required this.api, required this.outbox, this.isSignedIn, DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final ApiClient api;
  final Outbox outbox;
  final DateTime Function() _now;
  final Random _random;

  /// Exponential backoff with full jitter after a failed flush (offline, 429, 5xx): 30 s → 15 min.
  /// Jitter keeps a fleet of phones from retrying in lockstep when the API recovers.
  static const baseDelay = Duration(seconds: 30);
  static const maxDelay = Duration(minutes: 15);
  int _failures = 0;
  DateTime? _retryAfter;

  DateTime? get retryAfter => _retryAfter;

  /// Requests need a session; skip the flush (keep the queue) while signed out.
  final Future<bool> Function()? isSignedIn;
  Future<int>? _running;
  final _rejected = StreamController<(OutboxItem, ApiException)>.broadcast();

  /// Items the server refused for good (e.g. `outside_qada_window`) — the UI reverts and explains.
  Stream<(OutboxItem, ApiException)> get rejected => _rejected.stream;

  /// Concurrent callers share one flush. [force] (a user action, connectivity back) ignores backoff.
  Future<int> flush({bool force = false}) => _running ??= _flush(force: force).whenComplete(() => _running = null);

  Future<int> _flush({required bool force}) async {
    if (isSignedIn != null && !await isSignedIn!()) return 0;
    if (!force && _retryAfter != null && _now().isBefore(_retryAfter!)) return 0;
    final sent = await _send();
    if (await outbox.length == 0) {
      _failures = 0;
      _retryAfter = null;
    } else {
      _failures++;
      final cap = baseDelay * pow(2, _failures - 1).toInt();
      final ceiling = cap > maxDelay ? maxDelay : cap;
      _retryAfter = _now().add(Duration(milliseconds: (_random.nextDouble() * ceiling.inMilliseconds).round()));
    }
    return sent;
  }

  Future<int> _send() {
    return outbox.flush(onRejected: (item, e) => _rejected.add((item, e)), (item) async {
      switch (item.method) {
        case 'POST':
          await api.post(item.path, item.body);
        case 'PUT':
          await api.put(item.path, item.body);
        case 'PATCH':
          await api.patch(item.path, item.body);
        case 'DELETE':
          await api.delete(item.path);
      }
    });
  }
}
