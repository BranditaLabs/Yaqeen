import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class WifiRequired implements Exception {
  const WifiRequired();
}

/// Cancellation for a running download. A running [downloadResumable] listens ([onCancel]) and
/// drops its connection at once, instead of waiting for the next chunk to arrive.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in [..._listeners]) {
      l();
    }
    _listeners.clear();
  }

  /// Calls [f] once when this token is cancelled (at once if it already is). Returns a function
  /// that unregisters it.
  void Function() onCancel(void Function() f) {
    if (isCancelled) {
      f();
      return () {};
    }
    _listeners.add(f);
    return () => _listeners.remove(f);
  }
}

/// Cancelled when either of two tokens is (e.g. the caller's and the download queue's).
class LinkedCancelToken extends CancelToken {
  LinkedCancelToken(this._a, this._b);
  final CancelToken? _a;
  final CancelToken _b;
  @override
  bool get isCancelled => super.isCancelled || (_a?.isCancelled ?? false) || _b.isCancelled;

  @override
  void Function() onCancel(void Function() f) {
    var fired = false;
    void once() {
      if (fired) return;
      fired = true;
      f();
    }

    final offs = [super.onCancel(once), if (_a != null) _a.onCancel(once), _b.onCancel(once)];
    return () {
      for (final off in offs) {
        off();
      }
    };
  }
}

/// How long to wait for the server to answer, and for the next chunk once bytes flow. A stalled
/// connection fails (and frees its queue slot) instead of hanging until the OS drops it.
const downloadConnectTimeout = Duration(seconds: 20);
const downloadIdleTimeout = Duration(seconds: 30);

/// Downloads [uri] into [target], resuming a previous `<target>.part` with an HTTP Range request.
/// The finished file only appears at [target] once complete (rename), so a half file is never read.
Future<File> downloadResumable(
  http.Client client,
  Uri uri,
  File target, {
  CancelToken? cancel,
  void Function(int received, int? total)? onProgress,
  Duration connectTimeout = downloadConnectTimeout,
  Duration idleTimeout = downloadIdleTimeout,
}) async {
  if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
  await target.parent.create(recursive: true);
  final part = File('${target.path}.part');
  var have = await part.exists() ? await part.length() : 0;

  final req = http.Request('GET', uri);
  if (have > 0) req.headers['Range'] = 'bytes=$have-';
  final res = await _unlessCancelled(client.send(req).timeout(connectTimeout), cancel);
  if (res.statusCode == 416) {
    // Server says the range is past the end — the partial file is complete.
    await part.rename(target.path);
    return target;
  }
  if (res.statusCode != 200 && res.statusCode != 206) {
    res.stream.listen(null).cancel().ignore();
    throw HttpException('download ${res.statusCode}', uri: uri);
  }
  if (res.statusCode == 200) have = 0; // server ignored the range — start over
  final total = res.contentLength == null ? null : res.contentLength! + have;
  final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
  var received = have;
  final done = Completer<void>();
  final sub = res.stream.timeout(idleTimeout).listen(
    (chunk) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  // Cancelling the subscription closes the connection; the partial file stays for the next try.
  final off = cancel?.onCancel(() {
    sub.cancel().ignore();
    if (!done.isCompleted) done.completeError(const DownloadCancelled());
  });
  try {
    await done.future;
  } finally {
    off?.call();
    await sink.flush();
    await sink.close();
  }
  if (total != null && received < total) throw HttpException('download truncated', uri: uri);
  if (await target.exists()) await target.delete();
  await part.rename(target.path);
  return target;
}

/// [f], or [DownloadCancelled] as soon as [cancel] fires (a late response is drained and dropped).
Future<http.StreamedResponse> _unlessCancelled(Future<http.StreamedResponse> f, CancelToken? cancel) {
  if (cancel == null) return f;
  final out = Completer<http.StreamedResponse>();
  final off = cancel.onCancel(() {
    if (!out.isCompleted) out.completeError(const DownloadCancelled());
  });
  f.then(
    (r) {
      off();
      if (out.isCompleted) {
        r.stream.listen(null).cancel().ignore();
      } else {
        out.complete(r);
      }
    },
    onError: (Object e, StackTrace s) {
      off();
      if (!out.isCompleted) out.completeError(e, s);
    },
  );
  return out.future;
}
