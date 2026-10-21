import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Global switch: blur is expensive on low-end Android. Set to false at
/// startup (e.g. from a device-tier check) to fall back to frosted fills.
abstract final class YqGlassConfig {
  static bool enableBlur = true;
}

enum GlassTone { clear, gold }

/// The liquid-glass surface used for every card, pill and bar in Yaqeen.
///
/// Translucent white, background blur, a hairline white rim, a specular
/// highlight along the top edge and a soft drop shadow.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = YqRadii.card,
    this.padding = const EdgeInsets.all(YqSpace.l),
    this.tone = GlassTone.clear,
    this.opacity = 0.58,
    this.blur = 12,
    this.highlight = true,
    this.shadow = true,
    this.border,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final GlassTone tone;
  final double opacity;

  /// Gaussian sigma. CSS blur(24px) ≈ sigma 12.
  final double blur;
  final bool highlight;
  final bool shadow;
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final fill = tone == GlassTone.gold
        ? LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [YqColors.cream.withAlpha(224), YqColors.sand.withAlpha(190)],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              YqColors.white.withAlpha((opacity * 255 + 20).clamp(0, 255).round()),
              YqColors.white.withAlpha((opacity * 255).round()),
            ],
          );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: fill,
        borderRadius: shape,
        border: Border.fromBorderSide(border ?? const BorderSide(color: Color(0xE6FFFFFF))),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (highlight) {
      surface = Stack(
        children: [
          surface,
          Positioned(
            top: 1,
            left: radius * 0.8,
            right: radius * 0.8,
            height: 22,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(YqRadii.pill),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final clipped = ClipRRect(
      borderRadius: shape,
      child: YqGlassConfig.enableBlur && blur > 0
          ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: surface)
          : surface,
    );

    if (!shadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: tone == GlassTone.gold ? const Color(0x337C6127) : const Color(0x260F1A36),
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: clipped,
    );
  }
}

/// Tappable glass card with a gentle press-scale and haptic tick.
class GlassTap extends StatefulWidget {
  const GlassTap({super.key, required this.child, required this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<GlassTap> createState() => _GlassTapState();
}

class _GlassTapState extends State<GlassTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: YqMotion.fast,
          curve: YqMotion.ease,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Round 44pt glass icon button (back, settings, search…).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip, this.size = YqSpace.touch});

  final Widget icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GlassTap(
        onTap: onPressed,
        semanticLabel: tooltip,
        child: SizedBox.square(
          dimension: size,
          child: LiquidGlass(
            radius: YqRadii.pill,
            padding: EdgeInsets.zero,
            highlight: false,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
