import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../format.dart';

/// Tabular (equal-width) figures, so a changing number never shifts the layout around it.
TextStyle? tabular(TextStyle? style) =>
    (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// A number that counts up to [value] on first show (and glides between values when it changes),
/// in Western digits with tabular figures. The final text reserves its width from the first frame,
/// so nothing around it moves while it counts. Screen readers get the final value at once; under
/// reduce-motion it is simply the final text.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style, this.builder, this.textAlign, this.alignment = AlignmentDirectional.center});
  final int value;
  final TextStyle? style;

  /// Wraps the formatted number in a sentence, e.g. «{n} نقطة».
  final String Function(String n)? builder;
  final TextAlign? textAlign;

  /// Where the counting text sits inside the reserved (final) width.
  final AlignmentGeometry alignment;

  String _text(num v) => builder == null ? YqFormat.number(v.round()) : builder!(YqFormat.number(v.round()));

  @override
  Widget build(BuildContext context) {
    final s = tabular(style);
    final last = _text(value);
    if (reduceMotion(context)) return Text(last, style: s, textAlign: textAlign);
    return Semantics(
      label: last,
      excludeSemantics: true,
      child: Stack(
        alignment: alignment,
        children: [
          // The final text holds the width; the counting text is drawn over it.
          Visibility.maintain(visible: false, child: Text(last, style: s, textAlign: textAlign)),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: Duration(milliseconds: 700 + math.min(value.abs(), 600)),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(_text(v), style: s, textAlign: textAlign, maxLines: 1, softWrap: false),
          ),
        ],
      ),
    );
  }
}

/// A number whose digits roll up into place, staggered (the same motion as the public card's
/// rolling digits: 0.9 em from below, 900 ms, 90 ms apart, a soft overshoot). When the value
/// changes later, only the digits that changed roll — up for a larger number, down for a smaller
/// one. Tabular figures, Western digits; screen readers get the number at once; plain text under
/// reduce-motion.
class YqRollingNumber extends StatefulWidget {
  const YqRollingNumber({super.key, required this.value, required this.style, this.format, this.roll = true});

  final int value;
  final TextStyle style;

  /// Defaults to [YqFormat.number] (Western digits, grouped).
  final String Function(int v)? format;

  /// False shows the first value at once (only later changes roll).
  final bool roll;

  static const intro = Duration(milliseconds: 900);
  static const step = Duration(milliseconds: 90);

  /// The public card's curve: cubic-bezier(.2,.9,.25,1.15).
  static const curve = Cubic(0.2, 0.9, 0.25, 1.15);

  @override
  State<YqRollingNumber> createState() => _YqRollingNumberState();
}

class _YqRollingNumberState extends State<YqRollingNumber> with SingleTickerProviderStateMixin {
  AnimationController? _intro;
  bool _up = true;

  String get _text => (widget.format ?? YqFormat.number)(widget.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro != null || !widget.roll || reduceMotion(context)) return;
    final n = _text.length;
    _intro = AnimationController(vsync: this, duration: YqRollingNumber.intro + YqRollingNumber.step * math.max(0, n - 1))..forward();
  }

  @override
  void didUpdateWidget(YqRollingNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  void dispose() {
    _intro?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final style = tabular(widget.style)!;
    if (reduceMotion(context)) return Text(text, style: style, textDirection: TextDirection.ltr);
    final chars = text.characters.toList();
    final n = chars.length;
    final intro = _intro;
    final total = intro?.duration?.inMicroseconds ?? 1;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          for (var i = 0; i < n; i++)
            // Keyed by place from the right, so 99 → 100 rolls units into units.
            KeyedSubtree(
              key: ValueKey(n - i),
              child: _Digit(
                char: chars[i],
                style: style,
                up: _up,
                intro: intro,
                introCurve: Interval(
                  YqRollingNumber.step.inMicroseconds * i / total,
                  (YqRollingNumber.step.inMicroseconds * i + YqRollingNumber.intro.inMicroseconds) / total,
                  curve: YqRollingNumber.curve,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Digit extends StatelessWidget {
  const _Digit({required this.char, required this.style, required this.up, this.intro, required this.introCurve});
  final String char;
  final TextStyle style;
  final bool up;

  /// The number's first roll (null when it showed at once); this digit's slice is [introCurve].
  final Animation<double>? intro;
  final Curve introCurve;

  @override
  Widget build(BuildContext context) {
    Widget glyph = Text(char, key: ValueKey(char), style: style, textDirection: TextDirection.ltr);
    final a = intro;
    if (a != null) {
      final inner = glyph;
      glyph = AnimatedBuilder(
        animation: a,
        child: inner,
        builder: (context, child) {
          final v = introCurve.transform(a.value);
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: FractionalTranslation(translation: Offset(0, 0.9 * (1 - v)), child: child),
          );
        },
      );
    }
    // Later changes: the old digit leaves one way while the new one arrives from the other.
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Motion.emphasised,
        switchInCurve: Motion.emphasisedCurve,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, if (current != null) current]),
        transitionBuilder: (child, animation) {
          // Transitions are rebuilt every build (a new closure), so the digit leaving is recognised.
          final incoming = child.key == ValueKey(char);
          final from = up ? 0.9 : -0.9;
          final offset = incoming
              ? Tween(begin: Offset(0, from), end: Offset.zero).animate(animation)
              : Tween(begin: Offset(0, -from), end: Offset.zero).animate(animation);
          return FadeTransition(opacity: animation, child: SlideTransition(position: offset, child: child));
        },
        child: KeyedSubtree(key: ValueKey(char), child: glyph),
      ),
    );
  }
}
