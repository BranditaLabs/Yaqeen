import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../storage/kv_store.dart';

/// Error returned by the Yaqeen API: `{ "error": { "code", "message" } }`.
class ApiException implements Exception {
  ApiException(this.status, this.code, [this.message, this.details]);

  final int status;
  final String code;
  final String? message;

  /// `error.details` when the API sends one (e.g. the current document of a 409 `backup_conflict`).
  final Object? details;

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

  /// Called once when the server refuses the refresh token (revoked, expired, account gone) —
  /// the tokens are already cleared; the app ends the session and routes to sign-in.
  void Function()? onSessionExpired;

  /// The refresh in flight. Refresh tokens rotate on use, so concurrent 401s share one refresh:
  /// a second refresh with the same token would be refused and sign the user out.
  Future<bool>? _refreshing;

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
    // A refresh in flight: wait for it rather than send a token that is about to be replaced.
    final pending = _refreshing;
    if (pending != null) await pending.catchError((Object _) => false);
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

    if (res.statusCode == 401 && !retried && path != '/v1/auth/refresh') {
      // Another call may have rotated the pair while this one was in flight: retry with it.
      final current = await tokens.accessToken;
      if ((current != null && current != token) || await _refreshOnce()) {
        return _send(method, path, body: body, query: query, headers: headers, retried: true);
      }
    }
    if (res.statusCode >= 400) throw _error(res);
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      // Not our API (a captive portal's login page): no real connectivity.
      throw const OfflineException();
    }
  }

  /// `{ "error": { "code", "message", "details" } }`; code `error` for any other body (a gateway's
  /// HTML 502 page, an empty 503).
  static ApiException _error(http.Response res) {
    Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final err = decoded is Map ? decoded['error'] : null;
    if (err is! Map) return ApiException(res.statusCode, 'error');
    final code = err['code'];
    final message = err['message'];
    return ApiException(res.statusCode, code is String ? code : 'error', message is String ? message : null, err['details']);
  }

  Future<bool> _refreshOnce() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// True when a new pair is stored. Ends the session only when the server refuses the refresh
  /// token (400/401); a 5xx or 429 keeps it for the next try, and no network is [OfflineException].
  Future<bool> _refresh() async {
    final refresh = await tokens.refreshToken;
    if (refresh == null) return false;
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(timeout);
    } on Exception {
      throw const OfflineException();
    }
    if (res.statusCode == 200) {
      final Map<String, dynamic> json;
      try {
        json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      } on Object {
        throw const OfflineException();
      }
      await tokens.save(access: json['accessToken'] as String, refresh: json['refreshToken'] as String);
      return true;
    }
    if (res.statusCode == 400 || res.statusCode == 401) {
      // Rotated meanwhile (a sign-in on this phone): the stored pair is newer — use it.
      if (await tokens.refreshToken != refresh) return await tokens.accessToken != null;
      await tokens.clear();
      onSessionExpired?.call();
      return false;
    }
    // 5xx / 429: the session is fine, the server isn't — keep the tokens and retry later.
    throw _error(res);
  }
}
