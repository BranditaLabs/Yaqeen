import '../../../core/storage/local_store.dart';
import '../domain/hifz_plan.dart';

/// Hifz is device first, with an optional encrypted cloud backup (consent `cloud_backup`; spec §5.25):
/// no other API, no analytics, never in admin views.
class HifzRepository {
  HifzRepository(this.store);
  final LocalStore store;
  static const doc = 'hifz';

  Future<HifzPlan?> load() async => HifzPlan.tryParse(await store.read(doc));
  Future<void> save(HifzPlan plan) => store.write(doc, plan.toJson());
  Future<void> clear() => store.write(doc, const <String, Object>{});
}
