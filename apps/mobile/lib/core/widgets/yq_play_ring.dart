import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../design/motion.dart';
import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'yq_ring.dart';

/// A play/pause control for one recording or recitation (docs/DESIGN_SYSTEM.md §5): the glyph
/// morphs between play and pause, a lapis ring shows [progress] (0…1), and with [orbit] a slow
/// hairline ring turns once every 12 s while [playing] — a sign of life, not a spinner.
///
/// Tickers: the orbit runs only while playing and on screen (it stops when paused, and an
/// off-screen or background `TickerMode` mutes it); under reduce-motion nothing turns and the
/// glyph simply changes. The progress ring eases between values like every `YqRing`.
class YqPlayRing extends StatefulWidget {
  const YqPlayRing({
    super.key,
    required this.playing,
    required this.progress,
    required this.onPressed,
    this.size = 56,
    this.stroke = 3,
    this.orbit = false,
    this.semanticLabel,
  });

  final bool playing;
  final double progress;
  final VoidCallback? onPressed;
  final double size;
  final double stroke;
  final bool orbit;

  /// Overrides «تشغيل» / «إيقاف مؤقت» (e.g. with the recording's title).
  final String? semanticLabel;

  /// One full turn of the hairline orbit.
  static const revolution = Duration(seconds: 12);

  @override
  State<YqPlayRing> createState() => _YqPlayRingState();
}

class _YqPlayRingState extends State<YqPlayRing> with TickerProviderStateMixin {
  late final AnimationController _morph =
      AnimationController(vsync: this, duration: Motion.standard, value: widget.playing ? 1 : 0);
  late final AnimationController _orbit = AnimationController(vsync: this, duration: YqPlayRing.revolution);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncOrbit();
  }

  @override
  void didUpdateWidget(YqPlayRing old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      if (reduceMotion(context)) {
        _morph.value = widget.playing ? 1 : 0;
      } else {
        if (widget.playing) {
          _morph.forward();
        } else {
          _morph.reverse();
        }
      }
    }
    _syncOrbit();
  }

  /// The orbit turns only while playing, visible, and motion is welcome.
  void _syncOrbit() {
    final run = widget.orbit && widget.playing && !reduceMotion(context) && TickerMode.valuesOf(context).enabled;
    if (run && !_orbit.isAnimating) {
      _orbit.repeat();
    } else if (!run && _orbit.isAnimating) {
      _orbit.stop();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = widget.size;
    final label = widget.semanticLabel ?? (widget.playing ? t.listenPause : t.listenPlay);
    final ring = widget.orbit ? size - 10 : size;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GlassTap(
        onTap: widget.onPressed,
        pressScale: 0.92,
        child: SizedBox.square(
          dimension: math.max(size, YqSpace.touch),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.orbit)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _orbit,
                    builder: (context, _) => CustomPaint(
                      size: Size.square(size),
                      painter: _OrbitPainter(turn: _orbit.value, active: widget.playing),
                    ),
                  ),
                ),
              YqRing(
                value: widget.progress,
                size: ring,
                stroke: widget.stroke,
                color: YqColors.lapis,
                track: YqColors.lapis100.withValues(alpha: 0.5),
                child: Container(
                  width: ring - 2 * (widget.stroke + 4),
                  height: ring - 2 * (widget.stroke + 4),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: YqColors.white),
                  alignment: Alignment.center,
                  // Media glyphs never mirror.
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _morph,
                    size: ring * 0.42,
                    color: YqColors.ink,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hairline circle with one short brighter arc that travels round it ([turn] 0…1). Clockwise in
/// every language: it is a clock-like sign of playback, not a reading direction.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.turn, required this.active});
  final double turn;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = YqColors.lapis.withValues(alpha: 0.14),
    );
    if (!active) return;
    canvas.drawArc(
      rect,
      -math.pi / 2 + math.pi * 2 * turn,
      math.pi / 4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = YqColors.lapis.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.turn != turn || old.active != active;
}
