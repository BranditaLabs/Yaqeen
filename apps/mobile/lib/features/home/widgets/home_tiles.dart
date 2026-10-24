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
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../prayer/domain/qibla.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../data/tasbeeh_controller.dart';

/// Height shared by the square-ish Home tiles, so a row always lines up.
const homeTileHeight = 184.0;

/// Live Qibla widget: a small compass that turns with the phone and points to the Kaaba.
///
/// The sensor runs only while the tile is on screen (its tab active, app in the foreground) and
/// updates are throttled to visible changes, so it costs nothing in the background. Devices
/// without a compass get the bearing from north instead. Tap → the full Qibla screen.
class QiblaTile extends ConsumerStatefulWidget {
  const QiblaTile({super.key});

  @override
  ConsumerState<QiblaTile> createState() => _QiblaTileState();
}

class _QiblaTileState extends ConsumerState<QiblaTile> with WidgetsBindingObserver {
  StreamSubscription<HeadingReading>? _sub;
  double? _heading;
  bool _noCompass = false;
  bool _wasAligned = false;
  bool _foreground = true;

  /// Continuous (unwrapped) heading, so 359° → 1° slides the tape 2°, not −358°.
  double _tape = 0;

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
    if (previous != null && (turnToQibla(previous, h.degrees)).abs() < 1) return;
    final place = ref.read(settingsProvider).placeOrDefault;
    final bearing = qiblaBearing(place.lat, place.lng);
    final turn = turnToQibla(h.degrees, bearing);
    setState(() {
      _tape = previous == null ? h.degrees : _tape + turnToQibla(previous, h.degrees);
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
    final turn = heading == null ? null : turnToQibla(heading, bearing);
    final guidance = turn == null ? null : guidanceFor(turn);
    final aligned = guidance == QiblaGuidance.aligned;
    final status = switch (guidance) {
      QiblaGuidance.aligned => t.qiblaAligned,
      QiblaGuidance.turnRight => t.qiblaTurnRight,
      QiblaGuidance.turnLeft => t.qiblaTurnLeft,
      null => t.qiblaCardFrom(directionLabel(t, compassPoint(bearing))),
    };

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${t.qiblaCardTitle(YqFormat.number(bearing.round()))}، $status${heading == null ? '' : '، ${t.homeQiblaLive}'}',
      child: GlassTap(
        onTap: () => context.push('/prayer/qibla'),
        child: LiquidGlass(
          tone: aligned ? GlassTone.gold : GlassTone.clear,
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: homeTileHeight - 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TileTitle(icon: YqIcons.qibla, title: t.qiblaTitle, tag: '${YqFormat.number(bearing.round())}°', live: heading != null),
                const Spacer(),
                // Horizon tape: a heading ruler that slides as the phone turns; the Kaaba marker
                // drifts to the centre line when you face it.
                RepaintBoundary(
                  child: SizedBox(
                    height: 78,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: heading == null ? bearing : _tape),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, center, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _HorizonPainter(
                          center: center,
                          qibla: bearing,
                          aligned: aligned,
                          live: heading != null,
                          cardinals: [t.dirShortN, t.dirShortE, t.dirShortS, t.dirShortW],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: aligned ? FontWeight.w700 : FontWeight.w500,
                    color: aligned ? YqColors.goldText : YqColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter({required this.center, required this.qibla, required this.aligned, required this.live, required this.cardinals});

  /// Heading at the centre line (unwrapped degrees).
  final double center;
  final double qibla;
  final bool aligned;
  final bool live;

  /// N, E, S, W short labels.
  final List<String> cardinals;

  static const window = 60.0; // degrees each side

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final perDeg = w / (window * 2);
    final base = size.height * 0.64;
    final mid = w / 2;

    // Fade the ruler out towards the edges (soft horizon).
    final fade = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x001F3F94), Color(0x801F3F94), Color(0x801F3F94), Color(0x001F3F94)],
        stops: [0, 0.22, 0.78, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Rect.fromLTWH(0, base, w, 1), fade);

    final tick = Paint()..strokeCap = StrokeCap.round;
    final first = ((center - window) / 5).ceil() * 5;
    for (var d = first; d <= center + window; d += 5) {
      final x = mid + (d - center) * perDeg;
      final edge = 1 - ((x - mid).abs() / mid).clamp(0.0, 1.0);
      final norm = ((d % 360) + 360) % 360;
      final cardinal = norm % 90 == 0;
      final major = norm % 30 == 0;
      tick
        ..strokeWidth = cardinal ? 2 : 1
        ..color = Color.fromRGBO(
          31,
          63,
          148,
          (cardinal
                  ? 0.75
                  : major
                      ? 0.5
                      : 0.28) *
              edge,
        );
      final len = cardinal
          ? 12.0
          : major
              ? 8.0
              : 5.0;
      canvas.drawLine(Offset(x, base - len), Offset(x, base), tick);
      if (major) {
        final label = cardinal ? cardinals[norm ~/ 90] : '${norm.round()}';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: cardinal ? YqFonts.ui : YqFonts.numbers,
              fontFamilyFallback: const [YqFonts.ui],
              fontSize: cardinal ? 11 : 9,
              fontWeight: cardinal ? FontWeight.w700 : FontWeight.w400,
              color: (norm == 0 ? YqColors.error : YqColors.navy600).withValues(alpha: edge),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, base + 5));
      }
    }

    // Kaaba marker, or an edge arrow when it is outside the window.
    final off = turnToQibla(center % 360, qibla);
    final inside = off.abs() <= window - 6;
    final kx = inside ? mid + off * perDeg : (off > 0 ? w - 8 : 8.0);
    final ky = base - 26;
    if (aligned) {
      canvas.drawCircle(
        Offset(kx, ky),
        24,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0x99E9D49E), Color(0x00E9D49E)])
              .createShader(Rect.fromCircle(center: Offset(kx, ky), radius: 24)),
      );
    }
    if (inside) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(kx, ky), width: 16, height: 17), const Radius.circular(3));
      canvas.drawShadow(Path()..addRRect(r), YqColors.ink, 3, false);
      canvas.drawRRect(r, Paint()..color = YqColors.ink);
      canvas.drawRect(Rect.fromLTWH(kx - 8, ky - 3.5, 16, 2.6), Paint()..color = YqColors.gold);
    } else {
      final dir = off > 0 ? 1.0 : -1.0;
      final arrow = Path()
        ..moveTo(kx + 5 * dir, ky)
        ..lineTo(kx - 3 * dir, ky - 7)
        ..lineTo(kx - 3 * dir, ky + 7)
        ..close();
      canvas.drawPath(arrow, Paint()..color = YqColors.ink);
    }

    // Where the phone points.
    if (live) {
      final line = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = aligned ? YqColors.gold : YqColors.lapis;
      canvas.drawLine(Offset(mid, 4), Offset(mid, base + 2), line);
      final cap = Path()
        ..moveTo(mid - 5, 0)
        ..lineTo(mid + 5, 0)
        ..lineTo(mid, 6)
        ..close();
      canvas.drawPath(cap, Paint()..color = aligned ? YqColors.gold : YqColors.lapis);
    }
  }

  @override
  bool shouldRepaint(_HorizonPainter old) =>
      old.center != center || old.qibla != qibla || old.aligned != aligned || old.live != live || old.cardinals != cardinals;
}

