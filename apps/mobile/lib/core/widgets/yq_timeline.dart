import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'liquid_glass.dart';
import 'yq_icon.dart';

/// How a stop draws: a text row on the rail (prayers, steps) or a tappable glass pill (azkar,
/// routine, tasks).
enum StopStyle { line, pill }

/// One stop on a [YqTimeline].
class YqStop {
  const YqStop({
    required this.title,
    this.time,
    this.icon,
    this.style = StopStyle.line,
    this.subtitle,
    this.tag,
    this.goldTag = false,
    this.highlight = false,
    this.done = false,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  /// Wall-clock label at the start of the row, e.g. «3:53 م».
  final String? time;
  final String title;
  final YqIcons? icon;
  final StopStyle style;
  final String? subtitle;

  /// Small chip («التالية», «متاحة الآن»); gold with [goldTag].
  final String? tag;
  final bool goldTag;

  /// The next prayer, an open window, today's task: lapis dot, larger title (gold pill).
  final bool highlight;

  /// Completed: a gold check on the rail.
  final bool done;

  /// A control at the end of a line stop (a bell, a check).
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
}

/// A day, a plan or a list of steps as one vertical journey (docs/DESIGN_SYSTEM.md §4): past stops
/// recede (slate) over a gold thread, a «now» marker sits at the current position with what to do
/// now under it, the rest follows over mist.
class YqTimeline extends StatelessWidget {
  const YqTimeline({
    super.key,
    required this.stops,
    this.nowIndex,
    this.nowTime,
    this.nowLabel,
    this.nowChild,
    this.trailing,
    this.pastIndex,
    this.timeWidth = 58,
  });

  final List<YqStop> stops;

  /// The «now» marker goes before stops[nowIndex] (== stops.length: after the last); null = none.
  final int? nowIndex;
  final String? nowTime;
  final String? nowLabel;
  final Widget? nowChild;

  /// A plain block after the last stop (no dot).
  final Widget? trailing;

  /// Stops before this index read as past; defaults to [nowIndex] (0 when there is no marker).
  final int? pastIndex;

  /// Width of the time column; 0 hides it.
  final double timeWidth;

  static const _railWidth = 26.0;

  @override
  Widget build(BuildContext context) {
    final past = pastIndex ?? nowIndex ?? 0;
    final rows = <Widget>[];
    for (var i = 0; i <= stops.length; i++) {
      if (i == nowIndex) rows.add(_row(context, past: true, now: true, first: i == 0, last: false, child: _now()));
      if (i == stops.length) break;
      rows.add(
        _row(
          context,
          past: i < past,
          now: false,
          first: i == 0 && nowIndex != 0,
          last: i == stops.length - 1 && trailing == null,
          stop: stops[i],
          child: _stop(context, stops[i], past: i < past),
        ),
      );
    }
    if (trailing != null) {
      rows.add(_row(context, past: false, now: false, first: false, last: true, child: trailing!, plain: true));
    }
    return Column(children: rows);
  }

  Widget _row(
    BuildContext context, {
    required bool past,
    required bool now,
    required bool first,
    required bool last,
    required Widget child,
    YqStop? stop,
    bool plain = false,
  }) {
    final timeStyle = now
        ? YqText.numberSmall.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: YqColors.lapis)
        : YqText.numberSmall.copyWith(fontSize: 12, color: past ? YqColors.slate400 : YqColors.navy600);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (timeWidth > 0)
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(now ? (nowTime ?? '') : (stop?.time ?? ''), textAlign: TextAlign.end, style: timeStyle),
              ),
            ),
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(
                past: past,
                now: now,
                first: first,
                last: last,
                dot: plain
                    ? _Dot.none
                    : now
                        ? _Dot.now
                        : (stop?.done ?? false)
                            ? _Dot.done
                            : (stop?.highlight ?? false)
                                ? _Dot.highlight
                                : past
                                    ? _Dot.past
                                    : _Dot.future,
              ),
            ),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: YqSpace.m), child: child)),
        ],
      ),
    );
  }

  Widget _now() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(nowLabel ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.lapis)),
          ),
          if (nowChild != null) nowChild!,
        ],
      );

  Widget? _tag(YqStop m) => m.tag == null
      ? null
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: m.goldTag ? const Color(0x33C6A867) : const Color(0x1A1F3F94),
            borderRadius: BorderRadius.circular(YqRadii.pill),
          ),
          child: Text(
            m.tag!,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: m.goldTag ? YqColors.goldText : YqColors.lapis),
          ),
        );

  Widget _stop(BuildContext context, YqStop m, {required bool past}) {
    final titleColor = past && !m.highlight ? YqColors.slate400 : YqColors.ink;
    final tag = _tag(m);
    void tap() {
      HapticFeedback.selectionClick();
      m.onTap!();
    }

    if (m.style == StopStyle.line) {
      final row = Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: YqIcon(m.icon!, size: 18, tone: !past && m.highlight ? YqIconTone.active : YqIconTone.idle),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.title,
                          style: TextStyle(
                            fontSize: m.highlight ? 18 : 16,
                            fontWeight: m.highlight ? FontWeight.w700 : FontWeight.w500,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (tag != null) ...[const SizedBox(width: 8), tag],
                    ],
                  ),
                  if (m.subtitle != null) Text(m.subtitle!, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                ],
              ),
            ),
            if (m.trailing != null) m.trailing!,
          ],
        ),
      );
      if (m.onTap == null) return Semantics(label: m.semanticLabel, child: row);
      return Semantics(
        button: true,
        label: m.semanticLabel,
        child: InkWell(borderRadius: BorderRadius.circular(YqRadii.chip), onTap: tap, child: row),
      );
    }

    // Pill: a tappable glass card; gold while highlighted.
    return GlassTap(
      onTap: m.onTap == null ? null : tap,
      semanticLabel: m.semanticLabel ?? m.title,
      child: LiquidGlass(
        tone: m.highlight ? GlassTone.gold : GlassTone.clear,
        radius: YqRadii.tile,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        highlight: false,
        shadow: m.highlight,
        child: Row(
          children: [
            if (m.icon != null) ...[
              YqIcon(m.icon!, size: 18, tone: m.highlight ? YqIconTone.gold : YqIconTone.idle),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor)),
                  if (m.subtitle != null)
                    Text(
                      m.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: YqColors.muted),
                    ),
                ],
              ),
            ),
            if (tag != null) tag,
            if (m.trailing != null) ...[const SizedBox(width: 6), m.trailing!],
            if (m.onTap != null && m.trailing == null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: m.highlight ? YqColors.goldText : YqColors.slate400),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Dot { none, past, future, highlight, now, done }

