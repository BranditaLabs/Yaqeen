import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/text/arabic.dart';
import '../domain/qibla.dart';

class City {
  const City({required this.nameEn, this.nameAr, required this.country, required this.lat, required this.lng, required this.timezone});

  final String nameEn;
  final String? nameAr;
  final String country;
  final double lat;
  final double lng;
  final String timezone;

  String name(String locale) => locale == 'ar' ? (nameAr ?? nameEn) : nameEn;

  Place toPlace({bool auto = false}) =>
      Place(nameAr: nameAr ?? nameEn, nameEn: nameEn, country: country, lat: lat, lng: lng, timezone: timezone, auto: auto);
}

/// Bundled offline city list (assets/geo/cities.json, tools/geo/build_cities.py).
class CityRepository {
  CityRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;

  List<City>? _cities;
  Map<String, String> _countriesAr = const {};
  late List<(City, String, String)> _index; // city, normalized Arabic, normalized English

  Future<List<City>> all() async {
    if (_cities != null) return _cities!;
    final j = jsonDecode(await _bundle.loadString('assets/geo/cities.json')) as Map<String, dynamic>;
    _countriesAr = (j['countriesAr'] as Map).cast<String, String>();
    _cities = [
      for (final r in (j['cities'] as List).cast<List<dynamic>>())
        City(
          nameEn: r[0] as String,
          nameAr: r[1] as String?,
          country: r[2] as String,
          lat: (r[3] as num).toDouble(),
          lng: (r[4] as num).toDouble(),
          timezone: r[5] as String,
        ),
    ];
    _index = [for (final c in _cities!) (c, ArabicText.normalize(c.nameAr ?? ''), c.nameEn.toLowerCase())];
    return _cities!;
  }

  String countryName(String iso2, String locale) => locale == 'ar' ? (_countriesAr[iso2] ?? iso2) : iso2;

  /// Prefix matches first (Arabic or English), then contains; list order is MENA-first by population.
  Future<List<City>> search(String query, {int limit = 30}) async {
    final cities = await all();
    final q = ArabicText.normalize(query).toLowerCase();
    if (q.isEmpty) return cities.take(limit).toList();
    final starts = <City>[];
    final contains = <City>[];
    for (final (c, ar, en) in _index) {
      if (ar.startsWith(q) || en.startsWith(q) || ArabicText.withoutArticle(ar).startsWith(q)) {
        starts.add(c);
      } else if (ar.contains(q) || en.contains(q)) {
        contains.add(c);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  /// Closest city to a coordinate (names the auto-detected location, e.g. «القاهرة»).
  Future<(City, double km)?> nearest(double lat, double lng) async {
    (City, double)? best;
    for (final c in await all()) {
      final d = haversineKm(lat, lng, c.lat, c.lng);
      if (best == null || d < best.$2) best = (c, d);
    }
    return best;
  }
}
