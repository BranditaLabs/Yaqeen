import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env.dart';
import 'error_reporter.dart';

/// Sentry for crashes and errors (Dart, Android, iOS). Off unless built with `--dart-define=SENTRY_DSN=…`.
/// Obfuscated release builds are symbolicated from the debug symbols CI uploads (release-mobile.yml).
class SentryErrorReporter extends BufferedErrorReporter {
  @override
  Future<bool> startSdk() async {
    if (Env.sentryDsn.isEmpty) return false;
    // Same release name the CI symbol upload uses (release-mobile.yml): yaqeen@<version>+<build>.
    final info = await PackageInfo.fromPlatform();
    await SentryFlutter.init((o) {
      o
        ..dsn = Env.sentryDsn
        ..release = 'yaqeen@${info.version}+${info.buildNumber}'
        ..dist = info.buildNumber
        ..environment = Env.flavor
        ..sendDefaultPii = false
        ..tracesSampleRate = 0
        ..enableAutoPerformanceTracing = false
        ..enableUserInteractionBreadcrumbs = false
        ..enableUserInteractionTracing = false
        ..enableAutoNativeBreadcrumbs = false
        ..attachScreenshot = false
        ..attachViewHierarchy = false
        ..reportPackages = false
        ..maxBreadcrumbs = 20
        ..beforeBreadcrumb = keepBreadcrumb
        ..beforeSend = (event, hint) => scrubEvent(event);
    });
    return true;
  }

  @override
  void send(Object error, StackTrace? stack, String where, bool fatal) {
    Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        scope.setTag('where', where);
        if (fatal) scope.level = SentryLevel.fatal;
      },
    );
  }
}

/// Only our own boot breadcrumbs survive: navigation, taps and HTTP URLs could reveal worship use.
Breadcrumb? keepBreadcrumb(Breadcrumb? b, Hint hint) => b?.category == 'yq.boot' ? b : null;

SentryEvent scrubEvent(SentryEvent event) {
  event.user = null;
  event.request = null;
  event.breadcrumbs = event.breadcrumbs?.where((b) => b.category == 'yq.boot').toList();
  return event;
}
