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

/// Floating liquid-glass capsule. One glass "lens" slides under the active tab, which widens to
/// show its label; the last slot is the profile avatar.
///
/// Fluid by construction: every slot width and the lens position derive from the same target
/// layout and animate on the same curve and duration, so nothing jumps or overlaps mid-way, and
/// the label fades and unfolds instead of popping in. Positions are directional (RTL-correct).
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
  static const _pad = 7.0;
  static const _slot = 52.0;
  static const _duration = Duration(milliseconds: 420);
  static const _curve = Curves.easeOutCubic;

  /// Target width of every slot (tabs, then avatar) for the current selection.
  List<double> _widths(double inner) {
    final n = tabs.length;
    if (currentIndex >= n) {
      final each = ((inner - _slot) / n).clamp(_slot, double.infinity);
      return [for (var i = 0; i < n; i++) each, _slot];
    }
    final active = (inner - n * _slot).clamp(_slot, double.infinity);
    return [for (var i = 0; i < n; i++) i == currentIndex ? active : _slot, _slot];
  }

  @override
  Widget build(BuildContext context) {
    final profileActive = currentIndex == tabs.length;
    final bar = Container(
      height: height,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YqRadii.pill),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xBDFFFFFF), Color(0x75FFFFFF)],
        ),
        border: Border.all(color: const Color(0xEBFFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final widths = _widths(box.maxWidth);
          final lensIndex = currentIndex.clamp(0, widths.length - 1);
          final lensStart = widths.take(lensIndex).fold(0.0, (a, b) => a + b);
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: _duration,
                curve: _curve,
                start: lensStart,
                width: widths[lensIndex],
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  duration: YqMotion.fast,
                  opacity: profileActive ? 0 : 1,
                  child: const _Lens(),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _TabItem(tab: tabs[i], active: i == currentIndex, width: widths[i], onTap: () => _select(i)),
                  _Avatar(initial: avatarInitial, active: profileActive, label: profileLabel, onTap: () => _select(tabs.length)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: RepaintBoundary(
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
            child: YqGlassConfig.enableBlur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13), child: bar) : bar,
          ),
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

/// The glass lens under the active tab.
class _Lens extends StatelessWidget {
  const _Lens();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
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
        ),
      );
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.active, required this.width, required this.onTap});

  final YqTab tab;
  final bool active;
  final double width;
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
          duration: FloatingTabBar._duration,
          curve: FloatingTabBar._curve,
          width: width,
          height: FloatingTabBar._slot,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRect(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                YqIcon(tab.icon, size: 22, tone: active ? YqIconTone.active : YqIconTone.idle),
                Flexible(
                  // Unfolds (width) and fades together, so the icon stays centred when inactive.
                  child: AnimatedAlign(
                    duration: FloatingTabBar._duration,
                    curve: FloatingTabBar._curve,
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: active ? 1 : 0,
                    child: AnimatedOpacity(
                      duration: FloatingTabBar._duration,
                      curve: active ? const Interval(0.35, 1) : const Interval(0, 0.4),
                      opacity: active ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 7),
                        child: ExcludeSemantics(
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.lapis),
                          ),
                        ),
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