/// The thread: gold where the journey has passed, mist ahead, with a dot per stop.
class _RailPainter extends CustomPainter {
  _RailPainter({required this.past, required this.now, required this.first, required this.last, required this.dot});

  final bool past;
  final bool now;
  final bool first;
  final bool last;
  final _Dot dot;

  static const _dotY = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const goldLine = Color(0x99C6A867);
    const mistLine = Color(0xFFDCE4F2);
    if (!first) canvas.drawLine(Offset(x, 0), Offset(x, _dotY), line..color = past ? goldLine : mistLine);
    if (!last) canvas.drawLine(Offset(x, _dotY), Offset(x, size.height), line..color = past && !now ? goldLine : mistLine);

    final c = Offset(x, _dotY);
    switch (dot) {
      case _Dot.none:
        break;
      case _Dot.past:
        canvas.drawCircle(c, 4.5, Paint()..color = YqColors.gold);
      case _Dot.future:
        canvas.drawCircle(c, 4.5, Paint()..color = YqColors.white);
        canvas.drawCircle(
          c,
          4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = YqColors.mist,
        );
      case _Dot.highlight:
        canvas.drawCircle(c, 9, Paint()..color = const Color(0x261F3F94));
        canvas.drawCircle(c, 5.5, Paint()..color = YqColors.lapis);
      case _Dot.now:
        canvas.drawCircle(c, 11, Paint()..color = const Color(0x331F3F94));
        canvas.drawCircle(c, 6.5, Paint()..color = YqColors.white);
        canvas.drawCircle(
          c,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = YqColors.lapis,
        );
      case _Dot.done:
        canvas.drawCircle(c, 8, Paint()..color = YqColors.gold);
        final check = Path()
          ..moveTo(c.dx - 3.6, c.dy + 0.2)
          ..lineTo(c.dx - 1, c.dy + 2.8)
          ..lineTo(c.dx + 3.8, c.dy - 2.4);
        canvas.drawPath(
          check,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = YqColors.white,
        );
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.past != past || old.now != now || old.first != first || old.last != last || old.dot != dot;
}
