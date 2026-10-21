import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds every second while visible and the app is in the foreground (spec §5.9: the
/// countdown pauses on background). [builder] gets the current time.
class YqTicker extends StatefulWidget {
  const YqTicker({super.key, required this.builder, this.now = DateTime.now, this.interval = const Duration(seconds: 1)});

  final Widget Function(BuildContext context, DateTime now) builder;
  final DateTime Function() now;
  final Duration interval;

  @override
  State<YqTicker> createState() => _YqTickerState();
}

class _YqTickerState extends State<YqTicker> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      setState(() {});
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.now());
}

/// `01:24:10` until [target] (never negative).
class YqCountdown extends StatelessWidget {
  const YqCountdown({super.key, required this.target, required this.style, this.now = DateTime.now, this.onDone});

  final DateTime target;
  final TextStyle style;
  final DateTime Function() now;
  final VoidCallback? onDone;

  static String format(Duration d) {
    final s = d.isNegative ? Duration.zero : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s.inHours)}:${two(s.inMinutes.remainder(60))}:${two(s.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    return YqTicker(
      now: now,
      builder: (context, t) {
        final left = target.difference(t);
        if (left.isNegative && onDone != null) WidgetsBinding.instance.addPostFrameCallback((_) => onDone!());
        return Text(format(left), textDirection: TextDirection.ltr, style: style);
      },
    );
  }
}
