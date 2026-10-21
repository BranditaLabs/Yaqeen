import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/quran_data.dart';

/// Loads the bundled mushaf once (parsed off the UI thread). Works in airplane mode on day one.
class QuranRepository {
  QuranRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  Future<QuranData>? _data;

  Future<QuranData> load() => _data ??= () async {
        final raw = await _bundle.loadString('assets/quran/quran.json', cache: false);
        final json = await compute(_decode, raw);
        return QuranData.fromJson(json);
      }();

  static Map<String, dynamic> _decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;
}
