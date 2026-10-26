import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:yaqeen/core/platform/error_reporter.dart';
import 'package:yaqeen/core/platform/sentry_error_reporter.dart';

class _Fake extends BufferedErrorReporter {
  _Fake(this.configured);
  final bool configured;
  final sent = <String>[];
  @override
  Future<bool> startSdk() async => configured;
  @override
  void send(Object error, StackTrace? stack, String where, bool fatal) => sent.add('$where:$error');
}

void main() {
  test('errors before start are kept (bounded) and sent once the SDK is up', () async {
    final r = _Fake(true);
    for (var i = 0; i < BufferedErrorReporter.maxBuffered + 5; i++) {
      r.report('e$i', null, where: 'boot:config');
    }
    expect(r.sent, isEmpty);
    await r.start();
    expect(r.sent, hasLength(BufferedErrorReporter.maxBuffered));
    r.report('late', null, where: 'zone', fatal: true);
    expect(r.sent.last, 'zone:late');
  });

  test('without a DSN nothing is ever sent', () async {
    final r = _Fake(false);
    r.report('e', null, where: 'flutter');
    await r.start();
    r.report('e2', null, where: 'flutter');
    expect(r.sent, isEmpty);
  });

  test('reports carry no user, request or usage breadcrumbs', () {
    final event = SentryEvent(
      user: SentryUser(id: 'u1', email: 'a@b.c'),
      request: SentryRequest(url: 'https://api/v1/me/challenge/tasks/five_prayers'),
      breadcrumbs: [
        Breadcrumb(category: 'navigation', message: '/home/azkar'),
        Breadcrumb(category: 'yq.boot', message: 'config failed'),
      ],
    );
    final out = scrubEvent(event);
    expect(out.user, isNull);
    expect(out.request, isNull);
    expect(out.breadcrumbs!.map((b) => b.category), ['yq.boot']);
    expect(keepBreadcrumb(Breadcrumb(category: 'http', data: {'url': '/v1/me'}), Hint()), isNull);
  });
}
