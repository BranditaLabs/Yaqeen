import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/reading_repository.dart';
import '../domain/quran_data.dart';

final bookmarksProvider = FutureProvider.autoDispose((ref) => ref.watch(readingRepositoryProvider).bookmarks());
final lastReadProvider = FutureProvider.autoDispose((ref) => ref.watch(readingRepositoryProvider).lastRead());

enum _Browse { surahs, juz, saved }

String surahTypeLabel(AppLocalizations t, Surah s) => s.meccan ? t.quranMeccan : t.quranMedinan;

/// `08 · Quran index` (spec §5.10). Fully offline from the first launch.
class QuranIndexScreen extends ConsumerStatefulWidget {
  const QuranIndexScreen({super.key, this.focusSearch = false});

  /// Home's search button opens the index with the field focused.
  final bool focusSearch;

  @override
  ConsumerState<QuranIndexScreen> createState() => _QuranIndexScreenState();
}

class _QuranIndexScreenState extends ConsumerState<QuranIndexScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  _Browse _browse = _Browse.surahs;
  int? _expandedJuz;

  @override
  void initState() {
    super.initState();
    if (widget.focusSearch) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openPage(int page) => context.push('/quran/read/$page');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = ref.watch(quranDataProvider);
    final config = ref.watch(remoteConfigProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));

    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: data.when(
          loading: () => const _IndexSkeleton(),
          error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(quranDataProvider)),
          data: (q) {
            final hits = q.search(_query.text);
            final searching = _query.text.trim().isNotEmpty;
            return ListView(
              padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, 140),
              children: [
                Row(
                  children: [
                    Expanded(child: Semantics(header: true, child: Text(t.quranTitle, style: YqText.display.copyWith(fontSize: 28)))),
                    if (config.isOn(Flags.listen))
                      GlassIconButton(
                        tooltip: t.quranListen,
                        onPressed: () async {
                          final last = await ref.read(readingRepositoryProvider).lastRead();
                          if (context.mounted) context.push('/quran/listen/${last?.surah ?? 1}');
                        },
                        icon: const YqIcon(YqIcons.listen, size: 20),
                      ),
                    if (config.isOn(Flags.hifz)) ...[
                      const SizedBox(width: YqSpace.s),
                      GlassIconButton(
                        tooltip: t.quranHifzPlan,
                        onPressed: () => context.push('/quran/hifz'),
                        icon: const YqIcon(YqIcons.bookmark, size: 20),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: YqSpace.l),
                TextField(
                  controller: _query,
                  focusNode: _focus,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: t.quranSearchHint,
                    prefixIcon: const Padding(padding: EdgeInsets.all(12), child: YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle)),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: t.clearSearch,
                            icon: const Icon(Icons.close_rounded, color: YqColors.muted),
                            onPressed: () => setState(_query.clear),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xB3FFFFFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(YqRadii.pill),
                      borderSide: const BorderSide(color: Color(0xE6FFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(YqRadii.pill),
                      borderSide: const BorderSide(color: Color(0xE6FFFFFF)),
                    ),
                  ),
                ),
                const SizedBox(height: YqSpace.l),
                if (searching)
                  hits.isEmpty
                      ? LiquidGlass(child: YqEmptyState(icon: YqIcons.search, title: t.quranNoResults, hint: t.quranNoResultsHint))
                      : LiquidGlass(
                          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                          child: Column(
                            children: [
                              for (final h in hits.take(30))
                                switch (h) {
                                  SurahHit(:final surah) =>
                                    _SurahRow(surah: surah, locale: locale, onTap: () => _openPage(surah.startPage)),
                                  AyahHit(:final surah, :final ref, :final page) => YqListRow(
                                      dense: true,
                                      title: '${t.quranSurahName(surah.nameAr)} · ${t.quranAyahN(ref.ayah)}',
                                      subtitle: t.quranPageN(page),
                                      onTap: () => _openPage(page),
                                    ),
                                },
                            ],
                          ),
                        )
                else ...[
                  _ContinueCards(q: q, locale: locale, onOpen: _openPage),
                  const SizedBox(height: YqSpace.l),
                  Semantics(
                    label: t.quranBrowse,
                    child: YqSegmented<_Browse>(
                      segments: [(_Browse.surahs, t.quranSurahs), (_Browse.juz, t.quranJuzs), (_Browse.saved, t.quranSaved)],
                      selected: _browse,
                      onChanged: (b) => setState(() => _browse = b),
                    ),
                  ),
                  const SizedBox(height: YqSpace.m),
                  switch (_browse) {
                    _Browse.surahs => LiquidGlass(
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                        child: Column(
                          children: [for (final s in q.surahs) _SurahRow(surah: s, locale: locale, onTap: () => _openPage(s.startPage))],
                        ),
                      ),
                    _Browse.juz => LiquidGlass(
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                        child: Column(
                          children: [
                            for (var j = 1; j <= 30; j++) ...[
                              YqListRow(
                                dense: true,
                                leading: _Medallion(j),
                                title: t.quranJuz(j),
                                subtitle: t.quranJuzStarts(q.surah(q.firstOfJuz(j).surah).name(locale), q.firstOfJuz(j).ayah),
                                trailing: IconButton(
                                  tooltip: t.quranHizbQuarter(j),
                                  icon: Icon(
                                    _expandedJuz == j ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                    color: YqColors.muted,
                                  ),
                                  onPressed: () => setState(() => _expandedJuz = _expandedJuz == j ? null : j),
                                ),
                                onTap: () => _openPage(q.juzStartPage(j)),
                              ),
                              if (_expandedJuz == j)
                                for (var k = (j - 1) * 8 + 1; k <= j * 8; k++)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(start: 48),
                                    child: YqListRow(
                                      dense: true,
                                      title: t.quranHizbQuarter(k),
                                      subtitle:
                                          '${q.surah(q.firstOfQuarter(k).surah).name(locale)} ${YqFormat.number(q.firstOfQuarter(k).ayah)}',
                                      trailing: Text(YqFormat.number(q.pageOf(q.firstOfQuarter(k))), style: YqText.numberSmall),
                                      onTap: () => _openPage(q.pageOf(q.firstOfQuarter(k))),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    _Browse.saved => _Bookmarks(q: q, locale: locale, onOpen: _openPage),
                  },
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Plain circle hairline medallion — no ornament (brand rule).
class _Medallion extends StatelessWidget {
  const _Medallion(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: YqColors.mist)),
        child: Text(YqFormat.number(n), style: YqText.numberSmall.copyWith(color: YqColors.ink)),
      );
}

class _SurahRow extends StatelessWidget {
  const _SurahRow({required this.surah, required this.locale, required this.onTap});
  final Surah surah;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return YqListRow(
      dense: true,
      leading: _Medallion(surah.number),
      title: surah.name(locale),
      subtitle: t.quranSurahMeta(surahTypeLabel(t, surah), t.quranAyahCount(surah.ayahCount)),
      trailing: Text(YqFormat.number(surah.startPage), style: YqText.numberSmall),
      onTap: onTap,
    );
  }
}

class _ContinueCards extends ConsumerWidget {
  const _ContinueCards({required this.q, required this.locale, required this.onOpen});
  final QuranData q;
  final String locale;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final last = ref.watch(lastReadProvider).valueOrNull;
    final marks = ref.watch(bookmarksProvider).valueOrNull ?? const [];
    final cards = <Widget>[
      if (last != null)
        _ContinueCard(
          title: t.quranSurahName(q.surah(last.surah).name(locale)),
          subtitle: '${t.quranPageN(last.page)} · ${t.quranLastRead}',
          onTap: () => onOpen(last.page),
        ),
      for (final b in marks.take(5))
        _ContinueCard(
          title: t.quranSurahName(q.surah(b.ref?.surah ?? q.firstOfPage(b.page).surah).name(locale)),
          subtitle: '${b.ref != null ? t.quranAyahN(b.ref!.ayah) : t.quranPageN(b.page)} · ${t.quranSavedMark}',
          gold: true,
          onTap: () => onOpen(b.page),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: YqSpace.m),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.title, required this.subtitle, required this.onTap, this.gold = false});
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return GlassTap(
      onTap: onTap,
      semanticLabel: '$title · $subtitle',
      child: SizedBox(
        width: 220,
        child: LiquidGlass(
          tone: gold ? GlassTone.gold : GlassTone.clear,
          padding: const EdgeInsets.all(YqSpace.m),
          child: Row(
            children: [
              YqIconTile(gold ? YqIcons.bookmark : YqIcons.quran, gold: gold),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bookmarks extends ConsumerWidget {
  const _Bookmarks({required this.q, required this.locale, required this.onOpen});
  final QuranData q;
  final String locale;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final marks = ref.watch(bookmarksProvider);
    return marks.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(bookmarksProvider)),
      data: (list) => list.isEmpty
          ? LiquidGlass(child: YqEmptyState(icon: YqIcons.bookmark, title: t.quranNoBookmarks, hint: t.quranNoBookmarksHint))
          : LiquidGlass(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
              child: Column(
                children: [
                  for (final b in list)
                    YqListRow(
                      dense: true,
                      leading: const YqIconTile(YqIcons.bookmark, gold: true),
                      title: t.quranSurahName(q.surah(b.ref?.surah ?? q.firstOfPage(b.page).surah).name(locale)),
                      subtitle:
                          b.kind == BookmarkKind.ayah ? '${t.quranAyahN(b.ref!.ayah)} · ${t.quranPageN(b.page)}' : t.quranPageN(b.page),
                      onTap: () => onOpen(b.page),
                    ),
                ],
              ),
            ),
    );
  }
}

class _IndexSkeleton extends StatelessWidget {
  const _IndexSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(YqSpace.gutter),
        child: YqSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YqSkeletonBox(height: 32, width: 180),
              SizedBox(height: 16),
              YqSkeletonBox(height: 52, radius: YqRadii.pill),
              SizedBox(height: 16),
              YqSkeletonBox(height: 90, radius: YqRadii.card),
              SizedBox(height: 16),
              YqSkeletonBox(height: 400, radius: YqRadii.card),
            ],
          ),
        ),
      );
}
