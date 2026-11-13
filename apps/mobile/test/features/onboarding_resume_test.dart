import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/features/onboarding/presentation/splash_gate.dart';

/// Resume by route name (design §8): an interrupted onboarding continues at the step it stopped
/// at, and settings saved before the profile step existed still resume where they meant to.
void main() {
  test('the order: … routine → profile → download, and the frozen v1 list without profile', () {
    expect(onboardingRoutes, [
      '/onboarding/welcome',
      '/onboarding/language',
      '/onboarding/prayer',
      '/onboarding/consent',
      '/onboarding/goal',
      '/onboarding/routine',
      '/onboarding/profile',
      '/onboarding/download',
    ]);
    expect(legacyOnboardingRoutesV1, [for (final r in onboardingRoutes) if (r != '/onboarding/profile') r]);
  });

  test('a saved route wins over the index', () {
    for (final route in onboardingRoutes) {
      expect(nextAfterSplash(AppSettings(onboardingRoute: route, onboardingStep: 1)), route);
    }
    expect(nextAfterSplash(const AppSettings(onboardingRoute: '/onboarding/profile', onboardingStep: 6)), '/onboarding/profile');
  });

  test('legacy settings (no route): the index reads through the v1 list', () {
    expect(nextAfterSplash(const AppSettings(onboardingStep: 6)), '/onboarding/download'); // not profile
    expect(nextAfterSplash(const AppSettings(onboardingStep: 5)), '/onboarding/routine');
    expect(nextAfterSplash(const AppSettings(onboardingStep: 0)), '/onboarding/welcome');
    expect(nextAfterSplash(const AppSettings(onboardingStep: 99)), '/onboarding/download'); // clamped
  });

  test('an unknown saved route falls back to the legacy index', () {
    expect(nextAfterSplash(const AppSettings(onboardingRoute: '/onboarding/gone', onboardingStep: 2)), '/onboarding/prayer');
  });

  test('settings JSON from before the route existed still resume at download', () {
    final old = AppSettings.fromJson((jsonDecode('{"locale":"ar","onboardingStep":6}') as Map).cast<String, dynamic>());
    expect(old.onboardingRoute, isNull);
    expect(nextAfterSplash(old), '/onboarding/download');
    final saved = AppSettings.fromJson(const AppSettings(onboardingRoute: '/onboarding/profile', onboardingStep: 6).toJson());
    expect(nextAfterSplash(saved), '/onboarding/profile');
  });

  test('once onboarded: Home, or the deep link', () {
    final done = AppSettings(onboardingCompletedAt: DateTime.utc(2026), onboardingRoute: '/onboarding/profile');
    expect(nextAfterSplash(done), '/home');
    expect(nextAfterSplash(done, deepLink: '/profile'), '/profile');
  });
}
