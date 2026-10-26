import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/format.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/share_card.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/data/content_controller.dart';
import '../../content/domain/content_item.dart';

String duaCategoryLabel(AppLocalizations t, DuaCategory c) => switch (c) {
      DuaCategory.worry => t.duaCatWorry,
      DuaCategory.travel => t.duaCatTravel,
      DuaCategory.food => t.duaCatFood,
      DuaCategory.sleep => t.duaCatSleep,
      DuaCategory.mosque => t.duaCatMosque,
      DuaCategory.general => t.duaCatGeneral,
    };

/// Favourite duas — on the device only.
class FavouritesController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.read(azkarStoreProvider).favourites();

  Future<void> toggle(String id) async {
    final now = {...(state.valueOrNull ?? const <String>{})};
    now.contains(id) ? now.remove(id) : now.add(id);
    state = AsyncData(now);
    await ref.read(azkarStoreProvider).saveFavourites(now);
  }
}

final favouritesProvider = AsyncNotifierProvider<FavouritesController, Set<String>>(FavouritesController.new);

/// `17 · Duas` (spec §5.20).
class DuasScreen extends ConsumerWidget {
  const DuasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final content = ref.watch(contentProvider);
    final favs = ref.watch(favouritesProvider).valueOrNull ?? const <String>{};
    final s = ref.watch(settingsProvider);
    final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)()));

    final lib = content.valueOrNull;
    final ofDay = lib?.duaOfTheDay(today);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.xxl,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(back: true, title: t.duasTitle),
              if (ofDay != null) ...[const SizedBox(height: YqSpace.xl), _DayDua(item: ofDay)],
            ],
          ),
        ),
        children: content.when(
          loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 220, radius: YqRadii.hero))],
          error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(contentProvider))],
          data: (lib) {
            if (ofDay == null) {
              return [
                LiquidGlass(
                  child: YqEmptyState(
                    icon: YqIcons.dua,
                    title: t.duasEmpty,
                    hint: t.contentOfflineHint,
                    actionLabel: t.retry,
                    onAction: () => ref.read(contentProvider.notifier).refresh(),
                  ),
                ),
              ];
            }
            final favCount = favs.where((id) => lib.byId(id) != null).length;
            final orbs = <Widget>[
              for (final c in DuaCategory.values)
                if (lib.duas(c).isNotEmpty)
                  YqOrb(
                    size: 88,
                    title: duaCategoryLabel(t, c),
                    status: t.duaCount(lib.duas(c).length),
                    onTap: () => context.push('/home/duas/${c.key}'),
                    semanticLabel: '${duaCategoryLabel(t, c)}، ${t.duaCount(lib.duas(c).length)}',
                    disc: YqOrb.number(YqFormat.number(lib.duas(c).length), size: 26),
                  ),
              YqOrb(
                size: 88,
                title: t.duaFavourites,
                status: t.duaFavCount(favCount),
                glow: favCount > 0,
                statusColor: YqColors.goldText,
                onTap: () => context.push('/home/duas/favourites'),
                semanticLabel: '${t.duaFavourites}، ${t.duaFavCount(favCount)}',
                disc: Center(
                  child: Icon(favCount > 0 ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: YqColors.gold, size: 30),
                ),
              ),
            ];
            return [
              YqHeading(t.duaSections),
              for (var i = 0; i < orbs.length; i += 3) ...[
                YqOrbRow(orbs: [for (var j = i; j < i + 3; j++) j < orbs.length ? orbs[j] : const SizedBox.shrink()]),
                const SizedBox(height: YqSpace.l),
              ],
            ];
          },
        ),
      ),
    );
  }
}

/// The stage's moment: the dua of the day in the naskh face, its source, favourite and share.
class _DayDua extends ConsumerWidget {
  const _DayDua({required this.item});
  final ContentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fav = ref.watch(favouritesProvider).valueOrNull?.contains(item.id) ?? false;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(t.duaOfTheDay, style: text.labelSmall?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6)),
        const SizedBox(height: YqSpace.m),
        Text(item.textAr, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: YqText.dua.copyWith(fontSize: 24, height: 1.9)),
        const SizedBox(height: YqSpace.s),
        Text(item.source, textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: YqColors.goldText)),
        const SizedBox(height: YqSpace.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassIconButton(
              tooltip: fav ? t.duaFavRemove : t.duaFavAdd,
              onPressed: () => ref.read(favouritesProvider.notifier).toggle(item.id),
              icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? YqColors.gold : YqColors.muted, size: 22),
            ),
            const SizedBox(width: YqSpace.m),
            GlassIconButton(
              tooltip: t.duaShare,
              onPressed: () => showTextShareCard(context, ref, text: item.textAr, reference: item.source, fileName: 'yaqeen-dua.png'),
              icon: const YqIcon(YqIcons.share, size: 20, tone: YqIconTone.idle),
            ),
          ],
        ),
      ],
    );
  }
}

/// One dua: optional occasion title, text, source line (always), favourite and share.
class DuaCard extends ConsumerWidget {
  const DuaCard({super.key, required this.item, this.gold = false});
  final ContentItem item;
  final bool gold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fav = ref.watch(favouritesProvider).valueOrNull?.contains(item.id) ?? false;
    final text = Theme.of(context).textTheme;
    return LiquidGlass(
      tone: gold ? GlassTone.gold : GlassTone.clear,
      padding: const EdgeInsets.all(YqSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.title.isNotEmpty) Text(item.title, style: text.labelLarge?.copyWith(color: YqColors.muted)),
          const SizedBox(height: YqSpace.s),
          Text(item.textAr, textDirection: TextDirection.rtl, style: YqText.dua),
          const SizedBox(height: YqSpace.s),
          Text(item.source, style: text.bodySmall?.copyWith(color: YqColors.goldText)),
          const SizedBox(height: YqSpace.s),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: fav ? t.duaFavRemove : t.duaFavAdd,
                onPressed: () => ref.read(favouritesProvider.notifier).toggle(item.id),
                icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? YqColors.gold : YqColors.muted),
              ),
              IconButton(
                tooltip: t.duaShare,
                onPressed: () => showTextShareCard(context, ref, text: item.textAr, reference: item.source, fileName: 'yaqeen-dua.png'),
                icon: const YqIcon(YqIcons.share, size: 20, tone: YqIconTone.idle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A section's list, or favourites.
class DuaCategoryScreen extends ConsumerWidget {
  const DuaCategoryScreen({super.key, required this.category});

  /// A [DuaCategory] key, or `favourites`.
  final String category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final lib = ref.watch(contentProvider).valueOrNull;
    final favs = ref.watch(favouritesProvider).valueOrNull ?? const <String>{};
    final cat = DuaCategory.of(category);
    final items = lib == null
        ? const <ContentItem>[]
        : cat != null
            ? lib.duas(cat)
            : [for (final id in favs) lib.byId(id)].whereType<ContentItem>().toList();
    final title = cat != null ? duaCategoryLabel(t, cat) : t.duaFavourites;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.xxl,
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: title, subtitle: t.duaCount(items.length))),
        children: [
          if (items.isEmpty) LiquidGlass(child: YqEmptyState(icon: YqIcons.dua, title: t.duaFavCount(0))),
          for (final i in items) ...[DuaCard(item: i), const SizedBox(height: YqSpace.m)],
        ],
      ),
    );
  }
}
