import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../prayer/domain/qibla.dart';
import '../data/tasbeeh_controller.dart';
import '../../../core/widgets/liquid_orb.dart';

/// Diameter of a Home complication orb.
const orbSize = YqOrb.defaultSize;

/// Qibla complication — no compass rose: the Kaaba orbits the ring and reaches the top (where the
/// phone points) when you face it, then the orb glows gold with one light haptic.
///
/// The sensor runs only while the orb is on screen (its tab active, app in the foreground) and
/// updates are throttled to visible changes. Without a compass, the ring's top is north and the
/// Kaaba sits at the bearing. Tap → the full Qibla screen.
class QiblaOrb extends ConsumerStatefulWidget {
  const QiblaOrb({super.key});

  @override
  ConsumerState<QiblaOrb> createState() => _QiblaOrbState();
}

class _QiblaOrbState extends ConsumerState<QiblaOrb> with WidgetsBindingObserver {
  StreamSubscription<HeadingReading>? _sub;
  double? _heading;
  bool _noCompass = false;
  bool _wasAligned = false;
  bool _foreground = true;

  /// Kaaba angle on the ring, unwrapped (so 179° → −179° turns 2°, not 358°).
  double? _angle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled && _foreground;
    if (visible && _sub == null && !_noCompass) {
      final stream = ref.read(compassServiceProvider).headings;
      if (stream == null) {
        setState(() => _noCompass = true);
        return;
      }
      _sub = stream.listen(_onHeading);
    } else if (!visible && _sub != null) {
      _sub!.cancel();
      _sub = null;
    }
  }

  void _onHeading(HeadingReading h) {
    if (!mounted) return;
    final previous = _heading;
    // Repaint only for a visible change (≥ 1°): the sensor reports far more often than that.
    if (previous != null && turnToQibla(previous, h.degrees).abs() < 1) return;
    final place = ref.read(settingsProvider).placeOrDefault;
    final turn = turnToQibla(h.degrees, qiblaBearing(place.lat, place.lng));
    setState(() {
      final last = _angle;
      _angle = last == null ? turn : last + turnToQibla(last, turn);
      _heading = h.degrees;
    });
    final aligned = guidanceFor(turn) == QiblaGuidance.aligned;
    if (aligned && !_wasAligned) HapticFeedback.lightImpact();
    _wasAligned = aligned;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final place = ref.watch(settingsProvider.select((s) => s.placeOrDefault));
    final bearing = qiblaBearing(place.lat, place.lng);
    final heading = _heading;
    final live = heading != null;
    final turn = live ? turnToQibla(heading, bearing) : null;
    final guidance = turn == null ? null : guidanceFor(turn);
    final aligned = guidance == QiblaGuidance.aligned;
    final deg = '${YqFormat.number(bearing.round())}°';
    final status = switch (guidance) {
      QiblaGuidance.aligned => t.qiblaAligned,
      QiblaGuidance.turnRight => t.qiblaTurnRight,
      QiblaGuidance.turnLeft => t.qiblaTurnLeft,
      null => '$deg ${t.homeQiblaStatic}',
    };

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${t.qiblaCardTitle(YqFormat.number(bearing.round()))}، $status${live ? '، ${t.homeQiblaLive}' : ''}',
      child: GlassTap(
        onTap: () => context.push('/prayer/qibla'),
        child: YqOrb(
          title: t.qiblaTitle,
          status: status,
          glow: aligned,
          statusColor: aligned ? YqColors.goldText : null,
          disc: TweenAnimationBuilder<double>(
            tween: Tween(end: live ? (_angle ?? turn!) : bearing),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, angle, _) => CustomPaint(
              painter: _QiblaOrbitPainter(angle: angle, aligned: aligned, live: live, north: t.dirShortN),
              child: Center(
                child: Text(
                  deg,
                  textDirection: TextDirection.ltr,
                  style: YqText.numberSmall.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: aligned ? YqColors.goldDeep : YqColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring; the phone's direction (or north) is the top notch; the Kaaba glyph sits at [angle]
/// degrees clockwise from the top, with a soft trail back to the notch showing which way to turn.
class _QiblaOrbitPainter extends CustomPainter {
  _QiblaOrbitPainter({required this.angle, required this.aligned, required this.live, required this.north});

  final double angle;
  final bool aligned;
  final bool live;
  final String north;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x331F3F94),
    );
    // Quarter ticks.
    final tick = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x4D1F3F94);
    for (var i = 1; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 4), c + d * (r + 1), tick);
    }

    final rad = (angle % 360) * math.pi / 180;
    final signed = ((angle % 360) + 540) % 360 - 180; // −180…180
    // Trail from the notch to the Kaaba: the way to turn.
    if (live && signed.abs() > 3) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        signed * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x401F3F94),
      );
    }

    // Top notch: where the phone points (live) or north.
    final top = Offset(c.dx, c.dy - r);
    final notch = Path()
      ..moveTo(top.dx - 5, top.dy - 7)
      ..lineTo(top.dx + 5, top.dy - 7)
      ..lineTo(top.dx, top.dy - 1)
      ..close();
    canvas.drawPath(notch, Paint()..color = live ? (aligned ? YqColors.gold : YqColors.lapis) : YqColors.error);
    if (!live) {
      final tp = TextPainter(
        text: TextSpan(
          text: north,
          style: const TextStyle(
            fontFamily: YqFonts.ui,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: YqColors.error,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(top.dx - tp.width / 2, top.dy + 3));
    }

    // The Kaaba.
    final k = Offset(c.dx + r * math.sin(rad), c.dy - r * math.cos(rad));
    if (aligned) {
      canvas.drawCircle(
        k,
        16,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xB3E9D49E), Color(0x00E9D49E)])
              .createShader(Rect.fromCircle(center: k, radius: 16)),
      );
    }
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: k, width: 13, height: 14), const Radius.circular(2.5));
    canvas.drawShadow(Path()..addRRect(box), YqColors.ink, 2, false);
    canvas.drawRRect(box, Paint()..color = YqColors.ink);
    canvas.drawRect(Rect.fromLTWH(k.dx - 6.5, k.dy - 3, 13, 2.2), Paint()..color = YqColors.gold);
  }

  @override
  bool shouldRepaint(_QiblaOrbitPainter old) =>
      old.angle != angle || old.aligned != aligned || old.live != live || old.north != north;
}

