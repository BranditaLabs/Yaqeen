import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';

enum SignInProvider { google, apple, guest }

/// Who is using the app. Tokens live in secure storage; this (non-secret) part in prefs.
class Session {
  const Session({this.provider, this.userId, this.displayName, this.pendingServer = false});

  static const none = Session();

  /// null = not signed in yet (onboarding).
  final SignInProvider? provider;

  /// Server user id; null for a guest created offline that hasn't reached the API yet.
  final String? userId;
  final String? displayName;

  /// Guest chosen offline: the server guest is created on the first online moment (spec §5.3).
  final bool pendingServer;

  bool get signedIn => provider != null;
  bool get isGuest => provider == SignInProvider.guest;

  /// Earning and redeeming points need a Google/Apple account (spec §6.1).
  bool get canEarnPoints => signedIn && !isGuest && userId != null;

  Map<String, dynamic> toJson() =>
      {'provider': provider?.name, 'userId': userId, 'displayName': displayName, 'pendingServer': pendingServer};
  factory Session.fromJson(Map<String, dynamic> j) => Session(
        provider: SignInProvider.values.where((p) => p.name == j['provider']).firstOrNull,
        userId: j['userId'] as String?,
        displayName: j['displayName'] as String?,
        pendingServer: (j['pendingServer'] as bool?) ?? false,
      );
}

/// Exchanges a Google/Apple ID token for a Yaqeen session, keeps the session, links guests.
class AuthRepository {
  AuthRepository({required this.api, required this.tokens, required this.store});

  final ApiClient api;
  final TokenStore tokens;
  final KvStore store;
  static const _key = 'auth.session';

  Future<bool> get isSignedIn async => (await tokens.accessToken) != null;

  Future<Session> load() async {
    final raw = await store.read(_key);
    if (raw == null) return Session.none;
    try {
      return Session.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      // Unreadable session: start as a guest rather than not at all.
      await store.delete(_key);
      return Session.none;
    }
  }

  Future<void> _save(Session s) => store.write(_key, jsonEncode(s.toJson()));

  Future<Session> _consume(Object? json, SignInProvider provider) async {
    final m = (json as Map).cast<String, dynamic>();
    await tokens.save(access: m['accessToken'] as String, refresh: m['refreshToken'] as String);
    final user = (m['user'] as Map).cast<String, dynamic>();
    final s = Session(provider: provider, userId: user['id'] as String, displayName: user['displayName'] as String?);
    await _save(s);
    return s;
  }

  Future<Session> signIn(SignInProvider provider, {String? idToken, String? displayName, String locale = 'ar'}) async {
    final json = await api.post('/v1/auth/sign-in', {
      'provider': provider.name,
      if (idToken != null) 'idToken': idToken,
      if (displayName != null) 'displayName': displayName,
      'locale': locale,
    });
    return _consume(json, provider);
  }

  /// Guest that works with zero network: saved locally now, created on the server later.
  Future<Session> continueAsGuest({String locale = 'ar'}) async {
    try {
      return await signIn(SignInProvider.guest, locale: locale);
    } on OfflineException {
      const s = Session(provider: SignInProvider.guest, pendingServer: true);
      await _save(s);
      return s;
    }
  }

  /// Completes an offline guest once the network is back. No-op otherwise.
  Future<Session> ensureServerGuest(Session s, {String locale = 'ar'}) async {
    if (!s.pendingServer) return s;
    return signIn(SignInProvider.guest, locale: locale);
  }

  /// Guest → Google/Apple, keeping points (`POST /v1/auth/link`, spec §6.1).
  Future<Session> link(SignInProvider provider, {required String idToken, String? displayName}) async {
    final json = await api
        .post('/v1/auth/link', {'provider': provider.name, 'idToken': idToken, if (displayName != null) 'displayName': displayName});
    return _consume(json, provider);
  }

  /// `GET /v1/me/export` — the user's own copy of their server data (PDPL, spec §6.17).
  Future<Map<String, dynamic>> exportData() async => ((await api.get('/v1/me/export')) as Map).cast<String, dynamic>();

  /// `DELETE /v1/me`: sessions end now; the server anonymises after the grace period.
  Future<void> deleteAccount() async {
    await api.delete('/v1/me');
    await tokens.clear();
    await store.delete(_key);
  }

  Future<void> signOut() async {
    try {
      await api.post('/v1/auth/sign-out');
    } on Exception {
      // Sign out locally regardless.
    }
    await tokens.clear();
    await store.delete(_key);
  }
}
