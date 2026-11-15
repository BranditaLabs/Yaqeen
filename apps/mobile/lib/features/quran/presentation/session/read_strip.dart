import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/time/zoned.dart';
import '../../../../core/widgets/controls.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/quran_data.dart';
import '../quran_providers.dart';

final todayWirdProvider = FutureProvider.autoDispose((ref) => ref.watch(readingRepositoryProvider).wird());

/// «قراءة»: today's wird (and the khatma) and the page slider.
class ReadStrip extends ConsumerWidget {
  const ReadStrip({super.key, required this.page, required this.onJump});
  final int page;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final goal = ref.watch(settingsProvider.select((s) => s.wirdGoalPages));
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final tz = ref.watch(settingsProvider.select((s) => s.placeOrDefault.timezone));
    final today = Zoned.isoDate(Zoned.today(tz, ref.watch(clockProvider)()));
    final read = wird?.date == today ? wird!.count : 0;
    final khatma = ref.watch(khatmaProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs),
          child: Text(
            khatma != null && !khatma.finished
                ? '${t.readerWird} · ${t.pagesOf(read.clamp(0, goal), goal)} · ${t.quranKhatma} ${YqFormat.number((khatma.progress * 100).round())}%'
                : '${t.readerWird} · ${t.pagesOf(read.clamp(0, goal), goal)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs),
          // Gold only once today's goal is met (the rest of the reader stays lapis).
          child: YqProgressLine(value: goal == 0 ? 0 : read / goal, color: goal > 0 && read >= goal ? YqColors.gold : YqColors.lapis),
        ),
        Semantics(
          label: t.readerSlider,
          value: t.quranPageOf(page),
          child: Directionality(textDirection: TextDirection.rtl, child: PageSlider(page: page, onJump: onJump)),
        ),
      ],
    );
  }
}

/// The page slider: dragging only moves the thumb and its label; the reader turns to the page (and
/// fetches its font, saves it as the last read) once the thumb is let go.
class PageSlider extends StatefulWidget {
  const PageSlider({super.key, required this.page, required this.onJump});
  final int page;
  final ValueChanged<int> onJump;

  @override
  State<PageSlider> createState() => _PageSliderState();
}

class _PageSliderState extends State<PageSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.page.toDouble();
    return Slider(
      min: 1,
      max: QuranData.pageCount.toDouble(),
      divisions: QuranData.pageCount - 1,
      value: value,
      label: YqFormat.number(value.round()),
      activeColor: YqColors.lapis,
      inactiveColor: YqColors.line,
      onChanged: (v) => setState(() => _drag = v),
      onChangeEnd: (v) {
        setState(() => _drag = null);
        widget.onJump(v.round());
      },
    );
  }
}
