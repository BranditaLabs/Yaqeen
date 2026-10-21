import 'dart:io';

import 'package:http/http.dart' as http;

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class WifiRequired implements Exception {
  const WifiRequired();
}

/// Cooperative cancellation for a running download.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Downloads [uri] into [target], resuming a previous `<target>.part` with an HTTP Range request.
/// The finished file only appears at [target] once complete (rename), so a half file is never read.
Future<File> downloadResumable(
  http.Client client,
  Uri uri,
  File target, {
  CancelToken? cancel,
  void Function(int received, int? total)? onProgress,
}) async {
  await target.parent.create(recursive: true);
  final part = File('${target.path}.part');
  var have = await part.exists() ? await part.length() : 0;

  final req = http.Request('GET', uri);
  if (have > 0) req.headers['Range'] = 'bytes=$have-';
  final res = await client.send(req);
  if (res.statusCode == 416) {
    // Server says the range is past the end — the partial file is complete.
    await part.rename(target.path);
    return target;
  }
  if (res.statusCode != 200 && res.statusCode != 206) {
    throw HttpException('download ${res.statusCode}', uri: uri);
  }
  if (res.statusCode == 200) have = 0; // server ignored the range — start over
  final total = res.contentLength == null ? null : res.contentLength! + have;
  final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
  var received = have;
  try {
    await for (final chunk in res.stream) {
      if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
  if (total != null && received < total) throw HttpException('download truncated', uri: uri);
  if (await target.exists()) await target.delete();
  await part.rename(target.path);
  return target;
}
