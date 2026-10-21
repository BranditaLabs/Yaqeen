import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/offline/outbox.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

void main() {
  OutboxItem item(String id) => OutboxItem(id: id, method: 'POST', path: '/v1/x', body: {'clientEventId': id});

  test('persists and replays in order', () async {
    final box = Outbox(MemoryKvStore());
    await box.add(item('a'));
    await box.add(item('b'));
    final sent = <String>[];
    expect(await box.flush((i) async => sent.add(i.id)), 2);
    expect(sent, ['a', 'b']);
    expect(await box.items(), isEmpty);
  });

  test('stops when offline and keeps the rest', () async {
    final box = Outbox(MemoryKvStore());
    for (final id in ['a', 'b', 'c']) {
      await box.add(item(id));
    }
    var calls = 0;
    final removed = await box.flush((i) async {
      if (++calls == 2) throw const OfflineException();
    });
    expect(removed, 1);
    expect((await box.items()).map((e) => e.id), ['b', 'c']);
  });

  test('drops permanently rejected items, keeps retryable ones', () async {
    final box = Outbox(MemoryKvStore());
    await box.add(item('dup'));
    await box.add(item('rate'));
    await box.flush((i) async {
      if (i.id == 'dup') throw ApiException(400, 'already_completed');
      throw ApiException(429, 'rate_limited');
    });
    expect((await box.items()).map((e) => e.id), ['rate']);
  });

  test('event ids are 32 hex chars and unique', () {
    final ids = List.generate(100, (_) => Outbox.newEventId());
    expect(ids.toSet().length, 100);
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id)), isTrue);
  });
}
