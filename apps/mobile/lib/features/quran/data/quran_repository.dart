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
        // Decode *and* build the model on a background isolate; the result moves back without a copy.
        return compute(_parse, raw);
      }().catchError((Object e) {
        _data = null; // a later watch retries instead of caching the failure
        throw e;
      });

  static QuranData _parse(String raw) => QuranData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
