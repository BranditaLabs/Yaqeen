import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'yq_states.dart';

/// A printed mushaf page while it loads (spec §2 loading rule): fifteen justified lines in the
/// page's box — the last one short, like the end of a page — under one shimmer. Replaces the blank
/// moment while a page's font arrives and the reader's skeleton while the mushaf text is parsed.
class YqSkeletonMushafPage extends StatelessWidget {
  const YqSkeletonMushafPage({super.key, this.lines = 15, this.header = false});

  /// Printed lines per page (the Madani mushaf has 15).
  final int lines;

  /// Also sketch the page header and number (the reader's first paint, before any page exists).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return YqSkeleton(
      child: LayoutBuilder(
        builder: (context, box) {
          final height = box.maxHeight.isFinite ? box.maxHeight : lines * 32.0;
          final pitch = height / (lines + (header ? 2 : 0));
          final bar = (pitch * 0.34).clamp(6.0, 14.0);
          Widget line(double factor) => SizedBox(
                height: pitch,
                child: Center(child: YqSkeletonLine(widthFactor: factor, height: bar)),
              );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header)
                SizedBox(
                  height: pitch,
                  child: const Row(
                    children: [
                      SizedBox(width: 72, child: YqSkeletonBox(height: 10, radius: YqRadii.pill)),
                      Spacer(),
                      SizedBox(width: 96, child: YqSkeletonBox(height: 10, radius: YqRadii.pill)),
                    ],
                  ),
                ),
              for (var i = 0; i < lines; i++) line(i == lines - 1 ? 0.55 : 1),
              if (header)
                SizedBox(
                  height: pitch,
                  child: const Center(child: SizedBox(width: 44, child: YqSkeletonBox(height: 10, radius: YqRadii.pill))),
                ),
            ],
          );
        },
      ),
    );
  }
}
