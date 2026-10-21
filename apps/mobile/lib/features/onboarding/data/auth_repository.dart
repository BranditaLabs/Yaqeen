import '../../../core/network/api_client.dart';

enum SignInProvider { google, apple, guest }

/// Exchanges a Google/Apple ID token (from google_sign_in / sign_in_with_apple)
/// for a Yaqeen session. Guests can browse; joining the challenge needs an account.
class AuthRepository {
  AuthRepository({required this.api, required this.tokens});

  final ApiClient api;
  final TokenStore tokens;

  Future<bool> get isSignedIn async => (await tokens.accessToken) != null;

  Future<void> signIn(SignInProvider provider, {String? idToken, String? displayName, String locale = 'ar'}) async {
    final json = (await api.post('/v1/auth/sign-in', {
      'provider': provider.name,
      if (idToken != null) 'idToken': idToken,
      if (displayName != null) 'displayName': displayName,
      'locale': locale,
    }) as Map)
        .cast<String, dynamic>();
    await tokens.save(access: json['accessToken'] as String, refresh: json['refreshToken'] as String);
  }

  Future<void> signOut() async {
    try {
      await api.post('/v1/auth/sign-out');
    } on Exception {
      // Sign out locally regardless.
    }
    await tokens.clear();
  }
}
