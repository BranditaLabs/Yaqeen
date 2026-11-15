import 'package:flutter/material.dart';

/// One scroll feel everywhere: smooth, elastic (iOS-style) scrolling on both platforms instead of
/// Android's stretch/glow, which reads as more premium and keeps lists fluid.
class YqScrollBehavior extends MaterialScrollBehavior {
  const YqScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
