import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Pill switch. In RTL the "on" knob sits at the visual start (left).
class YqSwitch extends StatelessWidget {
  const YqSwitch({super.key, required this.value, required this.onChanged, this.activeColor = YqColors.lapis, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: YqMotion.base,
          curve: YqMotion.ease,
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? activeColor : YqColors.line,
            borderRadius: BorderRadius.circular(YqRadii.pill),
          ),
          child: AnimatedAlign(
            duration: YqMotion.base,
            curve: YqMotion.ease,
            alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: YqColors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x330A1530), blurRadius: 6, offset: Offset(0, 2))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass segmented control (prayer tabs, azkar times, font sizes…).
class YqSegmented<T> extends StatelessWidget {
  const YqSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x6BFFFFFF),
        borderRadius: BorderRadius.circular(YqRadii.pill),
        border: Border.all(color: const Color(0xD9FFFFFF)),
      ),
      child: Row(
        children: [
          for (final (value, label) in segments)
            // Width follows the label (within limits), so «Morning azkar» gets the room it needs
            // next to «Sleep» and every label stays at — or very near — its real size.
            Expanded(
              flex: label.characters.length.clamp(6, 20),
              child: Semantics(
                button: true,
                selected: value == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (value == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(value);
                  },
                  child: AnimatedContainer(
                    duration: YqMotion.fast,
                    curve: YqMotion.ease,
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: YqSpace.xs),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == selected ? YqColors.white : const Color(0x00FFFFFF),
                      borderRadius: BorderRadius.circular(YqRadii.pill),
                      boxShadow:
                          value == selected ? const [BoxShadow(color: Color(0x140A1530), blurRadius: 8, offset: Offset(0, 2))] : null,
                    ),
                    // One line in every segment, so the pills stay equal and round: a long label
                    // (bold when selected, English, large text) shrinks to fit instead of wrapping.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: value == selected ? FontWeight.w700 : FontWeight.w400,
                          color: value == selected ? YqColors.lapis : YqColors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thin progress line (wird, journey, downloads).
class YqProgressLine extends StatelessWidget {
  const YqProgressLine({
    super.key,
    required this.value,
    this.color = YqColors.lapis,
    this.track = const Color(0x1A1F3F94),
    this.height = 3,
  });

  final double value;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(YqRadii.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0, 1),
              child: ColoredBox(color: color, child: SizedBox(height: height)),
            ),
          ],
        ),
      ),
    );
  }
}
