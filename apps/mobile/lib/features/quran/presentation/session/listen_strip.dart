import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_ring.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/domain/audio_models.dart';
import '../../../listen/presentation/listen_controller.dart';

/// Fraction of the surah played (0 when the length is not known yet).
double listenProgress(ListenState s) {
  final total = s.duration ?? Duration.zero;
  if (total.inMilliseconds <= 0) return 0;
  return (s.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
}

/// «×2 / 3» while a counted passage repeats, else null.
String? listenRoundLabel(AppLocalizations t, ListenState s) {
  if (s.repeat != ListenRepeat.range && s.repeat != ListenRepeat.ayah) return null;
  if (s.repeatTimes == 0) return null;
  final n = (s.loopEnded ? s.roundsDone : s.roundsDone + 1).clamp(1, s.repeatTimes);
  return t.qsRoundOf(YqFormat.number(n), YqFormat.number(s.repeatTimes));
}

/// A round play / pause button whose ring is the surah's progress (strip, mini player).
class ListenPlayButton extends ConsumerWidget {
  const ListenPlayButton({super.key, this.size = YqSpace.touch});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(listenControllerProvider);
    final label = s.playing ? t.listenPause : t.listenPlay;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => ref.read(listenControllerProvider.notifier).toggle(),
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(listenControllerProvider.notifier).toggle(),
          child: YqRing(
            value: listenProgress(s),
            size: size,
            stroke: 2.5,
            child: Container(
              width: size - 10,
              height: size - 10,
              decoration: const BoxDecoration(color: YqColors.navy, shape: BoxShape.circle),
              child: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: YqColors.goldLight, size: size * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// «استماع» over the page: play / pause in a progress ring, where the recitation is (surah · ayah,
/// the round of a counted passage), previous / next ayah and the full player.
class ListenStrip extends ConsumerWidget {
  const ListenStrip({super.key, required this.onOpenPlayer, required this.onRetry});

  final VoidCallback onOpenPlayer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(listenControllerProvider);
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final locale = ref.watch(settingsProvider.select((x) => x.locale));
    final c = ref.read(listenControllerProvider.notifier);
    switch (s.status) {
      case ListenStatus.idle || ListenStatus.loading:
        // Shaped like what arrives: the ringed button and the two lines beside it.
        return const SizedBox(
          height: YqSpace.touch + 4,
          child: YqSkeleton(
            child: Row(
              children: [
                YqSkeletonBox.circle(YqSpace.touch),
                SizedBox(width: YqSpace.m),
                Expanded(child: YqSkeletonBox(height: 28, radius: YqRadii.pill)),
              ],
            ),
          ),
        );
      case ListenStatus.noReciter:
        return Row(
          children: [
            Expanded(child: Text(t.listenNoReciter, style: Theme.of(context).textTheme.bodySmall)),
            YqButton.text(label: t.qsChangeReciter, onPressed: () => context.push('/quran/reciters')),
          ],
        );
      case ListenStatus.unavailable:
        return Row(
          children: [
            Expanded(child: Text(t.listenUnavailable, style: Theme.of(context).textTheme.bodySmall)),
            YqButton.text(label: t.retry, onPressed: onRetry),
          ],
        );
      case ListenStatus.ready:
        break;
    }
    final surah = quran?.surah(s.surah);
    final round = listenRoundLabel(t, s);
    final where = surah == null ? '' : '${surah.name(locale)} · ${t.quranAyahN(s.ayah)}';
    return Row(
      children: [
        const ListenPlayButton(),
        const SizedBox(width: YqSpace.m),
        Expanded(
          child: Semantics(
            button: true,
            label: '$where. ${t.qsOpenPlayer}',
            excludeSemantics: true,
            onTap: onOpenPlayer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenPlayer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    [if (round != null) round, if (s.reciter != null) s.reciter!.name(locale)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: YqColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        // RTL: «previous ayah» sits on the right, matching reading direction.
        IconButton(tooltip: t.listenPrev, onPressed: s.synced ? c.previous : null, icon: const Icon(Icons.skip_next_rounded)),
        IconButton(tooltip: t.listenNext, onPressed: s.synced ? c.next : null, icon: const Icon(Icons.skip_previous_rounded)),
        IconButton(tooltip: t.qsOpenPlayer, onPressed: onOpenPlayer, icon: const Icon(Icons.expand_less_rounded, color: YqColors.lapis)),
      ],
    );
  }
}

/// Listening with the tools hidden: a 3-pt hairline of the surah's progress along the bottom and a
/// small play glyph, so the page stays almost bare (spec §5.11).
class ListenHairline extends ConsumerWidget {
  const ListenHairline({super.key, required this.onShow});
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(listenControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: YqSpace.l, bottom: YqSpace.s),
          child: Semantics(
            container: true,
            child: GestureDetector(onLongPress: onShow, child: const ListenPlayButton(size: 36)),
          ),
        ),
        SizedBox(
          height: 3,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: listenProgress(s),
              child: const ColoredBox(color: YqColors.lapis, child: SizedBox.expand()),
            ),
          ),
        ),
      ],
    );
  }
}
