import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../theme/tokens.dart';

/// A live input level while recording (docs/DESIGN_SYSTEM.md §5): 5–7 rounded lapis bars driven by
/// the real amplitude in [levels] (0…1, e.g. the microphone's normalised RMS), never by a
/// pretend animation. The newest sample sits in the centre and older ones spread outward, so a
/// voice reads as a soft wave; every height eases to its target. Silence rests low and still.
///
/// No ticker of its own: it moves only when a sample arrives. Under reduce-motion it is a static
/// rest shape and does not listen. Decorative: the caller labels the recording state.
class YqLiveLevel extends StatefulWidget {
  const YqLiveLevel({
    super.key,
    required this.levels,
    this.bars = 5,
    this.height = 28,
    this.barWidth = 4,
    this.gap = 3,
    this.color = YqColors.lapis,
  }) : assert(bars >= 5 && bars <= 7, 'YqLiveLevel draws 5 to 7 bars');

  final Stream<double> levels;
  final int bars;
  final double height;
  final double barWidth;
  final double gap;
  final Color color;

  /// The lowest a bar goes (a fraction of [height]), so the meter never disappears.
  static const floor = 0.14;

  /// How long a bar takes to reach a new height.
  static const ease = Duration(milliseconds: 140);

  @override
  State<YqLiveLevel> createState() => _YqLiveLevelState();
}

class _YqLiveLevelState extends State<YqLiveLevel> {
  StreamSubscription<double>? _sub;

  /// Newest first; one entry per distance from the centre.
  late List<double> _history = List.filled(_reach, 0);

  int get _reach => widget.bars ~/ 2 + 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(YqLiveLevel old) {
    super.didUpdateWidget(old);
    if (old.bars != widget.bars) _history = List.filled(_reach, 0);
    if (old.levels != widget.levels) {
      _sub?.cancel();
      _sub = null;
      _listen();
    }
  }

  void _listen() {
    if (reduceMotion(context)) {
      _sub?.cancel();
      _sub = null;
      return;
    }
    _sub ??= widget.levels.listen((v) {
      if (!mounted) return;
      setState(() => _history = [v.isNaN ? 0.0 : v.clamp(0.0, 1.0), ..._history.take(_reach - 1)]);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Bars nearer the centre stand a little taller, like a voice's body.
  double _profile(int distance) => 1 - 0.18 * distance;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final centre = (widget.bars - 1) / 2;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.bars; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                Builder(
                  builder: (context) {
                    final d = (i - centre).abs().round();
                    final amp = still ? 0.35 : _history[math.min(d, _reach - 1)];
                    final f = (YqLiveLevel.floor + (1 - YqLiveLevel.floor) * amp * _profile(d)).clamp(YqLiveLevel.floor, 1.0);
                    return AnimatedContainer(
                      key: ValueKey('yq-live-bar-$i'),
                      duration: still ? Duration.zero : YqLiveLevel.ease,
                      curve: Curves.easeOut,
                      width: widget.barWidth,
                      height: widget.height * f,
                      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(widget.barWidth)),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
