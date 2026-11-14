import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/product_analytics.dart';
import '../../../core/di/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../backup/data/backup_engine.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/badges_strip.dart' show sweptBadgesProvider;
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../../quran/data/session_store.dart';
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
    // First, before any other network call: the name and picture a guest chose on this phone reach
    // the account (only what they changed; the server's values win otherwise). The repository
    // keeps those changes on top of any refresh until they are pushed (`profile.dirty.v1`). Never
    // fails sign-in: offline keeps the flags for later.
    MeProfile? profile;
    try {
      profile = await ref.read(profileRepositoryProvider).pushAfterSignIn();
    } on Object {
      // best effort
    }
    // Signing in is not a level-up: the account's level becomes the last one seen on this phone.
    await _rebaseLevel(profile?.level.level);
    // Screens show the pushed profile (a refresh that raced the push was dropped by the repository).
    if (profile != null && ref.exists(meProfileProvider)) await ref.read(meProfileProvider.notifier).reload();
    await ref.read(consentRepositoryProvider).syncAll();
    // Settings chosen before the account existed reach the server too.
    final s = ref.read(settingsProvider);
    await ref.read(settingsRepositoryProvider).save(s);
    ref.read(outboxSyncProvider).flush().ignore();
  }

  /// A new account is about to replace the session: until its own level is known, the level-up
  /// moment neither remembers the placeholder profile nor owes anything.
  void _holdLevelUp() {
    if (ref.exists(levelUpProvider)) ref.read(levelUpProvider.notifier).reset(hold: true);
  }

  Future<void> _rebaseLevel(int? level) async {
    if (ref.exists(levelUpProvider)) ref.read(levelUpProvider.notifier).rebase(level);
    if (level != null) await ref.read(kvStoreProvider).write(ProfileRepository.lastSeenLevelKey, '$level');
  }

  /// Google or Apple. A cancelled native sheet is not an error (spec §5.3).
  Future<SignInOutcome> signInWith(SignInProvider provider) async {
    final social = ref.read(socialAuthProvider);
    try {
      final cred = provider == SignInProvider.apple ? await social.apple() : await social.google();
      if (cred == null) return SignInOutcome.cancelled;
      final session = await _repo.signIn(provider, idToken: cred.idToken, displayName: cred.displayName, locale: _locale);
      _holdLevelUp();
      state = session;
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
      final session = state.userId == null
          ? await _repo.signIn(provider, idToken: cred.idToken, displayName: cred.displayName, locale: _locale)
          : await _repo.link(provider, idToken: cred.idToken, displayName: cred.displayName);
      _holdLevelUp();
      state = session;
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
    // The UI signs out at once: the profile's photo files are removed in the background.
    await _forgetAccountCaches(awaitFiles: false);
    state = Session.none;
    return true;
  }

  static bool _accountScoped(OutboxItem i) => i.path.startsWith('/v1/me/') || i.path.startsWith('/v1/challenge/');

  Future<void> _forgetAccountCaches({bool awaitFiles = true}) async {
    final kv = ref.read(kvStoreProvider);
    for (final key in ['cache.rewards', 'cache.redemptions', ...BackupEngine.storageKeys]) {
      await kv.delete(key);
    }
    await ref.read(challengeRepositoryProvider).clearCache();
    // The cloud backup belongs to the account: the next account on this phone decides for itself
    // (the server copy and the consent record stay with this one).
    await ref.read(consentRepositoryProvider).adopt(ConsentKind.cloudBackup, false);
    // So do the profile (name, picture, level cache) and the competitions it joined.
    await _forgetProfile(awaitFiles: awaitFiles);
  }

  /// Profile and community caches, photo files and the `community` consent on this phone. The
  /// cached keys always go before the session changes (so no screen paints the old profile);
  /// [awaitFiles] false leaves the photo files to finish in the background.
  Future<void> _forgetProfile({bool awaitFiles = true}) async {
    // Started first: from here on a profile request still out for this account (a background
    // refresh, an upload) is dropped instead of writing the old profile back (the repository's
    // generation moves synchronously).
    final files = ref.read(profileRepositoryProvider).wipe();
    final kv = ref.read(kvStoreProvider);
    for (final key in ProfileRepository.wipedKeys) {
      await kv.delete(key);
    }
    YqAvatar.clearMemoryCache();
    // The last-seen level also lives in memory: the next account must not be compared with it.
    if (ref.exists(levelUpProvider)) ref.read(levelUpProvider.notifier).reset();
    // So does the set of medals whose light already passed (re-read from the wiped KV).
    if (ref.exists(sweptBadgesProvider)) ref.invalidate(sweptBadgesProvider);
    await ref.read(consentRepositoryProvider).adopt(ConsentKind.community, false);
    if (awaitFiles) {
      await files;
    } else {
      files.ignore();
    }
  }

  /// `DELETE /v1/me`, then wipes everything on this device (spec §5.24): tokens, caches, the local
  /// worship store, the profile, the Quran session and onboarding — the next start is a first launch.
  /// (Sign-out keeps the Quran session like other on-device Quran data.)
  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    await ref.read(socialAuthProvider).signOut();
    await _forgetProfile();
    final kv = ref.read(kvStoreProvider);
    await QuranSessionStore.wipe(kv);
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
