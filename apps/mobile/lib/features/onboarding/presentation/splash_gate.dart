import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import 'splash_screen.dart';

const onboardingRoutes = [
  '/onboarding/welcome',
  '/onboarding/language',
  '/onboarding/prayer',
  '/onboarding/consent',
  '/onboarding/goal',
  '/onboarding/routine',
  '/onboarding/download',
];

/// Where the splash goes: Home once onboarded, otherwise the step the user stopped at (kill-safe).
String nextAfterSplash(AppSettings s, {String? deepLink}) {
  if (!s.onboarded) return onboardingRoutes[s.onboardingStep.clamp(0, onboardingRoutes.length - 1)];
  return deepLink ?? '/home';
}

/// Full choreography the first launch of each day (3.8 s), 1.2 s afterwards (spec §4.1).
Duration splashHold(AppSettings s, String today) =>
    s.lastSplashDay == today ? const Duration(milliseconds: 1200) : const Duration(milliseconds: 3800);

/// The splash verse and its caption. Remote config carries only what a religious reviewer approved
/// (the API writes `splashVerse` on approval, spec §5.2); blank text, or the bundled verse itself,
/// shows the bundled verse with its designed caption.
(String, String) splashVerseOf(RemoteConfig c) {
  final text = c.splashVerseAr.trim();
  if (text.isEmpty || text == SplashScreen.bundledVerse) return (SplashScreen.bundledVerse, SplashScreen.bundledCaption);
  return (text, c.splashVerseRef.trim());
}

class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key, this.deepLink});
  final String? deepLink;

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  late final AppSettings _s = ref.read(settingsProvider);
  late final String _today = Zoned.isoDate(Zoned.today(_s.placeOrDefault.timezone, ref.read(clockProvider)()));

  @override
  void initState() {
    super.initState();
    if (_s.lastSplashDay != _today) {
      Future.microtask(() => ref.read(settingsProvider.notifier).update((x) => x.copyWith(lastSplashDay: _today), sync: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (verse, caption) = splashVerseOf(ref.watch(remoteConfigProvider));
    return SplashScreen(
      next: nextAfterSplash(_s, deepLink: widget.deepLink),
      hold: splashHold(_s, _today),
      verse: verse,
      verseCaption: caption,
    );
  }
}
