import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/features/challenge/domain/challenge_models.dart';
import 'package:yaqeen/features/challenge/presentation/challenge_controller.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';

Map<String, Object?> summaryFor(String date, int n, List<String> done) => {
      'enrolled': true,
      'startedOn': '2026-09-04',
      'dayNumber': n,
      'streak': 3,
      'balance': 500,
      'challengeLengthDays': 365,
      'today': {'date': date, 'dayNumber': n, 'status': 'today', 'points': 0, 'completedTasks': done, 'bonuses': <String>[]},
      'tasks': [
        {'key': 'five_prayers', 'labelAr': 'الصلوات الخمس', 'labelEn': 'Five prayers', 'points': 25},
        {'key': 'daily_task', 'labelAr': 'مهمة اليوم', 'labelEn': 'Daily task', 'points': 25},
      ],
    };

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUpAll(Zoned.ensureInitialized);

  // Cairo is on summer time (UTC+3) until the last Thursday of October 2026.
  late DateTime now;
  late bool online;
  late List<http.Request> sent;

  Future<ProviderContainer> container(MemoryKvStore kv) async {
    final secure = MemoryKvStore();
    await secure.write('auth.access', 'token');
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(secure),
        clockProvider.overrideWithValue(() => now),
        initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.google, userId: 'u1')),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            baseUrl: 'https://api.test',
            tokens: ref.watch(tokenStoreProvider),
            client: MockClient((req) async {
              if (!online) throw http.ClientException('offline');
              sent.add(req);
              if (req.url.path == '/v1/challenge/summary') {
                // The server's today follows the clock (Cairo).
                final d = Zoned.isoDate(Zoned.today('Africa/Cairo', now));
                return json(summaryFor(d, d == '2026-10-20' ? 47 : 46, []));
              }
              return json({'ok': true});
            }),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    online = true;
    sent = [];
  });

  test('a tick after local midnight goes to the new day, not yesterday (no accidental qada)', () async {
    now = DateTime.utc(2026, 10, 19, 20, 50); // 23:50 in Cairo on the 19th
    final c = await container(MemoryKvStore());
    final s = await c.read(challengeControllerProvider.future);
    expect(s.today!.date, '2026-10-19');

    now = DateTime.utc(2026, 10, 19, 21, 10); // 00:10 on the 20th — the summary in memory is stale
    await c.read(challengeControllerProvider.notifier).complete(TaskKey.fivePrayers);
    final tick = sent.lastWhere((r) => r.url.path.endsWith('/five_prayers/complete'));
    expect((jsonDecode(tick.body) as Map)['date'], '2026-10-20');
    expect(c.read(challengeControllerProvider).valueOrNull!.today!.date, '2026-10-20');
  });

  test('offline after midnight: the cached summary starts the new day empty and the tick keeps today', () async {
    final kv = MemoryKvStore();
    await kv.write('cache.challenge.summary', jsonEncode(summaryFor('2026-10-19', 46, ['five_prayers'])));
    online = false;
    now = DateTime.utc(2026, 10, 20, 7); // 10:00 on the 20th
    final c = await container(kv);
    final s = await c.read(challengeControllerProvider.future);
    expect(s.today!.date, '2026-10-20');
    expect(s.today!.completed, isEmpty); // yesterday's tick isn't shown as today's

    await c.read(challengeControllerProvider.notifier).complete(TaskKey.fivePrayers);
    final queued = await c.read(outboxProvider).items();
    expect(queued.single.path, '/v1/challenge/tasks/five_prayers/complete');
    expect(queued.single.body!['date'], '2026-10-20');
    expect(c.read(challengeControllerProvider).valueOrNull!.today!.completed, {TaskKey.fivePrayers});
  });

  test('refreshIfNewDay refetches only when the day changed', () async {
    now = DateTime.utc(2026, 10, 19, 20, 50);
    final c = await container(MemoryKvStore());
    final sub = c.listen(challengeControllerProvider, (_, __) {});
    addTearDown(sub.close);
    await c.read(challengeControllerProvider.future);
    final before = sent.where((r) => r.url.path == '/v1/challenge/summary').length;

    c.read(challengeControllerProvider.notifier).refreshIfNewDay();
    await c.read(challengeControllerProvider.future);
    expect(sent.where((r) => r.url.path == '/v1/challenge/summary').length, before);

    now = DateTime.utc(2026, 10, 19, 21, 10);
    c.read(challengeControllerProvider.notifier).refreshIfNewDay();
    final s = await c.read(challengeControllerProvider.future);
    expect(s.today!.date, '2026-10-20');
  });
}