/// Misbaha complication: tap to count, hold to reset. 33 beads around the orb fill gold, with a
/// firmer haptic at each completed round. The count lives on the device (tasbeehProvider).
class TasbeehOrb extends ConsumerWidget {
  const TasbeehOrb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final count = ref.watch(tasbeehProvider);
    const per = TasbeehController.round;
    final inRound = count % per;
    final round = count ~/ per + 1;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: t.tasbeehA11y(YqFormat.number(count)),
      onTap: () => _count(ref),
      onLongPress: () => _reset(context, ref),
      child: GlassTap(
        onTap: () => _count(ref),
        onLongPress: () => _reset(context, ref),
        child: YqOrb(
          title: t.tasbeehTitle,
          status: t.tasbeehRound(YqFormat.number(round)),
          disc: KeyedSubtree(
            // A new round starts the loop empty instead of sweeping back.
            key: ValueKey(round),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: inRound.toDouble()),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, v, child) => CustomPaint(painter: _MisbahaPainter(counted: v, beads: per), child: child),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: Tween(begin: 0.8, end: 1.0).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: Text(
                    YqFormat.number(count),
                    key: ValueKey(count),
                    textDirection: TextDirection.ltr,
                    style: YqText.numeral.copyWith(
                      fontSize: count >= 1000 ? 17 : 22,
                      fontWeight: FontWeight.w500,
                      color: YqColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _count(WidgetRef ref) {
    final next = ref.read(tasbeehProvider) + 1;
    next % TasbeehController.round == 0 ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    ref.read(tasbeehProvider.notifier).increment();
  }

  void _reset(BuildContext context, WidgetRef ref) {
    if (ref.read(tasbeehProvider) == 0) return;
    HapticFeedback.heavyImpact();
    ref.read(tasbeehProvider.notifier).reset();
    YqToast.show(context, AppLocalizations.of(context).tasbeehResetDone);
  }
}

/// A misbaha loop: [beads] beads on a ring with the imam bead (and its tassel) at the top. Counted
/// beads turn gold; the latest one is slightly larger with a soft glow. [counted] may be fractional
/// while it animates.
class _MisbahaPainter extends CustomPainter {
  _MisbahaPainter({required this.counted, required this.beads});
  final double counted;
  final int beads;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x40C6A867),
    );
    final top = Offset(c.dx, c.dy - r);
    canvas.drawCircle(top, 4.6, Paint()..color = YqColors.goldText);

    final step = math.pi * 2 / (beads + 1);
    final latest = counted.ceil() - 1;
    for (var i = 0; i < beads; i++) {
      final a = -math.pi / 2 + step * (i + 1);
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final fill = (counted - i).clamp(0.0, 1.0);
      final isLatest = i == latest && fill > 0;
      final radius = isLatest ? 3.8 : 2.9;
      if (isLatest) canvas.drawCircle(p, 7, Paint()..color = const Color(0x40E9D49E));
      canvas.drawCircle(p, radius, Paint()..color = Color.lerp(const Color(0xFFFFFFFF), YqColors.gold, fill)!);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Color.lerp(const Color(0x591F3F94), YqColors.goldText, fill)!,
      );
    }
  }

  @override
  bool shouldRepaint(_MisbahaPainter old) => old.counted != counted || old.beads != beads;
}

/// Wird complication: liquid that fills as today's pages are read. Tap → the Quran.
class WirdOrb extends ConsumerWidget {
  const WirdOrb({super.key, required this.done, required this.goal});
  final int done;
  final int goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final shown = done.clamp(0, goal);
    final complete = goal > 0 && done >= goal;
    return GlassTap(
      onTap: () => context.go('/quran'),
      semanticLabel: '${t.dailyWird}، ${t.pagesOf(shown, goal)}',
      child: YqOrb(
        title: t.dailyWird,
        status: complete ? t.homeWirdDone : t.pagesOf(shown, goal),
        statusColor: complete ? YqColors.success : null,
        disc: LiquidOrb(
          level: goal == 0 ? 0 : done / goal,
          size: orbSize - 12,
          complete: complete,
          child: Text(
            '${YqFormat.number(shown)}/${YqFormat.number(goal)}',
            textDirection: TextDirection.ltr,
            style: YqText.numberSmall.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: YqColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
