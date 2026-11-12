import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/prayer/data/city_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('country names: Arabic in ar, English in en (never a bare ISO code for a listed country)', () async {
    final repo = CityRepository();
    final cities = await repo.all();
    expect(repo.countryName('EG', 'ar'), 'مصر');
    expect(repo.countryName('EG', 'en'), 'Egypt');
    expect(repo.countryName('SA', 'en'), 'Saudi Arabia');
    // Every country in the bundled list has an English name.
    for (final c in cities.where((c) => c.country.isNotEmpty)) {
      expect(repo.countryName(c.country, 'en'), isNot(c.country), reason: c.country);
    }
    // No Arabic name yet → the English one rather than the code.
    expect(repo.countryName('JP', 'ar'), 'Japan');
  });

  test('English search finds a city and loads every row (places without a country included)', () async {
    final repo = CityRepository();
    final hits = await repo.search('cair');
    expect(hits.first.nameEn, 'Cairo');
    expect(repo.countryName(hits.first.country, 'en'), 'Egypt');
    expect((await repo.all()).length, 1500);
  });
}
