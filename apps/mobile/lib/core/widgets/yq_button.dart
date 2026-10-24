import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'liquid_glass.dart';

enum YqButtonKind { primary, secondary, text }

/// Buttons (spec §2.4): primary = dark ink pill 56 · secondary = glass pill · text = lapis.
/// One primary action per screen. While [loading], the button shows a spinner and ignores taps.
class YqButton extends StatelessWidget {
  const YqButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = YqButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  const YqButton.secondary({super.key, required this.label, required this.onPressed, this.icon, this.loading = false, this.expand = true})
      : kind = YqButtonKind.secondary;

  const YqButton.text({super.key, required this.label, required this.onPressed, this.icon, this.loading = false, this.expand = false})
      : kind = YqButtonKind.text;

  final String label;
  final VoidCallback? onPressed;
  final YqButtonKind kind;
  final Widget? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = switch (kind) {
      YqButtonKind.primary => YqColors.white,
      YqButtonKind.secondary => YqColors.ink,
      YqButtonKind.text => YqColors.lapis,
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else ...[
          if (icon != null) ...[icon!, const SizedBox(width: YqSpace.s)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: kind == YqButtonKind.text ? FontWeight.w500 : FontWeight.w700, color: fg),
            ),
          ),
        ],
      ],
    );

    final Widget body = switch (kind) {
      YqButtonKind.primary => AnimatedOpacity(
          duration: YqMotion.fast,
          opacity: enabled || loading ? 1 : 0.45,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl),
            decoration: BoxDecoration(
              color: YqColors.ink,
              borderRadius: BorderRadius.circular(YqRadii.pill),
              boxShadow: const [BoxShadow(color: Color(0x4D0A1530), blurRadius: 24, spreadRadius: -12, offset: Offset(0, 12))],
            ),
            child: content,
          ),
        ),
      YqButtonKind.secondary => AnimatedOpacity(
          duration: YqMotion.fast,
          opacity: enabled || loading ? 1 : 0.45,
          child: SizedBox(
            height: 56,
            child: LiquidGlass(
              radius: YqRadii.pill,
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl),
              highlight: false,
              child: content,
            ),
          ),
        ),
      YqButtonKind.text => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: YqSpace.touch),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: YqSpace.s), child: content),
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? label : null,
      excludeSemantics: loading,
      child: _Pressable(onTap: enabled ? onPressed : null, child: body),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(scale: _down && !reduce ? 0.985 : 1, duration: YqMotion.fast, curve: YqMotion.ease, child: widget.child),
    );
  }
}
