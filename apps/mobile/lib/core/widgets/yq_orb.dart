import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'liquid_glass.dart';
import 'outer_shadow.dart';
import 'yq_rise.dart';

/// A complication (docs/DESIGN_SYSTEM.md §4): a glass disc with a live instrument inside, a title
/// and one status line. Glows gold when its goal is met. Three per row at most ([YqOrbRow]).
class YqOrb extends StatelessWidget {
  const YqOrb({
    super.key,
    required this.disc,
    required this.title,
    required this.status,
    this.glow = false,
    this.statusColor,
    this.size = defaultSize,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.statusChild,
    this.swapText = false,
  });

  static const defaultSize = 100.0;

  final Widget disc;
  final String title;
  final String status;
  final bool glow;
  final Color? statusColor;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  /// Replaces the status line's text (e.g. a `CountUp` in the same style, [statusStyle]).
  final Widget? statusChild;

  /// Cross-fade the title and status when they change (a face that flips), over 200 ms.
  final bool swapText;

  /// The status line's style.
  static TextStyle statusStyle([Color? color]) => TextStyle(fontSize: 11, height: 1.3, color: color ?? YqColors.muted);

  /// A centred numeral for a disc.
  static Widget number(String value, {double size = 22, Color color = YqColors.ink}) => Center(
        child: Text(
          value,
          textDirection: TextDirection.ltr,
          style: YqText.numeral.copyWith(fontSize: size, fontWeight: FontWeight.w500, color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final frame = Column(
      children: [
        OuterShadow(
          circle: true,
          shadows: [
            BoxShadow(
              color: glow ? const Color(0x59C6A867) : const Color(0x260A1530),
              blurRadius: glow ? 28 : 22,
              spreadRadius: glow ? -4 : -10,
              offset: const Offset(0, 10),
            ),
          ],
          child: AnimatedContainer(
            duration: YqMotion.base,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: glow ? const [YqColors.cream, YqColors.sand] : const [Color(0xE6FFFFFF), Color(0xA6FFFFFF)],
              ),
              border: Border.all(color: const Color(0xF2FFFFFF), width: 1.2),
            ),
            child: RepaintBoundary(child: Padding(padding: const EdgeInsets.all(6), child: disc)),
          ),
        ),
        const SizedBox(height: 8),
        // The labels keep a small gutter from the neighbouring orb's, and the title stays on one
        // line on one baseline across the row: a long title shrinks to fit instead of being cut
        // off or pushing its status line down.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs),
          child: Column(
            children: [
              _swap(
                context,
                FittedBox(
                  key: ValueKey('t:$title'),
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.ink),
                  ),
                ),
              ),
              _swap(
                context,
                statusChild ??
                    Text(
                      status,
                      key: ValueKey('s:$status'),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: statusStyle(statusColor),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
    if (onTap == null && onLongPress == null) return frame;
    // An instrument under the thumb: a firmer press than a card (0.96), a selection haptic on tap.
    return GlassTap(onTap: onTap, onLongPress: onLongPress, semanticLabel: semanticLabel, pressScale: 0.96, child: frame);
  }

  Widget _swap(BuildContext context, Widget child) => !swapText
      ? child
      : AnimatedSwitcher(
          duration: motionOr(context, Motion.fade),
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
          child: child,
        );
}

/// Up to three orbs in equal columns (centred on 1/6, 3/6 and 5/6 of the row for three). With
/// [rise] each orb rises in on the page's first build, 40 ms apart (`YqRise`; skipped under
/// reduce-motion and for orbs that appear after the page has opened).
class YqOrbRow extends StatelessWidget {
  const YqOrbRow({super.key, required this.orbs, this.rise = false});
  final List<Widget> orbs;
  final bool rise;

  static const stagger = Duration(milliseconds: 40);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < orbs.length; i++)
            Expanded(child: rise ? YqRise(order: i, stagger: stagger, distance: 10, child: orbs[i]) : orbs[i]),
        ],
      );
}
