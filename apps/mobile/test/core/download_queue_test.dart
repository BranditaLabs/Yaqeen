import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/network/download_queue.dart';
import 'package:yaqeen/core/network/resumable_download.dart';

void main() {
  test('runs at most maxConcurrent jobs at once and drains the rest', () async {
    final q = DownloadQueue(maxConcurrent: 3);
    var live = 0;
    var peak = 0;
    final gates = List.generate(7, (_) => Completer<void>());
    final done = [
      for (var i = 0; i < 7; i++)
        q.add(
          'k$i',
          group: 'g',
          run: (_, __) async {
            live++;
            peak = live > peak ? live : peak;
            await gates[i].future;
            live--;
            return i;
          },
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(q.running, 3);
    expect(q.waiting, 4);
    for (final g in gates) {
      g.complete();
      await Future<void>.delayed(Duration.zero);
    }
    expect(await Future.wait(done), [0, 1, 2, 3, 4, 5, 6]);
    expect(peak, 3);
    expect(q.running + q.waiting, 0);
  });

  test('the same key joins the running job instead of downloading twice', () async {
    final q = DownloadQueue();
    var runs = 0;
    final gate = Completer<void>();
    Future<int> job(CancelToken _, ProgressFn __) async {
      runs++;
      await gate.future;
      return 1;
    }

    final a = q.add('same', group: 'g', run: job);
    final b = q.add('same', group: 'g', run: job);
    gate.complete();
    expect(await Future.wait([a, b]), [1, 1]);
    expect(runs, 1);
  });

  test('cancelGroup stops queued and running jobs of that group only', () async {
    final q = DownloadQueue(maxConcurrent: 1);
    final other = Completer<void>();
    Future<String> waitUntilCancelled(CancelToken c, ProgressFn _) async {
      while (!c.isCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw const DownloadCancelled();
    }

    final running = q.add('r1', group: 'reciter', run: waitUntilCancelled);
    final queued = q.add('r2', group: 'reciter', run: waitUntilCancelled);
    final keep = q.add(
      'p1',
      group: 'packs',
      run: (_, __) async {
        await other.future;
        return 'pack';
      },
    );
    await Future<void>.delayed(Duration.zero);
    final cancelled = Future.wait([
      expectLater(running, throwsA(isA<DownloadCancelled>())),
      expectLater(queued, throwsA(isA<DownloadCancelled>())),
    ]);
    q.cancelGroup('reciter');
    await cancelled;
    other.complete();
    expect(await keep, 'pack');
  });

  test('progress reaches every listener of a job', () async {
    final q = DownloadQueue();
    final seen = <int>[];
    final joined = <int>[];
    final gate = Completer<void>();
    final a = q.add(
      'k',
      group: 'g',
      onProgress: (r, _) => seen.add(r),
      run: (_, p) async {
        await gate.future;
        p(10, 100);
        p(100, 100);
        return 0;
      },
    );
    final b = q.add('k', group: 'g', onProgress: (r, _) => joined.add(r), run: (_, __) async => 0);
    gate.complete();
    await Future.wait([a, b]);
    expect(seen, [10, 100]);
    expect(joined, [10, 100]);
  });
}
