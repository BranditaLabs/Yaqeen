import 'package:flutter/material.dart';

import '../../core/theme/typography.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/yq_layout.dart';
import '../../l10n/gen/app_localizations.dart';

/// Temporary body for a route whose screen is not built yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const Align(alignment: AlignmentDirectional.centerStart, child: YqBackButton()),
                Expanded(
                  child: Center(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
