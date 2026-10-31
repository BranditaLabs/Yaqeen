import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/env.dart';

/// What a native provider sheet returns. `null` from [SocialAuth] means the user cancelled.
class SocialCredential {
  const SocialCredential({required this.idToken, this.displayName});
  final String idToken;

  /// Apple sends the name only on the first sign-in, so we pass it to the API then.
  final String? displayName;
}

abstract interface class SocialAuth {
  Future<SocialCredential?> google();
  Future<SocialCredential?> apple();
  Future<void> signOut();
}

class PluginSocialAuth implements SocialAuth {
  bool _googleReady = false;

  @override
  Future<SocialCredential?> google() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(serverClientId: Env.googleServerClientId.isEmpty ? null : Env.googleServerClientId);
      _googleReady = true;
    }
    try {
      final account = await g.authenticate();
      final token = account.authentication.idToken;
      return token == null ? null : SocialCredential(idToken: token, displayName: account.displayName);
    } on GoogleSignInException catch (e) {
      debugPrint('YQ-AUTH google ${e.code.name}: ${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled && !isGoogleSetupFailure(e.description)) return null;
      rethrow;
    }
  }

  /// Credential Manager reports some setup problems as a cancellation — chiefly "[16] Account reauth
  /// failed" when the app's signing-key SHA isn't registered with the OAuth project. Those are
  /// failures, not the user closing the sheet, so the welcome screen says so instead of doing nothing.
  @visibleForTesting
  static bool isGoogleSetupFailure(String? description) {
    final d = description?.toLowerCase() ?? '';
    return d.contains('[16]') || d.contains('reauth') || d.contains('developer console');
  }

  @override
  Future<SocialCredential?> apple() async {
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        webAuthenticationOptions: Platform.isAndroid
            ? WebAuthenticationOptions(clientId: Env.appleServiceId, redirectUri: Uri.parse(Env.appleRedirectUri))
            : null,
      );
      final name = [c.givenName, c.familyName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      return c.identityToken == null ? null : SocialCredential(idToken: c.identityToken!, displayName: name.isEmpty ? null : name);
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('YQ-AUTH apple ${e.code.name}: ${e.message}');
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
  }
}

/// Test double: returns [credential] (or null = cancelled).
class FakeSocialAuth implements SocialAuth {
  FakeSocialAuth({this.credential});
  SocialCredential? credential;
  @override
  Future<SocialCredential?> google() async => credential;
  @override
  Future<SocialCredential?> apple() async => credential;
  @override
  Future<void> signOut() async {}
}
