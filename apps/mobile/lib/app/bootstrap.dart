import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Start-up that cannot hang on the native splash (the splash stays until Flutter's first frame).
///
/// Everything before `runApp` goes through [step]: concurrent, time-boxed, and falling back to a
/// safe default when a plugin throws or never answers. Plugin set-up that the first frame doesn't
/// need runs [afterFirstFrame]. Every failure is logged as `YQ-BOOT …` so logcat / Console show it
/// in release builds (CI `mobile-smoke` waits for `YQ-BOOT first-frame`).
abstract final class Boot {
  static const timeout = Duration(seconds: 3);

  static void log(String message) => debugPrint('YQ-BOOT $message');

  /// Runs [run] with a [limit]; on error or timeout logs it and returns [fallback].
  static Future<T> step<T>(String name, Future<T> Function() run, T fallback, {Duration limit = timeout}) async {
    try {
      return await run().timeout(limit);
    } catch (e, st) {
      log('$name failed: $e\n$st');
      return fallback;
    }
  }

  /// Fire-and-forget work after the first frame; each task is isolated so one failure stops nothing.
  static void afterFirstFrame(Map<String, Future<void> Function()> tasks) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      log('first-frame');
      for (final t in tasks.entries) {
        unawaited(step(t.key, t.value, null, limit: const Duration(seconds: 20)));
      }
    });
  }

  /// Routes every uncaught error to the log instead of dying silently.
  static void guard(void Function() body) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      log('flutter error: ${details.exceptionAsString()}\n${details.stack}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('uncaught: $error\n$stack');
      return true;
    };
    runZonedGuarded(body, (error, stack) => log('uncaught (zone): $error\n$stack'));
  }
}
