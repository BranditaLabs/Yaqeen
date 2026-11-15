import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/notifications/push_spool.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/features/notifications/data/inbox_repository.dart';
import 'package:yaqeen/features/notifications/domain/inbox_item.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 9);

  PushMessage push(String id, {String? link, String? category}) =>
      PushMessage(id: id, title: 'عرض', body: 'خصم', at: now, link: link, campaignId: 'c1', category: category);

  test('an FCM message becomes a push: notification first, data as fallback, nothing to show → null', () {
    final m = PushMessage.from(
      messageId: 'm1',
      title: 'Title',
      body: 'Body',
      sentTime: now,
      data: {'link': 'yaqeen://redeem', 'campaignId': 'c9'},
      now: now,
    )!;
    expect((m.id, m.title, m.body, m.link, m.campaignId, m.category), ('m1', 'Title', 'Body', 'yaqeen://redeem', 'c9', null));
    final fromData = PushMessage.from(data: {'title': 'T', 'body': 'B', 'category': 'challenge'}, now: now)!;
    expect(fromData.title, 'T');
    expect(fromData.category, 'challenge');
    expect(fromData.id, isNotEmpty);
    expect(PushMessage.from(data: {'link': 'yaqeen://home'}, now: now), isNull);
  });

  test('pushes file under challenge or offers — never worship', () {
    expect(inboxItemForPush(push('a', link: 'yaqeen://challenge')).category, InboxCategory.challenge);
    expect(inboxItemForPush(push('b', link: 'https://yaqeenarabia.com/app/calendar')).category, InboxCategory.challenge);
    expect(inboxItemForPush(push('c', link: 'yaqeen://redeem')).category, InboxCategory.offers);
    expect(inboxItemForPush(push('d')).category, InboxCategory.offers);
    expect(inboxItemForPush(push('e', link: 'yaqeen://store', category: 'challenge')).category, InboxCategory.challenge);
    expect(inboxItemForPush(push('f', link: 'yaqeen://challenge', category: 'offers')).category, InboxCategory.offers);
    final item = inboxItemForPush(push('g', link: 'yaqeen://redeem'));
    expect((item.id, item.link, item.campaignId, item.read), ('push:g', 'yaqeen://redeem', 'c1', false));
  });

  test('the inbox keeps each push once', () async {
    final repo = InboxRepository(LocalStore(MemoryKvStore()), now: () => now);
    await repo.addPushes([push('a', link: 'yaqeen://challenge'), push('b')]);
    await repo.markRead('push:a');
    await repo.addPushes([push('a', link: 'yaqeen://challenge')]); // the tap of one already filed
    final all = await repo.all();
    expect(all.map((i) => i.id).toSet(), {'push:a', 'push:b'});
    expect(all.firstWhere((i) => i.id == 'push:a').read, isTrue);
    expect(await repo.unread(), 1);
  });

  test('background spool: appended pushes are taken once, torn lines skipped', () async {
    final dir = await Directory.systemTemp.createTemp('yq_spool');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/push_inbox.jsonl');
    final spool = PushSpool(() async => file);
    expect(await spool.take(), isEmpty);
    await spool.append(push('a', link: 'yaqeen://challenge'));
    await file.writeAsString('{"id": "torn', mode: FileMode.append);
    await file.writeAsString('\n', mode: FileMode.append);
    await spool.append(push('b'));
    final taken = await spool.take();
    expect(taken.map((m) => m.id), ['a', 'b']);
    expect(taken.first.link, 'yaqeen://challenge');
    expect(taken.first.at, now);
    expect(await spool.take(), isEmpty);
  });
}
