import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// The Home tasbeeh counter (a plain counter, no text of its own). Device first (optional encrypted
/// cloud backup, consent `cloud_backup`), written behind a short debounce so fast tapping never waits
/// on storage; survives restarts.
class TasbeehController extends Notifier<int> {
  static const key = 'home.tasbeeh';
  static const round = 33;
  Timer? _save;

  @override
  int build() {
    ref.onDispose(() => _save?.cancel());
    Future(() async {
      final raw = await ref.read(kvStoreProvider).read(key);
      final saved = int.tryParse(raw ?? '') ?? 0;
      // A tap that landed before the load finished counts on top of what was saved.
      state = state + saved;
    });
    return 0;
  }

  void increment() {
    state = state + 1;
    _persist();
  }

  /// Cloud backup restored a count: it replaces the shown one and is saved at once.
  void adopt(int count) {
    _save?.cancel();
    state = count;
    ref.read(kvStoreProvider).write(key, '$state').ignore();
  }

  void reset() {
    state = 0;
    _persist();
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () => ref.read(kvStoreProvider).write(key, '$state'));
  }
}

final tasbeehProvider = NotifierProvider<TasbeehController, int>(TasbeehController.new);
