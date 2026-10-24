import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/share_card.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
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

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: t.duasTitle),
            children: content.when(
              loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 220, radius: YqRadii.hero))],
              error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(contentProvider))],
              data: (lib) {
                final ofDay = lib.duaOfTheDay(today);
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
                return [
                  Text(t.duaOfTheDay, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.goldText)),
                  const SizedBox(height: YqSpace.s),
                  DuaCard(item: ofDay, gold: true),
                  const SizedBox(height: YqSpace.xl),
                  Text(t.duaSections, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: YqSpace.m),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: YqSpace.m,
                    crossAxisSpacing: YqSpace.m,
                    childAspectRatio: 1.7,
                    children: [
                      for (final c in DuaCategory.values)
                        if (lib.duas(c).isNotEmpty)
                          _SectionTile(
                            title: duaCategoryLabel(t, c),
                            subtitle: t.duaCount(lib.duas(c).length),
                            onTap: () => context.push('/home/duas/${c.key}'),
                          ),
                      _SectionTile(
                        title: t.duaFavourites,
                        subtitle: t.duaFavCount(favs.where((id) => lib.byId(id) != null).length),
                        gold: true,
                        onTap: () => context.push('/home/duas/favourites'),
                      ),
                    ],
                  ),
                ];
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.title, required this.subtitle, required this.onTap, this.gold = false});
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) => GlassTap(
        onTap: onTap,
        semanticLabel: '$title، $subtitle',
        child: LiquidGlass(
          padding: const EdgeInsets.all(YqSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: YqSpace.xs),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: gold ? YqColors.goldText : YqColors.muted)),
            ],
          ),
        ),
      );
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
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: title, subtitle: t.duaCount(items.length)),
            children: [
              if (items.isEmpty) LiquidGlass(child: YqEmptyState(icon: YqIcons.dua, title: t.duaFavCount(0))),
              for (final i in items) ...[DuaCard(item: i), const SizedBox(height: YqSpace.m)],
            ],
          ),
        ),
      ),
    );
  }
}
