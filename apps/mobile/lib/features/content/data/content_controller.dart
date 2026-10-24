import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../domain/content_item.dart';

/// Local first (cache → bundled seed), then a background refresh; screens never wait on the network.
class ContentController extends AsyncNotifier<ContentLibrary> {
  @override
  Future<ContentLibrary> build() async {
    final repo = ref.read(contentRepositoryProvider);
    final local = ContentLibrary(await repo.local());
    Future.microtask(refresh);
    return local;
  }

  Future<void> refresh() async {
    final fresh = await ref.read(contentRepositoryProvider).sync();
    if (fresh != null) state = AsyncData(ContentLibrary(fresh));
  }
}

final contentProvider = AsyncNotifierProvider<ContentController, ContentLibrary>(ContentController.new);
