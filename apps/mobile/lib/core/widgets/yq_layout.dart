import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'liquid_glass.dart';
import 'yq_icon.dart';

/// Shared screen geometry, so every screen lines up the same way.
abstract final class YqInsets {
  /// The page gutter on both sides (directional, so RTL and LTR match).
  static const page = EdgeInsetsDirectional.symmetric(horizontal: YqSpace.gutter);

  /// Bottom space a scrolling screen leaves under its last item: the bottom safe area plus
  /// [extra]. Inside a tab the shell counts the floating dock as safe area (lib/app/shell.dart),
  /// so this one value clears the dock on tab screens and the home indicator everywhere else.
  static double bottom(BuildContext context, [double extra = YqSpace.xxl]) => MediaQuery.paddingOf(context).bottom + extra;
}

/// Back chevron that points the way back in the current text direction (right in RTL).
class YqBackButton extends StatelessWidget {
  const YqBackButton({super.key, this.label, this.onPressed});

  /// Accessibility label, e.g. «رجوع إلى التحدي». Defaults to the platform "Back".
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      tooltip: label ?? MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ??
          () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
      icon: const Icon(Icons.chevron_left_rounded, color: YqColors.ink, size: 26),
    );
  }
}

/// Screen header: back · title (+ subtitle) · actions.
class YqTopBar extends StatelessWidget {
  const YqTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.back = true,
    this.backLabel,
    this.actions = const [],
    this.large = false,
  });

  final String title;
  final String? subtitle;
  final bool back;
  final String? backLabel;
  final List<Widget> actions;

  /// Large display title for tab roots.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: YqSpace.s, bottom: YqSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (back) ...[YqBackButton(label: backLabel), const SizedBox(width: YqSpace.m)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: large ? YqText.display.copyWith(fontSize: 28) : text.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle != null) Text(subtitle!, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: YqSpace.s), a],
        ],
      ),
    );
  }
}

/// Glass card with an optional title row (spec §2.4 `YqSection`).
class YqSection extends StatelessWidget {
  const YqSection({
    super.key,
    this.title,
    this.action,
    required this.child,
    this.padding = const EdgeInsets.all(YqSpace.l),
    this.tone = GlassTone.clear,
  });

  final String? title;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final GlassTone tone;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      padding: padding,
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Semantics(header: true, child: Text(title!, style: Theme.of(context).textTheme.titleMedium))),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: YqSpace.m),
          ],
          child,
        ],
      ),
    );
  }
}

/// 40-pt rounded icon tile used at the start of list rows.
class YqIconTile extends StatelessWidget {
  const YqIconTile(this.icon, {super.key, this.tone = YqIconTone.active, this.gold = false, this.size = 40});

  final YqIcons icon;
  final YqIconTone tone;
  final bool gold;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gold ? const Color(0x29C6A867) : const Color(0x141F3F94),
        borderRadius: BorderRadius.circular(YqRadii.chip),
      ),
      child: YqIcon(icon, size: size * 0.5, tone: gold ? YqIconTone.gold : tone),
    );
  }
}

/// List row: leading · title + subtitle · trailing. Whole row is the touch target (≥ 44 pt).
class YqListRow extends StatelessWidget {
  const YqListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.dense = false,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool dense;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: dense ? YqSpace.touch : 56),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? YqSpace.xs : YqSpace.s),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: YqSpace.m)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.4, color: titleColor)),
                  if (subtitle != null) Text(subtitle!, style: text.bodySmall?.copyWith(fontSize: 11.5, height: 1.5)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: YqSpace.s), trailing!] else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: YqColors.muted),
          ],
        ),
      ),
    );
    if (onTap == null) return Semantics(label: semanticLabel, child: row);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(YqRadii.chip),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: row,
      ),
    );
  }
}

/// Hairline between rows inside a section.
class YqDivider extends StatelessWidget {
  const YqDivider({super.key});
  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: Color(0x80DCE4F2));
}

/// Selectable pill chip (filters, goal picker, reminder minutes).
class YqChip extends StatelessWidget {
  const YqChip({super.key, required this.label, required this.selected, required this.onTap, this.semanticLabel});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: YqMotion.fast,
          curve: YqMotion.ease,
          constraints: const BoxConstraints(minHeight: 40, minWidth: YqSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
          decoration: BoxDecoration(
            color: selected ? YqColors.lapis : const Color(0x9EFFFFFF),
            borderRadius: BorderRadius.circular(YqRadii.chip),
            border: Border.all(color: selected ? YqColors.lapis : const Color(0xE6FFFFFF)),
            boxShadow:
                selected ? const [BoxShadow(color: Color(0x4D1F3F94), blurRadius: 14, spreadRadius: -8, offset: Offset(0, 6))] : null,
          ),
          // Center with factors so the chip hugs its label (a Container alignment would stretch it).
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? YqColors.white : YqColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Onboarding progress: N dashes, the first [step] filled lapis (spec §5.4).
class YqStepper extends StatelessWidget {
  const YqStepper({super.key, required this.step, this.total = 5, required this.semanticLabel});

  final int step;
  final int total;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedContainer(
                duration: YqMotion.base,
                width: i < step ? 22 : 14,
                height: 4,
                decoration:
                    BoxDecoration(color: i < step ? YqColors.lapis : YqColors.line, borderRadius: BorderRadius.circular(YqRadii.pill)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Page scaffold: porcelain ambient ground, safe area and the 20-pt gutter.
class YqPage extends StatelessWidget {
  const YqPage({super.key, required this.children, this.bottomPadding = 40, this.controller, this.header});

  final List<Widget> children;
  final double bottomPadding;
  final ScrollController? controller;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: YqInsets.page.add(EdgeInsetsDirectional.only(top: YqSpace.s, bottom: YqInsets.bottom(context, bottomPadding))),
      children: [if (header != null) header!, ...children],
    );
  }
}

/// A glass group of rows separated by hairlines (settings, codes, links).
class YqGroup extends StatelessWidget {
  const YqGroup({super.key, required this.children, this.gold = false});
  final List<Widget> children;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      tone: gold ? GlassTone.gold : GlassTone.clear,
      highlight: false,
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.xs),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const YqDivider(),
            children[i],
          ],
        ],
      ),
    );
  }
}
