import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
import 'liquid_glass.dart';

enum YqButtonKind { primary, secondary, text }

/// Buttons (spec §2.4): primary = dark ink pill 56 · secondary = glass pill · text = lapis.
/// One primary action per screen. While [loading], the button keeps its label (and its exact size),
/// ignores taps, and the label shimmers with the skeleton sweep — never a spinner (spec §2 loading
/// rule). Under reduce-motion the label stays still at 60%. Screen readers hear «{label}» with the
/// value «جارٍ التنفيذ».
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
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: YqSpace.s)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: kind == YqButtonKind.text ? FontWeight.w500 : FontWeight.w700, color: fg),
          ),
        ),
      ],
    );
    // The same row while loading, so the button never changes size.
    final Widget content = loading ? _ShimmerLabel(child: row) : row;

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
      value: loading ? Localizations.of<AppLocalizations>(context, AppLocalizations)?.skWorking : null,
      excludeSemantics: loading,
      child: _Pressable(onTap: enabled ? onPressed : null, child: body),
    );
  }
}

/// The label of a working button: a soft light band sweeps across it with the reading direction
/// (right → left in Arabic) on the skeleton's 1600 ms easeInOutSine period. The text itself fades
/// to half and the band lifts it back to full, so it reads on ink, glass and plain alike. Under
/// reduce-motion the label is static at 60%.
class _ShimmerLabel extends StatefulWidget {
  const _ShimmerLabel({required this.child});
  final Widget child;

  /// Same sweep as `YqSkeleton.period` (kept here so the button doesn't depend on the states file).
  static const period = Duration(milliseconds: 1600);

  @override
  State<_ShimmerLabel> createState() => _ShimmerLabelState();
}

class _ShimmerLabelState extends State<_ShimmerLabel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _ShimmerLabel.period);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduce) return Opacity(opacity: 0.6, child: widget.child);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_c.value);
          final x = -2.2 + 4.4 * t; // band centre travels from beyond one edge to beyond the other
          final c = rtl ? -x : x;
          return ShaderMask(
            // Keeps the label's own colour and scales its alpha: 50% at rest, full under the band.
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(c - 1.1, -0.25),
              end: Alignment(c + 1.1, 0.25),
              colors: const [Color(0x80FFFFFF), Color(0x80FFFFFF), Color(0xFFFFFFFF), Color(0x80FFFFFF), Color(0x80FFFFFF)],
              stops: const [0, 0.32, 0.5, 0.68, 1],
            ).createShader(rect),
            child: child,
          );
        },
        child: widget.child,
      ),
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
