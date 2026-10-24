import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../storage/kv_store.dart';

/// Error returned by the Yaqeen API: `{ "error": { "code", "message" } }`.
class ApiException implements Exception {
  ApiException(this.status, this.code, [this.message]);

  final int status;
  final String code;
  final String? message;

  /// 4xx except 408/429 will never succeed on retry (e.g. `already_completed`).
  bool get isPermanent => status >= 400 && status < 500 && status != 408 && status != 429;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// No connectivity / timeout. Callers should queue and retry later.
class OfflineException implements Exception {
  const OfflineException();
}

/// Holds the session; access token is short-lived (15 min), refresh token rotates.
class TokenStore {
  TokenStore(this._store);
  final KvStore _store;

  static const _access = 'auth.access';
  static const _refresh = 'auth.refresh';

  Future<String?> get accessToken => _store.read(_access);
  Future<String?> get refreshToken => _store.read(_refresh);

  Future<void> save({required String access, required String refresh}) async {
    await _store.write(_access, access);
    await _store.write(_refresh, refresh);
  }

  Future<void> clear() async {
    await _store.delete(_access);
    await _store.delete(_refresh);
  }
}

/// Thin JSON client with bearer auth and one transparent refresh on 401.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final Duration timeout;
  final http.Client _http;

  /// Called when refresh fails — the app routes to sign-in.
  void Function()? onSessionExpired;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body, Map<String, String>? headers]) => _send('POST', path, body: body, headers: headers);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final token = await tokens.accessToken;
    final req = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = 'ar';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on SocketException {
      throw const OfflineException();
    } on TimeoutException {
      throw const OfflineException();
    } on http.ClientException {
      throw const OfflineException();
    }

    if (res.statusCode == 401 && !retried && path != '/v1/auth/refresh' && await _refresh()) {
      return _send(method, path, body: body, query: query, headers: headers, retried: true);
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final err = (decoded is Map ? decoded['error'] : null) as Map<String, dynamic>?;
      throw ApiException(res.statusCode, (err?['code'] as String?) ?? 'error', err?['message'] as String?);
    }
    return decoded;
  }

  Future<bool> _refresh() async {
    final refresh = await tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await _http
          .post(
            Uri.parse('$baseUrl/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(timeout);
      if (res.statusCode != 200) {
        await tokens.clear();
        onSessionExpired?.call();
        return false;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      await tokens.save(access: json['accessToken'] as String, refresh: json['refreshToken'] as String);
      return true;
    } on Exception {
      return false;
    }
  }
}
