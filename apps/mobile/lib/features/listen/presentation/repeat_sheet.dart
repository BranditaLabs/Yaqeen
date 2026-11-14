import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/audio_models.dart';
import 'listen_controller.dart';

Future<void> showRepeatSheet(BuildContext context, {required int ayahCount}) =>
    showYqSheet<void>(context, builder: (_) => RepeatSheet(ayahCount: ayahCount));

/// `RepeatSheet` (spec §5.13): off, the current ayah ×N, a range A–B ×N, or the surah. Ayah and
/// range need the reciter's ayah timings. Every choice applies at once.
class RepeatSheet extends ConsumerStatefulWidget {
  const RepeatSheet({super.key, required this.ayahCount});
  final int ayahCount;

  @override
  ConsumerState<RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends ConsumerState<RepeatSheet> {
  RangeValues? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final st = ref.watch(listenControllerProvider);
    final c = ref.read(listenControllerProvider.notifier);
    final n = widget.ayahCount;
    int clampAyah(int a) => a.clamp(1, n);
    final from = clampAyah(st.rangeFrom ?? st.ayah);
    final to = clampAyah(st.rangeTo ?? st.ayah);
    final range = _dragging ?? RangeValues(from.toDouble(), to.toDouble());
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: YqSpace.s, bottom: YqSpace.s),
          child: YqChip(label: label, selected: selected, onTap: onTap),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.listenRepeatTitle, style: text.titleLarge),
        const SizedBox(height: YqSpace.m),
        Wrap(
          children: [
            chip(t.listenRepeatOff, st.repeat == ListenRepeat.off, () => c.setRepeat(ListenRepeat.off)),
            if (st.synced) ...[
              chip(t.listenRepeatAyah, st.repeat == ListenRepeat.ayah, () => c.setRepeat(ListenRepeat.ayah)),
              chip(t.listenRepeatRange, st.repeat == ListenRepeat.range, () => c.setRepeat(ListenRepeat.range, from: from, to: to)),
            ],
            chip(t.listenRepeatSurah, st.repeat == ListenRepeat.surah, () => c.setRepeat(ListenRepeat.surah)),
          ],
        ),
        if (!st.synced) Text(t.listenRepeatNeedsSync, style: text.bodySmall?.copyWith(color: YqColors.muted)),
        if (st.repeat == ListenRepeat.range) ...[
          const SizedBox(height: YqSpace.m),
          Text(t.listenRepeatRangeLabel(range.start.round(), range.end.round()), style: text.bodyMedium),
          if (n > 1)
            RangeSlider(
              min: 1,
              max: n.toDouble(),
              divisions: n - 1,
              values: range,
              labels: RangeLabels(YqFormat.number(range.start.round()), YqFormat.number(range.end.round())),
              activeColor: YqColors.lapis,
              inactiveColor: YqColors.line,
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                c.setRepeat(ListenRepeat.range, from: v.start.round(), to: v.end.round());
              },
            ),
        ],
        if (st.repeat == ListenRepeat.ayah || st.repeat == ListenRepeat.range) ...[
          const SizedBox(height: YqSpace.m),
          Text(t.listenRepeatTimesTitle, style: text.titleSmall),
          const SizedBox(height: YqSpace.s),
          Wrap(
            children: [
              for (final times in listenRepeatTimes)
                chip(
                  times == 0 ? t.listenRepeatForever : t.listenRepeatTimes(times),
                  st.repeatTimes == times,
                  () => c.setRepeat(st.repeat, times: times),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
