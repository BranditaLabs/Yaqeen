import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/passage.dart';
import '../../quran/presentation/session/listen_strip.dart';
import 'listen_controller.dart';

/// How many readers are open (the reader marks itself); the mini player steps aside under one.
class ReaderPresence extends Notifier<int> {
  @override
  int build() => 0;
  void enter() => state++;
  void leave() => state = state > 0 ? state - 1 : 0;
}

final readerPresenceProvider = NotifierProvider<ReaderPresence, int>(ReaderPresence.new);

/// The mini player was closed («إغلاق المشغّل»); it comes back the next time recitation plays.
class MiniPlayerDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(listenControllerProvider.select((s) => s.playing), (was, now) {
      if (now && was != true) state = false;
    });
    return false;
  }

  void dismiss() => state = true;
}

final miniPlayerDismissedProvider = NotifierProvider<MiniPlayerDismissed, bool>(MiniPlayerDismissed.new);

/// Whether the shell shows the mini player: recitation is loaded (or loading), not a reciter
/// sample, not closed, and no reader on top.
final miniPlayerVisibleProvider = Provider<bool>((ref) {
  final s = ref.watch(listenControllerProvider.select((s) => (s.status, s.sampleOf)));
  final loaded = s.$1 == ListenStatus.ready || s.$1 == ListenStatus.loading;
  return loaded && s.$2 == null && !ref.watch(miniPlayerDismissedProvider) && ref.watch(readerPresenceProvider) == 0;
});

/// `MiniPlayer` (spec §5.13): an app-wide pill above the dock — the surah, the step (ayah, or the
/// round of a counted passage), play / pause inside a progress ring, and close (pause + dismiss).
/// A tap opens the reader on the recited page in listen mode. Frosted, never a live blur.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const height = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(listenControllerProvider);
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final locale = ref.watch(settingsProvider.select((x) => x.locale));
    if (s.status == ListenStatus.loading || quran == null) {
      return const SizedBox(height: height, child: YqSkeleton(child: YqSkeletonBox(height: height, radius: YqRadii.pill)));
    }
    final name = quran.surah(s.surah).name(locale);
    final step = listenRoundLabel(t, s) ?? t.quranAyahN(s.ayah);
    void open() {
      final page = quran.pageOf(s.ref);
      context.push('/quran/read/${page.clamp(1, 604)}?mode=${QuranMode.listen.name}');
    }

    return SizedBox(
      height: height,
      child: LiquidGlass(
        radius: YqRadii.pill,
        opacity: 0.82,
        padding: const EdgeInsetsDirectional.fromSTEB(YqSpace.s, YqSpace.xs, YqSpace.xs, YqSpace.xs),
        child: Row(
          children: [
            const ListenPlayButton(size: 46),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Semantics(
                button: true,
                label: '$name، $step. ${t.qsOpenPlayer}',
                excludeSemantics: true,
                onTap: open,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: open,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(step, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: t.qsClosePlayer,
              onPressed: () {
                ref.read(listenControllerProvider.notifier).pause();
                ref.read(miniPlayerDismissedProvider.notifier).dismiss();
              },
              icon: const Icon(Icons.close_rounded, color: YqColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
