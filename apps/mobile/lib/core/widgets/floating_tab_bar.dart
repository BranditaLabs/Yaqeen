import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/living_sky.dart';
import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'outer_shadow.dart';
import 'yq_icon.dart';

class YqTab {
  const YqTab({required this.icon, required this.label});
  final YqIcons icon;
  final String label;
}

/// The living dock: a floating porcelain-glass capsule. One ink "lens" lit by the living sky
/// slides under the active tab, which widens to show its label in gold; the last slot is the
/// profile avatar. A hairline thread along the top edge is the day itself — gold up to where the
/// sun is now (a moon dot at night), the same light as every screen's stage.
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

  static const height = 68.0;
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
            clipBehavior: Clip.none,
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
              const Positioned(left: 14, right: 14, top: -_pad + 1.5, height: 5, child: _DayThread()),
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
        // Outside the capsule only, so the translucent glass never looks smudged.
        child: OuterShadow(
          borderRadius: BorderRadius.circular(YqRadii.pill),
          shadows: const [
            BoxShadow(color: Color(0x4D0A1530), blurRadius: 44, spreadRadius: -16, offset: Offset(0, 22)),
            BoxShadow(color: Color(0x0F0A1530), blurRadius: 6, offset: Offset(0, 2)),
          ],
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

/// The lens under the active tab: ink glass with a glow of the current sky at its top edge.
class _Lens extends StatelessWidget {
  const _Lens();

  @override
  Widget build(BuildContext context) => LivingSky(
        builder: (context, sky) => AnimatedContainer(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YqRadii.pill),
            gradient: RadialGradient(
              center: const Alignment(0, -1.4),
              radius: 1.5,
              colors: [Color.lerp(YqColors.navy, sky.palette.glow, 0.35)!, YqColors.navy],
              stops: const [0, 0.85],
            ),
            border: Border.all(color: const Color(0x59E9D49E)),
            boxShadow: const [BoxShadow(color: Color(0x660A1530), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8))],
          ),
        ),
      );
}

/// The day as a hairline: mist track, gold up to the sun's position, and the sun (or a moon at
/// night) as a small glint. Mirrored in RTL like the stage's arc.
class _DayThread extends StatelessWidget {
  const _DayThread();

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: LivingSky(
          builder: (context, sky) => TweenAnimationBuilder<double>(
            tween: Tween(end: sky.position),
            duration: YqMotion.slow,
            curve: Curves.easeOutCubic,
            builder: (context, p, _) => CustomPaint(painter: _ThreadPainter(position: p, night: sky.phase == SkyPhase.night, rtl: rtl)),
          ),
        ),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter({required this.position, required this.night, required this.rtl});
  final double position;
  final bool night;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final p = position.clamp(0.0, 1.0);
    final x = size.width * (rtl ? 1 - p : p);
    final line = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line..color = const Color(0x40B8C6E0));
    canvas.drawLine(Offset(rtl ? size.width : 0, y), Offset(x, y), line..color = night ? const Color(0x991F3F94) : const Color(0xCCC6A867));
    final glint = Offset(x, y);
    canvas.drawCircle(glint, 5, Paint()..color = night ? const Color(0x331F3F94) : const Color(0x55E9D49E));
    canvas.drawCircle(glint, 2.6, Paint()..color = night ? YqColors.lapis : YqColors.gold);
  }

  @override
  bool shouldRepaint(_ThreadPainter old) => old.position != position || old.night != night || old.rtl != rtl;
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
                AnimatedSwitcher(
                  duration: FloatingTabBar._duration,
                  child: YqIcon(tab.icon, key: ValueKey(active), size: 22, tone: active ? YqIconTone.light : YqIconTone.idle),
                ),
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
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.goldLight),
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
