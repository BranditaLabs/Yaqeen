import '../../../core/storage/local_store.dart';
import '../domain/inbox_item.dart';

class InboxRepository {
  InboxRepository(this.store, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final LocalStore store;
  final DateTime Function() _now;

  Future<List<InboxItem>> all() async =>
      pruneInbox((await store.readList('inbox')).map((e) => InboxItem.fromJson((e as Map).cast<String, dynamic>())), _now());

  Future<void> _save(List<InboxItem> items) => store.write('inbox', pruneInbox(items, _now()).map((i) => i.toJson()).toList());

  /// Adds new items (same id = already there, kept as is).
  Future<void> addAll(Iterable<InboxItem> items) async {
    final current = await all();
    final ids = current.map((i) => i.id).toSet();
    await _save([...current, ...items.where((i) => !ids.contains(i.id))]);
  }

  Future<void> markRead(String id) async => _save([for (final i in await all()) i.id == id ? i.markRead() : i]);

  Future<void> markAllRead() async => _save([for (final i in await all()) i.markRead()]);

  Future<int> unread() async => (await all()).where((i) => !i.read).length;
}
