import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/resumable_download.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('yq_dl'));
  tearDown(() async => tmp.delete(recursive: true));

  /// A server that sends [first] bytes, then nothing more (a stalled connection).
  http.Client stalling(List<int> first, {StreamController<List<int>>? body}) => MockClient.streaming((req, _) async {
        final c = body ?? StreamController<List<int>>();
        c.add(first);
        return http.StreamedResponse(c.stream, 200, contentLength: 1000);
      });

  test('a stalled body fails after the idle timeout; the partial file stays', () async {
    final target = File('${tmp.path}/a.mp3');
    await expectLater(
      downloadResumable(
        stalling(List.filled(100, 1)),
        Uri.parse('https://cdn.test/a.mp3'),
        target,
        idleTimeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').length(), 100);
  });

  test('a server that never answers fails after the connect timeout', () async {
    final never = MockClient.streaming((_, __) => Completer<http.StreamedResponse>().future);
    await expectLater(
      downloadResumable(
        never,
        Uri.parse('https://cdn.test/b.mp3'),
        File('${tmp.path}/b.mp3'),
        connectTimeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('cancel stops a stalled download at once, through a linked token too', () async {
    final caller = CancelToken();
    final body = StreamController<List<int>>();
    final run = downloadResumable(
      stalling(List.filled(100, 1), body: body),
      Uri.parse('https://cdn.test/c.mp3'),
      File('${tmp.path}/c.mp3'),
      cancel: LinkedCancelToken(caller, CancelToken()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final started = DateTime.now();
    caller.cancel();
    await expectLater(run, throwsA(isA<DownloadCancelled>()));
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 1)));
    expect(body.hasListener, isFalse); // the connection was dropped
  });

  test('cancel while waiting for the server answers DownloadCancelled', () async {
    final token = CancelToken();
    final never = MockClient.streaming((_, __) => Completer<http.StreamedResponse>().future);
    final run = downloadResumable(never, Uri.parse('https://cdn.test/d.mp3'), File('${tmp.path}/d.mp3'), cancel: token);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    await expectLater(run, throwsA(isA<DownloadCancelled>()));
  });
}
