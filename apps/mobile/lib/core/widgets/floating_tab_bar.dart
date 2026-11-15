import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'outer_shadow.dart';
import 'yq_icon.dart';

/// One destination in the dock: a Yaqeen icon, or the profile avatar, and a label.
class YqTab {
  const YqTab({required YqIcons this.icon, required this.label})
      : avatar = null,
        initial = null;

  /// The profile destination: the person's [avatar] (e.g. `MeAvatar(size: 24)`) in a 24-pt circle
  /// with a lapis rim when active and a white rim otherwise; their [initial] (ink on ice) until one
  /// is given.
  const YqTab.avatar({this.avatar, required String this.initial, required this.label}) : icon = null;

  final YqIcons? icon;
  final Widget? avatar;
  final String? initial;
  final String label;

  bool get isAvatar => initial != null;
}

/// The dock (docs/DESIGN_SYSTEM.md §4): a floating porcelain-glass capsule with equal slots, each an
/// icon over a small label. A soft lapis glass pill sits under the active slot and glides to the
/// next one on a spring (it jumps when reduce-motion is on).
///
/// Symmetric by construction: every slot is exactly `width / tabs.length`, icons are 24 pt on
/// one baseline, and the pill is the slot inset by [_inset] on every side. Slots run in reading
/// order (start → end), so the first tab is on the right in Arabic. Idle, it paints nothing: the
/// pill only moves while its spring runs.
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({super.key, required this.tabs, required this.currentIndex, required this.onSelect});

  final List<YqTab> tabs;
  final int currentIndex;

  /// Called on every tap, including the active tab (the shell pops that tab back to its root).
  final ValueChanged<int> onSelect;

  /// Capsule height.
  static const height = 64.0;

  /// The capsule never grows wider than this (tablets, landscape); it stays centred.
  static const maxWidth = 520.0;

  static const _inset = 4.0;
  static const _labelSize = 11.0;
  static const _maxTextScale = 1.3;

  /// Distance from the bottom of the screen to the capsule: just above the iOS home indicator,
  /// and clear of Android's gesture handle or button bar.
  static double gapFor(TargetPlatform platform, double systemBottom) => switch (platform) {
        TargetPlatform.iOS when systemBottom > 0 => math.max(systemBottom - 12, YqSpace.m),
        _ => math.max(systemBottom, YqSpace.l),
      };

  /// What scrolling content under the dock must leave clear: the gap, the capsule and a breath.
  static double clearanceFor(TargetPlatform platform, double systemBottom) => gapFor(platform, systemBottom) + height + YqSpace.l;

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar> with SingleTickerProviderStateMixin {
  // Calm, barely-there overshoot; settles in about 350 ms.
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.86);

  /// The pill's position in slots (0 = first tab), driven by a spring.
  late final AnimationController _pill = AnimationController.unbounded(vsync: this, value: widget.currentIndex.toDouble());

  @override
  void didUpdateWidget(FloatingTabBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex == widget.currentIndex) return;
    final target = widget.currentIndex.toDouble();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pill.value = target;
    } else {
      _pill.animateWith(SpringSimulation(_spring, _pill.value, target, _pill.velocity));
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _tap(int i) {
    if (i != widget.currentIndex) HapticFeedback.selectionClick();
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.tabs.length;
    final radius = BorderRadius.circular(YqRadii.pill);
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [YqColors.white.withValues(alpha: 0xEB / 255), YqColors.white.withValues(alpha: 0xD6 / 255)],
        ),
        border: Border.all(color: YqColors.white.withValues(alpha: 0xF2 / 255)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FloatingTabBar._inset),
        child: LayoutBuilder(
          builder: (context, box) {
            final slot = box.maxWidth / n;
            return Stack(
              children: [
                AnimatedBuilder(
                  animation: _pill,
                  builder: (context, child) => PositionedDirectional(
                    start: _pill.value.clamp(0.0, n - 1.0) * slot,
                    top: 0,
                    bottom: 0,
                    width: slot,
                    child: child!,
                  ),
                  child: const _Pill(),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      SizedBox(
                        width: slot,
                        child: _Slot(tab: widget.tabs[i], active: i == widget.currentIndex, index: i, count: n, onTap: () => _tap(i)),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );

    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FloatingTabBar.maxWidth),
        child: SizedBox(
          height: FloatingTabBar.height,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: RepaintBoundary(
              // Shadows outside the capsule only, so the translucent glass never looks smudged.
              child: OuterShadow(
                borderRadius: radius,
                shadows: [
                  BoxShadow(color: YqColors.ink.withValues(alpha: 0x2E / 255), blurRadius: 36, spreadRadius: -14, offset: const Offset(0, 16)),
                  BoxShadow(color: YqColors.ink.withValues(alpha: 0x14 / 255), blurRadius: 4, offset: const Offset(0, 1)),
                ],
                child: ClipRRect(
                  borderRadius: radius,
                  // The one live blur in the app: fixed chrome only (docs/DESIGN_SYSTEM.md §6).
                  child: YqGlassConfig.enableBlur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar) : bar,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The active state: a soft lapis glass pill with a white rim at its top edge.
class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YqRadii.pill),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [YqColors.lapis.withValues(alpha: 0.07), YqColors.lapis.withValues(alpha: 0.13)],
          ),
          border: Border.all(color: YqColors.lapis.withValues(alpha: 0.10)),
        ),
      );
}

class _Slot extends StatefulWidget {
  const _Slot({required this.tab, required this.active, required this.index, required this.count, required this.onTap});

  final YqTab tab;
  final bool active;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final color = active ? YqColors.lapis : YqColors.muted;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: FloatingTabBar._maxTextScale);
    final icon = tab.isAvatar
        ? _AvatarIcon(avatar: tab.avatar, initial: tab.initial!, active: active)
        : YqIcon(tab.icon!, size: 24, tone: active ? YqIconTone.active : YqIconTone.idle);
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: tab.label,
      // «1 of 5», like the platform tab bars.
      hint: kIsWeb ? null : MaterialLocalizations.of(context).tabLabel(tabIndex: widget.index + 1, tabCount: widget.count),
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.92 : 1,
            duration: YqMotion.fast,
            curve: YqMotion.ease,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(dimension: 24, child: Center(child: icon)),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs),
                  // Long labels («Challenge» at 1.3×) shrink to fit their slot instead of clipping.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: YqMotion.fast,
                      curve: YqMotion.ease,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: FloatingTabBar._labelSize,
                        height: 1.2,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: color,
                      ),
                      child: Text(tab.label, maxLines: 1, softWrap: false, textScaler: scaler),
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

/// The profile "icon": the person's avatar in a circle, ringed lapis when active and white
/// otherwise. Without an avatar widget, their initial in ink on ice (no gold — gold is for
/// achievement only).
class _AvatarIcon extends StatelessWidget {
  const _AvatarIcon({required this.avatar, required this.initial, required this.active});

  final Widget? avatar;
  final String initial;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: YqMotion.fast,
        curve: YqMotion.ease,
        width: 24,
        height: 24,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: YqColors.ice,
          border: Border.all(color: active ? YqColors.lapis : YqColors.white, width: 1.5),
        ),
        child: avatar != null
            ? ClipOval(child: SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: avatar)))
            : Text(
                initial,
                // An icon, not text: it keeps its size at any text scale.
                textScaler: TextScaler.noScaling,
                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: YqColors.ink),
              ),
      );
}
