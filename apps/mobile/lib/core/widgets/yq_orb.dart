import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'liquid_glass.dart';
import 'outer_shadow.dart';

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
              color: glow ? const Color(0x59C6A867) : const Color(0x260F1A36),
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
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.ink),
        ),
        Text(
          status,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.3, color: statusColor ?? YqColors.muted),
        ),
      ],
    );
    if (onTap == null && onLongPress == null) return frame;
    return GlassTap(onTap: onTap, onLongPress: onLongPress, semanticLabel: semanticLabel, child: frame);
  }
}

/// Up to three orbs, evenly spaced.
class YqOrbRow extends StatelessWidget {
  const YqOrbRow({super.key, required this.orbs});
  final List<Widget> orbs;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final o in orbs) Expanded(child: o)],
      );
}
