import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/floating_tab_bar.dart';
import '../core/widgets/yq_icon.dart';
import '../l10n/gen/app_localizations.dart';

/// Hosts the five tab branches and floats the liquid tab bar above them.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          // Soft fade so content dissolves under the floating bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 130 + bottomInset,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00F3F6FB), Color(0xEBF3F6FB)],
                    stops: [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: YqSpace.gutter,
            right: YqSpace.gutter,
            bottom: bottomInset > 0 ? bottomInset : 26,
            child: FloatingTabBar(
              currentIndex: navigationShell.currentIndex,
              onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
              avatarInitial: 'أ',
              profileLabel: t.tabProfile,
              tabs: [
                YqTab(icon: YqIcons.home, label: t.tabHome),
                YqTab(icon: YqIcons.quran, label: t.tabQuran),
                YqTab(icon: YqIcons.prayer, label: t.tabPrayer),
                YqTab(icon: YqIcons.challenge, label: t.tabChallenge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
