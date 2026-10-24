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
import '../../../core/widgets/yq_layout.dart';
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
  bool _noCompass = false;
  bool _wasAligned = false;

  @override
  void initState() {
    super.initState();
    final stream = ref.read(compassServiceProvider).headings;
    if (stream == null) {
      _noCompass = true;
    } else {
      _sub = stream.listen((h) {
        if (!mounted) return;
        setState(() => _heading = h);
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

    return Scaffold(
      body: AmbientBackground(
        lights: aligned ? AmbientBackground.goldLights : AmbientBackground.defaultLights,
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(
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
                const SizedBox(height: YqSpace.m),
              ],
              const SizedBox(height: YqSpace.l),
              Semantics(
                label: turn == null ? t.qiblaNoCompass(YqFormat.number(bearing.round())) : t.qiblaA11y(YqFormat.number(turn.abs().round())),
                liveRegion: true,
                child: ExcludeSemantics(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _CompassPainter(heading: heading ?? 0, bearing: bearing, aligned: aligned, hasHeading: heading != null),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: YqSpace.xl),
              if (_noCompass || heading == null)
                Text(
                  t.qiblaNoCompass(YqFormat.number(bearing.round())),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else ...[
                Text(
                  switch (guidance!) {
                    QiblaGuidance.turnRight => t.qiblaTurnRight,
                    QiblaGuidance.turnLeft => t.qiblaTurnLeft,
                    QiblaGuidance.aligned => t.qiblaAligned,
                  },
                  textAlign: TextAlign.center,
                  style: YqText.display.copyWith(fontSize: 24, color: aligned ? YqColors.goldText : YqColors.ink),
                ),
                const SizedBox(height: YqSpace.s),
                Text(
                  t.qiblaReadout(YqFormat.number(bearing.round()), YqFormat.number(heading.round())),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: YqSpace.xl),
              Row(
                children: [
                  Expanded(child: YqButton.secondary(label: t.qiblaCalibrate, onPressed: _calibrate)),
                  const SizedBox(width: YqSpace.m),
                  Expanded(child: YqButton.secondary(label: '${t.qiblaCamera} · ${t.soon}', onPressed: null)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dial rotates against the device heading so north stays north; the gold pointer marks the Kaaba.
class _CompassPainter extends CustomPainter {
  _CompassPainter({required this.heading, required this.bearing, required this.aligned, required this.hasHeading});

  final double heading;
  final double bearing;
  final bool aligned;
  final bool hasHeading;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xB3FFFFFF));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 4 : 1.5
        ..color = aligned ? YqColors.gold : YqColors.line,
    );

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * math.pi / 180);
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var d = 0; d < 360; d += 10) {
      final major = d % 90 == 0;
      tick
        ..strokeWidth = major ? 2 : 1
        ..color = major ? YqColors.ink : YqColors.mist;
      final a = d * math.pi / 180;
      final inner = r - (major ? 18 : 10);
      canvas.drawLine(Offset(math.sin(a) * inner, -math.cos(a) * inner), Offset(math.sin(a) * (r - 4), -math.cos(a) * (r - 4)), tick);
    }
    // North marker.
    final north = Path()
      ..moveTo(0, -r + 22)
      ..lineTo(-7, -r + 36)
      ..lineTo(7, -r + 36)
      ..close();
    canvas.drawPath(north, Paint()..color = YqColors.lapis);
    // Kaaba pointer at the Qibla bearing.
    final b = bearing * math.pi / 180;
    final tip = Offset(math.sin(b) * (r - 30), -math.cos(b) * (r - 30));
    canvas.drawLine(
      Offset.zero,
      tip,
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = YqColors.gold,
    );
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(b);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -11, 22, 22), const Radius.circular(4)),
      Paint()..color = YqColors.ink,
    );
    canvas.drawRect(const Rect.fromLTWH(-11, -5, 22, 3), Paint()..color = YqColors.gold);
    canvas.restore();
    canvas.restore();

    // Fixed needle: where the phone points.
    if (hasHeading) {
      canvas.drawLine(
        c,
        c + Offset(0, -r + 6),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = aligned ? YqColors.goldText : YqColors.lapis,
      );
    }
    canvas.drawCircle(c, 6, Paint()..color = YqColors.ink);
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.heading != heading || old.bearing != bearing || old.aligned != aligned || old.hasHeading != hasHeading;
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
