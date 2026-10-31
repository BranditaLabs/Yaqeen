import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal async key-value store so repositories can be unit-tested with [MemoryKvStore].
abstract interface class KvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Non-sensitive data (settings, caches, offline outbox).
class PrefsKvStore implements KvStore {
  PrefsKvStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);
  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

/// Tokens only — Keychain on iOS, EncryptedSharedPreferences/Keystore on Android.
class SecureKvStore implements KvStore {
  SecureKvStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKvStore implements KvStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Wraps a store and announces every key written or deleted — the opt-in cloud backup watches it
/// to know which device-first collection changed, without touching the stores themselves.
/// Events are delivered synchronously, during the write.
class ObservableKvStore implements KvStore {
  ObservableKvStore(this._inner);
  final KvStore _inner;
  final _changes = StreamController<String>.broadcast(sync: true);

  Stream<String> get changes => _changes.stream;

  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) async {
    await _inner.write(key, value);
    _changes.add(key);
  }

  @override
  Future<void> delete(String key) async {
    await _inner.delete(key);
    _changes.add(key);
  }
}
