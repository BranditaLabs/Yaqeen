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

  /// Sends items in order. Stops at the first offline error (keeps the rest);
  /// drops items the server rejects permanently (e.g. already completed).
  /// Returns the number of items removed from the queue.
  Future<int> flush(OutboxSender send) async {
    final queue = await items();
    var removed = 0;
    for (final item in queue) {
      try {
        await send(item);
        removed++;
      } on ApiException catch (e) {
        if (!e.isPermanent) break;
        removed++;
      } on OfflineException {
        break;
      }
    }
    if (removed > 0) await _save(queue.sublist(removed));
    return removed;
  }
}
