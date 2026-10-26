import 'dart:collection';

/// Crash and error reporting (Sentry), behind an interface so tests and dev builds run without it.
///
/// Privacy: reports carry no user, no request URLs or bodies, no navigation or tap breadcrumbs and no
/// screenshots — nothing about which prayers, azkar, surahs or tasks someone used. Only the error, its
/// stack, the app version and the device/OS.
abstract interface class ErrorReporter {
  /// Starts the SDK (after the first frame). Errors reported earlier are kept and sent then.
  Future<void> start();

  /// An uncaught error, or a caught one that should not happen. [where] is a fixed label
  /// (`boot:config`, `zone`), never user data.
  void report(Object error, StackTrace? stack, {required String where, bool fatal = false});
}

class NoopErrorReporter implements ErrorReporter {
  const NoopErrorReporter();
  @override
  Future<void> start() async {}
  @override
  void report(Object error, StackTrace? stack, {required String where, bool fatal = false}) {}
}

/// Holds errors that happen before [start] (boot) and replays them once the SDK is up.
abstract class BufferedErrorReporter implements ErrorReporter {
  static const maxBuffered = 20;
  final _early = Queue<(Object, StackTrace?, String, bool)>();
  bool _started = false;

  /// Starts the SDK; returns false when it is not configured (no DSN), so nothing is ever sent.
  Future<bool> startSdk();

  /// Sends one report through the started SDK.
  void send(Object error, StackTrace? stack, String where, bool fatal);

  @override
  Future<void> start() async {
    if (_started) return;
    _started = await startSdk();
    if (!_started) {
      _early.clear();
      return;
    }
    while (_early.isNotEmpty) {
      final (e, st, where, fatal) = _early.removeFirst();
      send(e, st, where, fatal);
    }
  }

  @override
  void report(Object error, StackTrace? stack, {required String where, bool fatal = false}) {
    if (_started) {
      send(error, stack, where, fatal);
    } else if (_early.length < maxBuffered) {
      _early.add((error, stack, where, fatal));
    }
  }
}
