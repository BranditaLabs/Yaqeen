import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'remote_config.dart';

class RemoteConfigController extends Notifier<RemoteConfig> {
  @override
  RemoteConfig build() => ref.watch(initialConfigProvider);

  Future<void> refresh({bool force = false}) async {
    state = await ref.read(remoteConfigRepositoryProvider).refresh(force: force);
  }
}

final remoteConfigProvider = NotifierProvider<RemoteConfigController, RemoteConfig>(RemoteConfigController.new);
