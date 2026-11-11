import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/product_analytics.dart';
import '../../../core/di/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../backup/data/backup_engine.dart';
import '../data/auth_repository.dart';
import '../data/consent_repository.dart';

enum SignInOutcome { signedIn, cancelled, failed, offline }

/// The current session and the sign-in / link / sign-out flows (spec §5.3, §6.1).
class SessionController extends Notifier<Session> {
  @override
  Session build() => ref.watch(initialSessionProvider);

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  String get _locale => ref.read(settingsProvider).locale;

  Future<void> _afterSignIn() async {
    await ref.read(consentRepositoryProvider).syncAll();
    // Settings chosen before the account existed reach the server too.
    final s = ref.read(settingsProvider);
    await ref.read(settingsRepositoryProvider).save(s);
    ref.read(outboxSyncProvider).flush().ignore();
  }

  /// Google or Apple. A cancelled native sheet is not an error (spec §5.3).
  Future<SignInOutcome> signInWith(SignInProvider provider) async {
    final social = ref.read(socialAuthProvider);
    try {
      final cred = provider == SignInProvider.apple ? await social.apple() : await social.google();
      if (cred == null) return SignInOutcome.cancelled;
      state = await _repo.signIn(provider, idToken: cred.idToken, displayName: cred.displayName, locale: _locale);
      // Consent isn't decided yet during onboarding → queued, sent only if ads are allowed.
      await ref.read(analyticsProvider).logOrQueue(AdEvent.signUp);
      unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.signIn, {'provider': provider.name}));
      await _afterSignIn();
      return SignInOutcome.signedIn;
    } on OfflineException {
      return SignInOutcome.offline;
    } on Exception {
      return SignInOutcome.failed;
    }
  }

  /// Works with zero network (spec §5.3 acceptance).
  Future<void> continueAsGuest() async {
    state = await _repo.continueAsGuest(locale: _locale);
    unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.signIn, {'provider': 'guest'}));
    if (!state.pendingServer) await _afterSignIn();
  }

  Future<void>? _ensuring;

  /// Creates the server guest for an offline guest once connectivity returns (start, resume,
  /// back online). Concurrent callers share one attempt, so one phone never makes two guests.
  Future<void> ensureServerAccount() => _ensuring ??= _ensureServerAccount().whenComplete(() => _ensuring = null);

  Future<void> _ensureServerAccount() async {
    if (!state.pendingServer) return;
    try {
      state = await _repo.ensureServerGuest(state, locale: _locale);
      await _afterSignIn();
    } on Exception {
      // Still offline (or the API is down); try again on the next start / connectivity change.
    }
  }

  /// Guest → Google/Apple keeping points (`POST /v1/auth/link`).
  Future<SignInOutcome> link(SignInProvider provider) async {
    final social = ref.read(socialAuthProvider);
    try {
      await ensureServerAccount();
      final cred = provider == SignInProvider.apple ? await social.apple() : await social.google();
      if (cred == null) return SignInOutcome.cancelled;
      state = state.userId == null
          ? await _repo.signIn(provider, idToken: cred.idToken, displayName: cred.displayName, locale: _locale)
          : await _repo.link(provider, idToken: cred.idToken, displayName: cred.displayName);
      await ref.read(analyticsProvider).log(AdEvent.signUp);
      await _afterSignIn();
      return SignInOutcome.signedIn;
    } on OfflineException {
      return SignInOutcome.offline;
    } on Exception {
      return SignInOutcome.failed;
    }
  }

  /// Keeps on-device Quran data; wipes tokens and synced caches (spec §5.24).
  Future<void> signOut() async {
    // Deliver what this account still owes with its own token (offline: the queue stays), then
    // drop the rest — the next account on this phone must never be credited with it.
    try {
      await ref.read(outboxSyncProvider).flush(force: true);
    } on Exception {
      // Signing out never fails on the network.
    }
    await ref.read(outboxProvider).removeWhere(_accountScoped);
    await _repo.signOut();
    await ref.read(socialAuthProvider).signOut();
    await _forgetAccountCaches();
    state = Session.none;
  }

  /// The server refused the refresh token (revoked, expired): the account is gone from this phone.
  /// The ApiClient already cleared the tokens; queued writes stay for when the user signs in again.
  /// Returns whether a session actually ended (the caller then routes to Welcome).
  Future<bool> expire() async {
    if (!state.signedIn || state.pendingServer) return false;
    await _repo.forget();
    await _forgetAccountCaches();
    state = Session.none;
    return true;
  }

  static bool _accountScoped(OutboxItem i) => i.path.startsWith('/v1/me/') || i.path.startsWith('/v1/challenge/');

  Future<void> _forgetAccountCaches() async {
    final kv = ref.read(kvStoreProvider);
    for (final key in ['cache.rewards', 'cache.redemptions', ...BackupEngine.storageKeys]) {
      await kv.delete(key);
    }
    await ref.read(challengeRepositoryProvider).clearCache();
    // The cloud backup belongs to the account: the next account on this phone decides for itself
    // (the server copy and the consent record stay with this one).
    await ref.read(consentRepositoryProvider).adopt(ConsentKind.cloudBackup, false);
  }

  /// `DELETE /v1/me`, then wipes everything on this device (spec §5.24): tokens, caches, the local
  /// worship store and onboarding — the next start is a first launch.
  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    await ref.read(socialAuthProvider).signOut();
    final kv = ref.read(kvStoreProvider);
    for (final key in [
      'cache.challenge.summary', 'cache.rewards', 'cache.redemptions', 'cache.content', 'cache.dailyTask', //
      'consents.v1', 'consents.pending.v1', 'consents.decided', 'analytics.pending.v1', 'outbox.v1',
      ...BackupEngine.storageKeys, BackupEngine.offeredKey,
    ]) {
      await kv.delete(key);
    }
    await ref.read(challengeRepositoryProvider).clearCache();
    await ref.read(localStoreProvider).wipe();
    await ref.read(hifzRepositoryProvider).clear();
    await ref.read(localNotificationsProvider).cancelAll();
    await ref.read(settingsProvider.notifier).update((s) => AppSettings(locale: s.locale), sync: false);
    state = Session.none;
  }
}

final sessionProvider = NotifierProvider<SessionController, Session>(SessionController.new);
