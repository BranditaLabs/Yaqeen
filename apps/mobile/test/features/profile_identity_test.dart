import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/features/card/domain/public_card.dart' as card;
import 'package:yaqeen/features/onboarding/data/consent_repository.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';
import 'package:yaqeen/features/profile/domain/avatar_presets.dart';
import 'package:yaqeen/features/profile/domain/level.dart';
import 'package:yaqeen/features/profile/domain/me_profile.dart';

void main() {
  test('kAvatarPresets mirrors packages/brand/avatars/avatars.json, and every preset has its art', () {
    final json = (jsonDecode(File('../../packages/brand/avatars/avatars.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    expect([for (final p in kAvatarPresets) {'id': p.id, 'gender': p.gender.name, 'ar': p.ar, 'en': p.en}], json);
    for (final p in kAvatarPresets) {
      expect(File(p.asset).existsSync(), isTrue, reason: p.asset);
    }
    final constants = jsonDecode(File('test/fixtures/community/constants.json').readAsStringSync()) as Map<String, dynamic>;
    expect(kAvatarPresets.map((p) => p.id).toList(), constants['AVATAR_PRESETS']);
    expect(presetById('f04')!.en, 'Niqab');
    expect(presetById('x99'), isNull);
  });

  test('every preset has an ARB label (avM01…avF08) in both languages', () {
    final ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
    for (final p in kAvatarPresets) {
      final key = 'av${p.id[0].toUpperCase()}${p.id.substring(1)}';
      expect(ar[key], p.ar, reason: key);
      expect(en[key], isA<String>(), reason: key);
    }
  });

  group('AvatarRef', () {
    test('parses the three kinds and round-trips', () {
      for (final a in [
        const InitialAvatar(),
        const PresetAvatar('m03'),
        const PhotoAvatar(id: 'a1', url: '/v1/me/avatar/photo/256', smallUrl: '/v1/me/avatar/photo/96', localPath: '/x/avatar_a1.webp'),
      ]) {
        expect(AvatarRef.fromJson(jsonDecode(jsonEncode(a.toJson()))), a);
      }
    });

    test('unknown or malformed values read as the initial', () {
      expect(AvatarRef.fromJson(null), const InitialAvatar());
      expect(AvatarRef.fromJson({'kind': 'hologram'}), const InitialAvatar());
      expect(AvatarRef.fromJson({'kind': 'preset'}), const InitialAvatar());
      expect(AvatarRef.fromJson({'kind': 'photo', 'id': 'x'}), const InitialAvatar());
    });

    test('isAuthedPath only for the caller\'s own /v1/me/ paths', () {
      const own = PhotoAvatar(id: 'a', url: '/v1/me/avatar/photo/256', smallUrl: '/v1/me/avatar/photo/96');
      const public = PhotoAvatar(id: 'a', url: 'https://api.yaqeenarabia.com/v1/public/avatars/a/256.webp', smallUrl: 'https://x/96.webp');
      expect(own.isAuthedPath, isTrue);
      expect(public.isAuthedPath, isFalse);
      expect(const PhotoAvatar.local('/tmp/avatar_local.jpg').isLocalOnly, isTrue);
    });
  });

  group('MeProfile', () {
    test('guest: level 1 at 0, nothing public, all switches off', () {
      final g = MeProfile.guest(displayName: 'Guest');
      expect(g.level, levelFor(0));
      expect(g.community, CommunitySettings.off);
      expect(g.league, isNull);
      expect(g.recentBadges, isEmpty);
      expect(g.avatar, const InitialAvatar());
    });

    test('firstName is the first word only (never the full name)', () {
      expect(MeProfile.firstNameOf('  Ahmed Hamdy Abo Elela '), 'Ahmed');
      expect(MeProfile.firstNameOf('محمد عبد الله'), 'محمد');
      expect(MeProfile.firstNameOf(null), '');
    });
  });

  test('levels moved to profile/domain and are still exported by public_card.dart', () {
    expect(card.levelFor(2000).level, 3);
    expect(identical(card.cardLevels, cardLevels), isTrue);
    expect(levelFor(25000).isTop, isTrue);
    expect(levelFor(24999).isTop, isFalse);
  });

  group('settings and flags', () {
    test('serverPatch sends the chosen city\'s ISO-2 country, null when unknown', () {
      expect(const AppSettings(place: Place.cairo).serverPatch()['country'], 'EG');
      expect(const AppSettings().serverPatch()['country'], isNull);
      const odd = Place(nameAr: 'س', nameEn: 'X', country: '', lat: 0, lng: 0, timezone: 'UTC');
      expect(const AppSettings(place: odd).serverPatch()['country'], isNull);
    });

    test('onboardingRoute round-trips; old settings read it as null and keep the legacy index', () {
      const s = AppSettings(onboardingStep: 6, onboardingRoute: '/onboarding/profile');
      final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.onboardingRoute, '/onboarding/profile');
      expect(back.onboardingStep, 6);
      final legacy = AppSettings.fromJson({'onboardingStep': 6});
      expect(legacy.onboardingRoute, isNull);
      expect(legacy.onboardingStep, 6);
      expect(s.copyWith(locale: 'en').onboardingRoute, '/onboarding/profile');
    });

    test('competition flags and the community consent are off by default', () {
      const c = RemoteConfig();
      expect(c.features[Flags.leagues], isFalse);
      expect(c.features[Flags.tournaments], isFalse);
      expect(c.features[Flags.leaderboard], isFalse);
      expect(ConsentKind.community.wire, 'community');
      expect(consentDefaults[ConsentKind.community], isFalse);
      expect(onboardingConsents, isNot(contains(ConsentKind.community)));
    });
  });
}
