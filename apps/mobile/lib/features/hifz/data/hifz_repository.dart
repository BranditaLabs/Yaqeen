import '../../../core/storage/local_store.dart';
import '../domain/hifz_plan.dart';

/// Hifz stays on the device (spec §5.25): no API, no analytics, not in the server export.
class HifzRepository {
  HifzRepository(this.store);
  final LocalStore store;
  static const _doc = 'hifz';

  Future<HifzPlan?> load() async => HifzPlan.tryParse(await store.read(_doc));
  Future<void> save(HifzPlan plan) => store.write(_doc, plan.toJson());
  Future<void> clear() => store.write(_doc, const <String, Object>{});
}
