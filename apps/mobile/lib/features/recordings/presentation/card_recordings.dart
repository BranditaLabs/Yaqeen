import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/recording_models.dart';
import 'recording_widgets.dart';
import 'recordings_providers.dart';

/// The card editor's «تلاواتي على البطاقة» (APP_SPEC §5.26): which of the person's recordings the
/// web card `/u/<handle>` plays — only public + approved ones (a public one still in the AI check
/// says «تظهر بعد الفحص»). Changing who hears a recording stays on the Profile cards.
class CardRecordingsSection extends ConsumerWidget {
  const CardRecordingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final items = ref.watch(myRecordingsProvider).valueOrNull?.items ?? const <Recording>[];
    final public = [for (final r in items) if (r.visibility == RecordingVisibility.public) r];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(t.recCardTitle),
        if (public.isEmpty)
          YqGroup(
            key: const ValueKey('rec-card-none'),
            children: [YqListRow(leading: const YqIconTile(YqIcons.recite, size: 36), title: t.recCardNone)],
          )
        else
          YqGroup(
            key: const ValueKey('rec-card-list'),
            children: [
              for (final r in public) _CardRecordingRow(key: ValueKey('rec-card-${r.id}'), recording: r),
            ],
          ),
        const SizedBox(height: YqSpace.xs),
        Text(t.recCardHint, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
      ],
    );
  }
}

class _CardRecordingRow extends StatelessWidget {
  const _CardRecordingRow({super.key, required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = recording;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: YqSpace.touch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
        child: Row(
          children: [
            Icon(r.live ? Icons.play_circle_outline_rounded : Icons.hourglass_empty_rounded, color: r.live ? YqColors.lapis : YqColors.muted),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VerseRefText(surah: r.surah, from: r.fromAyah, to: r.toAyah, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                  if (!r.live) Text(t.recCardPending, style: const TextStyle(fontSize: 11.5, color: YqColors.muted)),
                ],
              ),
            ),
            Text(secondsText(t, r.durationMs), style: const TextStyle(color: YqColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// The preview's «تلاواتي» block: what the card shows — the verse reference with a play mark and
/// read-only reaction counts (the web card plays them; the preview never does).
class CardRecordingsPreview extends ConsumerWidget {
  const CardRecordingsPreview({super.key, required this.night});
  final bool night;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final items = ref.watch(myRecordingsProvider).valueOrNull?.items ?? const <Recording>[];
    final live = [for (final r in items) if (r.visibility == RecordingVisibility.public && r.live) r];
    if (live.isEmpty) return const SizedBox(width: double.infinity);
    final ink = night ? YqColors.white : YqColors.ink;
    final muted = night ? YqColors.navy200 : YqColors.muted;
    return Padding(
      key: const ValueKey('rec-card-preview'),
      padding: const EdgeInsets.only(top: YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.recTitle, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: YqSpace.s),
          for (final r in live)
            Padding(
              padding: const EdgeInsets.only(bottom: YqSpace.xs),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: night ? YqColors.sky : YqColors.lapis, width: 2)),
                    child: Icon(Icons.play_arrow_rounded, size: 18, color: night ? YqColors.sky : YqColors.lapis),
                  ),
                  const SizedBox(width: YqSpace.s),
                  Expanded(child: VerseRefText(surah: r.surah, from: r.fromAyah, to: r.toAyah, style: TextStyle(fontSize: 12.5, color: ink), maxLines: 1)),
                  if (r.reactions.total > 0) Text(YqFormat.number(r.reactions.total), style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
