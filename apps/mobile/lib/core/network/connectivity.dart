import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline signal for the offline banner and outbox flushes (spec §2.5, §6.16).
abstract interface class ConnectivityMonitor {
  Future<bool> isOnline();

  /// Wi-Fi or Ethernet — large downloads wait for it unless the user overrides (spec §5.14).
  Future<bool> isUnmetered();
  Stream<bool> get changes;
}

/// Default for tests and before the plugin is wired: assume online; requests still fail
/// gracefully with [OfflineException] when they can't connect.
class AlwaysOnline implements ConnectivityMonitor {
  const AlwaysOnline();
  @override
  Future<bool> isOnline() async => true;
  @override
  Future<bool> isUnmetered() async => true;
  @override
  Stream<bool> get changes => const Stream.empty();
}

class PluginConnectivityMonitor implements ConnectivityMonitor {
  PluginConnectivityMonitor([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;

  static bool _online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _online(await _c.checkConnectivity());
  @override
  Future<bool> isUnmetered() async =>
      (await _c.checkConnectivity()).any((x) => x == ConnectivityResult.wifi || x == ConnectivityResult.ethernet);
  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_online).distinct();
}
