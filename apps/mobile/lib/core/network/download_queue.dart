import 'dart:async';
import 'dart:collection';

import 'resumable_download.dart';

/// Byte progress of one running job.
typedef ProgressFn = void Function(int received, int? total);

/// One app-wide queue for every large download (recitation audio, content packs).
///
/// - At most [maxConcurrent] jobs run at once, across all groups, so the user's bandwidth is used
///   well without starving playback or the API.
/// - A job is keyed: adding a key that is already queued or running joins the existing job.
/// - Jobs belong to a group (a reciter id, `packs`) that can be cancelled at once.
/// - The queue outlives every screen (it sits in a keep-alive provider); leaving a screen never
///   cancels a download.
class DownloadQueue {
  DownloadQueue({this.maxConcurrent = 3});

  final int maxConcurrent;
  final _waiting = Queue<_Job>();
  final _running = <String, _Job>{};
  final _byKey = <String, _Job>{};

  int get running => _running.length;
  int get waiting => _waiting.length;

  /// Queues [run] under [key]. The future completes when the job finishes, or fails with its
  /// error (a cancelled job fails with [DownloadCancelled]).
  Future<T> add<T>(String key, {required String group, required Future<T> Function(CancelToken cancel, ProgressFn progress) run, ProgressFn? onProgress}) {
    final existing = _byKey[key];
    if (existing != null) {
      if (onProgress != null) existing.listeners.add(onProgress);
      return existing.done.future.then((v) => v as T);
    }
    final job = _Job(key, group, (c, p) async => run(c, p));
    if (onProgress != null) job.listeners.add(onProgress);
    _byKey[key] = job;
    _waiting.add(job);
    _pump();
    return job.done.future.then((v) => v as T);
  }

  /// Cancels every queued and running job of [group].
  void cancelGroup(String group) {
    for (final j in [..._waiting.where((j) => j.group == group)]) {
      _waiting.remove(j);
      _finish(j, error: const DownloadCancelled());
    }
    for (final j in _running.values.where((j) => j.group == group)) {
      j.token.cancel();
    }
  }

  void _pump() {
    while (_running.length < maxConcurrent && _waiting.isNotEmpty) {
      final job = _waiting.removeFirst();
      _running[job.key] = job;
      job.run(job.token, (r, t) {
        for (final l in job.listeners) {
          l(r, t);
        }
      }).then((v) => _finish(job, value: v), onError: (Object e) => _finish(job, error: e));
    }
  }

  void _finish(_Job job, {Object? value, Object? error}) {
    _running.remove(job.key);
    _byKey.remove(job.key);
    if (error != null) {
      job.done.completeError(error);
      // Nobody may be awaiting a cancelled job; don't surface it as an unhandled error.
      job.done.future.ignore();
    } else {
      job.done.complete(value);
    }
    _pump();
  }
}

class _Job {
  _Job(this.key, this.group, this.run);
  final String key;
  final String group;
  final Future<Object?> Function(CancelToken cancel, ProgressFn progress) run;
  final token = CancelToken();
  final listeners = <ProgressFn>[];
  final done = Completer<Object?>();
}
