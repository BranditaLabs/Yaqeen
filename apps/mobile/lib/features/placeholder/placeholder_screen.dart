import 'package:flutter/material.dart';

import '../../core/theme/typography.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../l10n/gen/app_localizations.dart';

enum PlaceholderTitle { quran, prayer, challenge, profile }

/// Temporary tab body until each feature module is built.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.titleKey});

  final PlaceholderTitle titleKey;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title = switch (titleKey) {
      PlaceholderTitle.quran => t.tabQuran,
      PlaceholderTitle.prayer => t.tabPrayer,
      PlaceholderTitle.challenge => t.challengeTitle,
      PlaceholderTitle.profile => t.tabProfile,
    };
    return AmbientBackground(
      lights: titleKey == PlaceholderTitle.challenge ? AmbientBackground.goldLights : AmbientBackground.defaultLights,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: LiquidGlass(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: YqText.display),
                  const SizedBox(height: 8),
                  Text(t.comingSoon, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
