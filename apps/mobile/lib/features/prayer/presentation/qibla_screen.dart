import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/qibla.dart';
import 'city_picker_sheet.dart';

/// `14 · Qibla` (spec §5.16). Full screen, works offline (bearing from the saved place).
class QiblaScreen extends ConsumerStatefulWidget {
  const QiblaScreen({super.key});

  @override
  ConsumerState<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends ConsumerState<QiblaScreen> {
  StreamSubscription<HeadingReading>? _sub;
  HeadingReading? _heading;
  bool _wasAligned = false;

  /// Kaaba angle on the ring, unwrapped (179° → −179° turns 2°, not 358°) so it never spins round.
  double? _angle;

  @override
  void initState() {
    super.initState();
    // No compass: the orbit stays static (north up, the Kaaba at the bearing).
    final stream = ref.read(compassServiceProvider).headings;
    if (stream != null) {
      _sub = stream.listen((h) {
        if (!mounted) return;
        final place = ref.read(settingsProvider).placeOrDefault;
        final turn = turnToQibla(h.degrees, qiblaBearing(place.lat, place.lng));
        setState(() {
          final last = _angle;
          _angle = last == null ? turn : last + turnToQibla(last, turn);
          _heading = h;
        });
        _hapticOnAlignment();
      });
    }
  }

  /// One light haptic when the user turns into alignment — not repeatedly while staying there.
  void _hapticOnAlignment() {
    final s = ref.read(settingsProvider).placeOrDefault;
    final h = _heading;
    if (h == null) return;
    final aligned = guidanceFor(turnToQibla(h.degrees, qiblaBearing(s.lat, s.lng))) == QiblaGuidance.aligned;
    if (aligned && !_wasAligned) HapticFeedback.lightImpact();
    _wasAligned = aligned;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _calibrate() {
    final t = AppLocalizations.of(context);
    showYqSheet<void>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.qiblaCalibrate, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.l),
          const SizedBox(height: 120, width: 200, child: _FigureEight()),
          const SizedBox(height: YqSpace.l),
          Text(t.qiblaCalibrateHint, textAlign: TextAlign.center, style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.close, onPressed: () => Navigator.of(c).pop()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final place = s.placeOrDefault;
    final bearing = qiblaBearing(place.lat, place.lng);
    final km = distanceToKaabaKm(place.lat, place.lng);
    final heading = _heading?.degrees;
    final turn = heading == null ? null : turnToQibla(heading, bearing);
    final guidance = turn == null ? null : guidanceFor(turn);
    final aligned = guidance == QiblaGuidance.aligned;

    final deg = YqFormat.number(bearing.round());
    final guidanceText = switch (guidance) {
      QiblaGuidance.turnRight => t.qiblaTurnRight,
      QiblaGuidance.turnLeft => t.qiblaTurnLeft,
      QiblaGuidance.aligned => t.qiblaAligned,
      null => null,
    };

    return Scaffold(
      body: YqCanvas(
        lights: aligned ? AmbientBackground.goldLights : null,
        stage: YqStage(
          compact: true,
          gold: aligned,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(
                back: true,
                title: t.qiblaTitle,
                subtitle: t.qiblaDistance(place.name(s.locale), YqFormat.number(km.round())),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final p = await showCityPicker(context);
                      if (p != null) await ref.read(settingsProvider.notifier).update((x) => x.copyWith(place: p));
                    },
                    child: Text(t.locationChange),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.xl),
              YqMoment(
                value: AnimatedDefaultTextStyle(
                  duration: YqMotion.base,
                  style: YqMoment.display(context, size: guidanceText == null ? 20 : 34)
                      .copyWith(color: aligned ? YqColors.goldText : YqColors.ink),
                  child: Text(guidanceText ?? t.qiblaNoCompass(deg)),
                ),
                caption: heading == null ? null : Text(t.qiblaReadout(deg, YqFormat.number(heading.round()))),
              ),
            ],
          ),
        ),
        children: [
          if (_heading?.needsCalibration ?? false) ...[
            LiquidGlass(
              tone: GlassTone.gold,
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
              child: Row(
                children: [
                  Expanded(child: Text(t.qiblaNeedsCalibration, style: const TextStyle(fontWeight: FontWeight.w500))),
                  TextButton(onPressed: _calibrate, child: Text(t.qiblaCalibrate)),
                ],
              ),
            ),
            const SizedBox(height: YqSpace.l),
          ],
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Semantics(
                label: turn == null ? t.qiblaNoCompass(deg) : t.qiblaA11y(YqFormat.number(turn.abs().round())),
                liveRegion: true,
                child: ExcludeSemantics(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: RepaintBoundary(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: turn == null ? bearing : (_angle ?? turn)),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        builder: (context, angle, _) => CustomPaint(
                          painter: _OrbitPainter(
                            angle: angle,
                            north: heading == null ? 0 : -heading,
                            aligned: aligned,
                            live: heading != null,
                            northLabel: t.dirShortN,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${YqFormat.number((aligned || turn == null ? bearing : turn.abs()).round())}°',
                                  textDirection: TextDirection.ltr,
                                  style: YqMoment.numeral(size: 64, color: aligned ? YqColors.goldDeep : YqColors.ink),
                                ),
                                if (turn != null && !aligned)
                                  Text(
                                    t.qiblaCardTitle(deg),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: YqSpace.xl),
          YqButton.secondary(label: t.qiblaCalibrate, onPressed: _calibrate),
          // Not built yet: a quiet note rather than a disabled pill that truncates its own label.
          const SizedBox(height: YqSpace.m),
          Text(
            '${t.qiblaCamera} · ${t.soon}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The Qibla as an orbit (the Home complication at full size): the top notch is where the phone
/// points (north without a compass); the Kaaba travels the ring at [angle]° clockwise from the
/// top and reaches it when you face the Qibla, where the ring turns gold. A soft trail shows which
/// way to turn; the north letter rides the ring at [north]°.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.angle, required this.north, required this.aligned, required this.live, required this.northLabel});

  final double angle;
  final double north;
  final bool aligned;
  final bool live;
  final String northLabel;

  Offset _on(Offset c, double r, double deg) {
    final a = deg * math.pi / 180;
    return Offset(c.dx + r * math.sin(a), c.dy - r * math.cos(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 26;
    // Glass disc.
    canvas.drawCircle(
      c,
      r + 18,
      Paint()
        ..shader =
            const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6FFFFFF), Color(0x99FFFFFF)])
                .createShader(Rect.fromCircle(center: c, radius: r + 18)),
    );
    canvas.drawCircle(
      c,
      r + 18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xF2FFFFFF),
    );
    if (aligned) {
      canvas.drawCircle(
        c,
        r + 18,
        Paint()
          ..shader =
              const RadialGradient(colors: [Color(0x00E9D49E), Color(0x66E9D49E)]).createShader(Rect.fromCircle(center: c, radius: r + 18)),
      );
    }
    // Ring and degree ticks (riding with north).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 3 : 1.4
        ..color = aligned ? YqColors.gold : const Color(0x331F3F94),
    );
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x401F3F94);
    for (var d = 0; d < 360; d += 15) {
      final major = d % 90 == 0;
      tick.strokeWidth = major ? 1.6 : 1;
      canvas.drawLine(_on(c, r - (major ? 12 : 7), north + d), _on(c, r - 3, north + d), tick);
    }
    final n = TextPainter(
      text: TextSpan(
        text: northLabel,
        style: const TextStyle(fontFamily: YqFonts.ui, fontSize: 12, fontWeight: FontWeight.w700, color: YqColors.lapis),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    n.paint(canvas, _on(c, r - 24, north) - Offset(n.width / 2, n.height / 2));

    // Trail from the notch to the Kaaba: the way to turn.
    final signed = ((angle % 360) + 540) % 360 - 180;
    if (live && signed.abs() > 3) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        signed * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x401F3F94),
      );
    }

    // Top notch: where the phone points.
    final top = Offset(c.dx, c.dy - r);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx - 8, top.dy - 14)
        ..lineTo(top.dx + 8, top.dy - 14)
        ..lineTo(top.dx, top.dy - 3)
        ..close(),
      Paint()..color = aligned ? YqColors.gold : YqColors.lapis,
    );

    // The Kaaba.
    final k = _on(c, r, angle);
    canvas.drawCircle(
      k,
      aligned ? 34 : 22,
      Paint()
        ..shader = RadialGradient(colors: [aligned ? const Color(0xB3E9D49E) : const Color(0x591F3F94), const Color(0x00FFFFFF)])
            .createShader(Rect.fromCircle(center: k, radius: aligned ? 34 : 22)),
    );
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: k, width: 24, height: 26), const Radius.circular(4));
    canvas.drawShadow(Path()..addRRect(box), YqColors.ink, 3, false);
    canvas.drawRRect(box, Paint()..color = YqColors.ink);
    canvas.drawRect(Rect.fromLTWH(k.dx - 12, k.dy - 6, 24, 4), Paint()..color = YqColors.gold);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.angle != angle || old.north != north || old.aligned != aligned || old.live != live || old.northLabel != northLabel;
}

class _FigureEight extends StatefulWidget {
  const _FigureEight();
  @override
  State<_FigureEight> createState() => _FigureEightState();
}

class _FigureEightState extends State<_FigureEight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 0.25;
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
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _EightPainter(_c.value)));
}

class _EightPainter extends CustomPainter {
  _EightPainter(this.t);
  final double t;

  Offset _at(Size s, double u) {
    final a = u * 2 * math.pi;
    return Offset(s.width / 2 + math.sin(a) * s.width * 0.4, s.height / 2 + math.sin(2 * a) * s.height * 0.3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(_at(size, 0).dx, _at(size, 0).dy);
    for (var i = 1; i <= 100; i++) {
      final p = _at(size, i / 100);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = YqColors.mist,
    );
    canvas.drawCircle(_at(size, t), 9, Paint()..color = YqColors.lapis);
  }

  @override
  bool shouldRepaint(_EightPainter old) => old.t != t;
}
