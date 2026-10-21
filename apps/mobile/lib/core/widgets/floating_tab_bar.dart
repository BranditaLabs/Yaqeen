import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'yq_icon.dart';

class YqTab {
  const YqTab({required this.icon, required this.label});
  final YqIcons icon;
  final String label;
}

/// Floating liquid-glass capsule. The active tab sits inside a glass "lens"
/// that widens to show its label; the last slot is the profile avatar.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
    required this.avatarInitial,
    required this.profileLabel,
  });

  /// Main tabs (home, quran, prayer, challenge). Profile is index tabs.length.
  final List<YqTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final String avatarInitial;
  final String profileLabel;

  static const height = 66.0;

  @override
  Widget build(BuildContext context) {
    final profileActive = currentIndex == tabs.length;
    final bar = Container(
      height: height,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YqRadii.pill),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xBDFFFFFF), Color(0x75FFFFFF)],
        ),
        border: Border.all(color: const Color(0xEBFFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < tabs.length; i++)
            _TabItem(tab: tabs[i], active: i == currentIndex, onTap: () => _select(i)),
          _Avatar(initial: avatarInitial, active: profileActive, label: profileLabel, onTap: () => _select(tabs.length)),
        ],
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YqRadii.pill),
          boxShadow: const [
            BoxShadow(color: Color(0x4D0A1530), blurRadius: 44, spreadRadius: -16, offset: Offset(0, 22)),
            BoxShadow(color: Color(0x0F0A1530), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(YqRadii.pill),
          child: YqGlassConfig.enableBlur
              ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13), child: bar)
              : bar,
        ),
      ),
    );
  }

  void _select(int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    onSelect(i);
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.active, required this.onTap});

  final YqTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: YqMotion.base,
          curve: YqMotion.ease,
          height: 52,
          padding: EdgeInsetsDirectional.only(start: active ? 16 : 15, end: active ? 18 : 15),
          decoration: active
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(YqRadii.pill),
                  gradient: const RadialGradient(
                    center: Alignment(0, -1.2),
                    radius: 1.6,
                    colors: [Color(0xFAFFFFFF), Color(0xC7E9EFF9), Color(0xB8D6E0F2)],
                    stops: [0, 0.6, 1],
                  ),
                  border: Border.all(color: const Color(0xE6FFFFFF)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x661F3F94), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8)),
                  ],
                )
              : const BoxDecoration(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              YqIcon(tab.icon, size: 22, tone: active ? YqIconTone.active : YqIconTone.idle),
              AnimatedSize(
                duration: YqMotion.base,
                curve: YqMotion.ease,
                child: active
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(start: 7),
                        child: Text(
                          tab.label,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.lapis),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial, required this.active, required this.label, required this.onTap});

  final String initial;
  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 52,
          child: Center(
            child: AnimatedContainer(
              duration: YqMotion.base,
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF1E2B6), YqColors.gold],
                ),
                // Outer ring first, white gap painted over it.
                boxShadow: [
                  BoxShadow(color: active ? YqColors.lapis : const Color(0x73C6A867), spreadRadius: active ? 4 : 3),
                  const BoxShadow(color: YqColors.white, spreadRadius: 2),
                ],
              ),
              child: Text(initial, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3A2E10))),
            ),
          ),
        ),
      ),
    );
  }
}
