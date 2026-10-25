import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';

enum MomentKind { prayer, azkar, routine }

/// One stop on the day's timeline.
class DayMoment {
  const DayMoment({
    required this.time,
    required this.title,
    required this.icon,
    required this.kind,
    this.subtitle,
    this.tag,
    this.highlight = false,
    this.onTap,
  });

  /// Wall-clock label, e.g. «3:53 م».
  final String time;
  final String title;
  final String? subtitle;
  final YqIcons icon;
  final MomentKind kind;

  /// Small chip («التالية», «متاحة الآن»).
  final String? tag;

  /// The next prayer, or azkar whose window is open.
  final bool highlight;
  final VoidCallback? onTap;
}

/// The day as one vertical journey: past moments recede, a «now» marker sits at the current time
/// with what to do now under it, and the rest of the day follows.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.moments,
    required this.nowIndex,
    required this.nowTime,
    required this.nowLabel,
    required this.nowChild,
    this.trailing,
  });

  final List<DayMoment> moments;

  /// The «now» marker goes before moments[nowIndex] (== moments.length: after the last).
  final int nowIndex;
  final String nowTime;
  final String nowLabel;
  final Widget nowChild;
  final Widget? trailing;

  static const _timeWidth = 58.0;
  static const _railWidth = 26.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i <= moments.length; i++) {
      if (i == nowIndex) rows.add(_row(context, past: true, now: true, first: i == 0, last: false, child: _now()));
      if (i == moments.length) break;
      rows.add(
        _row(
          context,
          past: i < nowIndex,
          now: false,
          first: i == 0 && nowIndex != 0,
          last: i == moments.length - 1 && trailing == null,
          moment: moments[i],
          child: _moment(context, moments[i], past: i < nowIndex),
        ),
      );
    }
    if (trailing != null) rows.add(_row(context, past: false, now: false, first: false, last: true, child: trailing!, plain: true));
    return Column(children: rows);
  }

  Widget _row(
    BuildContext context, {
    required bool past,
    required bool now,
    required bool first,
    required bool last,
    required Widget child,
    DayMoment? moment,
    bool plain = false,
  }) {
    final timeStyle = now
        ? YqText.numberSmall.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: YqColors.lapis,
          )
        : YqText.numberSmall.copyWith(fontSize: 12, color: past ? YqColors.slate400 : YqColors.navy600);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                now ? nowTime : (moment?.time ?? ''),
                textAlign: TextAlign.end,
                style: timeStyle,
              ),
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
                    : (now
                        ? _Dot.now
                        : (moment?.highlight ?? false)
                            ? _Dot.highlight
                            : past
                                ? _Dot.past
                                : _Dot.future),
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
            child: Text(
              nowLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: YqColors.lapis,
              ),
            ),
          ),
          nowChild,
        ],
      );

  Widget _moment(BuildContext context, DayMoment m, {required bool past}) {
    final titleColor = past ? YqColors.slate400 : YqColors.ink;
    final tag = m.tag == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: m.kind == MomentKind.azkar ? const Color(0x33C6A867) : const Color(0x1A1F3F94),
              borderRadius: BorderRadius.circular(YqRadii.pill),
            ),
            child: Text(
              m.tag!,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: m.kind == MomentKind.azkar ? YqColors.goldText : YqColors.lapis,
              ),
            ),
          );

    if (m.kind == MomentKind.prayer) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            YqIcon(m.icon, size: 18, tone: past ? YqIconTone.idle : (m.highlight ? YqIconTone.active : YqIconTone.idle)),
            const SizedBox(width: 8),
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
      );
    }

    // Azkar: a tappable glass pill; gold while its window is open.
    return GlassTap(
      onTap: m.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              m.onTap!();
            },
      semanticLabel: m.title,
      child: LiquidGlass(
        tone: m.highlight ? GlassTone.gold : GlassTone.clear,
        radius: YqRadii.tile,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        highlight: false,
        shadow: m.highlight,
        child: Row(
          children: [
            YqIcon(m.icon, size: 18, tone: m.highlight ? YqIconTone.gold : YqIconTone.idle),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: past && !m.highlight ? YqColors.slate400 : YqColors.ink,
                    ),
                  ),
                  if (m.subtitle != null)
                    Text(
                      m.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: YqColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (tag != null) tag,
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: m.highlight ? YqColors.goldText : YqColors.slate400,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Dot { none, past, future, highlight, now }

/// The timeline thread: gold where the day has passed, mist ahead, with a dot per moment.
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
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.past != past || old.now != now || old.first != first || old.last != last || old.dot != dot;
}