/// Tasbeeh widget: tap the tile to count, hold to reset. A ring fills every 33, with a firmer
/// haptic at each completed round. The count lives on the device (tasbeehProvider).
class TasbeehTile extends ConsumerWidget {
  const TasbeehTile({super.key});

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
        child: GestureDetector(
          onLongPress: () => _reset(context, ref),
          child: LiquidGlass(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              height: homeTileHeight - 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TileTitle(icon: YqIcons.azkar, title: t.tasbeehTitle, tag: t.tasbeehRound(YqFormat.number(round))),
                  const Spacer(),
                  Center(
                    child: RepaintBoundary(
                      child: SizedBox.square(
                        dimension: 96,
                        child: KeyedSubtree(
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
                                  style: YqText.numeral
                                      .copyWith(fontSize: count >= 1000 ? 20 : 26, fontWeight: FontWeight.w500, color: YqColors.ink),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    t.tasbeehHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, height: 1.3, color: YqColors.muted),
                  ),
                ],
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

/// Icon + title (+ small tag) at the top of a Home tile.
class _TileTitle extends StatelessWidget {
  const _TileTitle({required this.icon, required this.title, this.tag, this.live = false});
  final YqIcons icon;
  final String title;
  final String? tag;

  /// A small green dot: the tile is following a live sensor.
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        YqIcon(icon, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (tag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: const Color(0x141F3F94), borderRadius: BorderRadius.circular(YqRadii.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (live) ...[
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: YqColors.success, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                ],
                Text(
                  tag!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: YqColors.lapis),
                ),
              ],
            ),
          ),
      ],
    );
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
    final r = size.width / 2 - 7;
    // Thread.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x40C6A867),
    );
    // Imam bead and tassel at the top.
    final top = Offset(c.dx, c.dy - r);
    canvas.drawLine(
      top,
      top.translate(0, -6),
      Paint()
        ..color = YqColors.goldText
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(top, 5.2, Paint()..color = YqColors.goldText);

    final step = math.pi * 2 / (beads + 1);
    final latest = counted.ceil() - 1;
    for (var i = 0; i < beads; i++) {
      final a = -math.pi / 2 + step * (i + 1);
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final fill = (counted - i).clamp(0.0, 1.0);
      final isLatest = i == latest && fill > 0;
      final radius = isLatest ? 4.6 : 3.4;
      if (isLatest) canvas.drawCircle(p, 8, Paint()..color = const Color(0x40E9D49E));
      canvas.drawCircle(p, radius, Paint()..color = Color.lerp(const Color(0xFFFFFFFF), YqColors.gold, fill)!);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.lerp(const Color(0x591F3F94), YqColors.goldText, fill)!,
      );
    }
  }

  @override
  bool shouldRepaint(_MisbahaPainter old) => old.counted != counted || old.beads != beads;
}
