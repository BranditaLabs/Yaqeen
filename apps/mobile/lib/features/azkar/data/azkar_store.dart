import '../../../core/storage/local_store.dart';
import '../domain/azkar_progress.dart';

/// Azkar counts and dua favourites — device only, never synced (they are worship data).
class AzkarStore {
  AzkarStore(this.store);
  final LocalStore store;

  Future<AzkarDay?> day() async => AzkarDay.tryParse(await store.read('azkar'));
  Future<void> saveDay(AzkarDay d) => store.write('azkar', d.toJson());

  Future<Set<String>> favourites() async => {...((await store.readList('favourites')).cast<String>())};
  Future<void> saveFavourites(Set<String> ids) => store.write('favourites', ids.toList());
}
