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
import '../../../core/time/zoned.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/reading_repository.dart';
import '../domain/quran_data.dart';
import '../../home/widgets/orbs.dart';
import 'reader_screen.dart';

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

    final bar = YqStageBar(
      title: t.quranTitle,
      large: true,
      actions: [
        if (config.isOn(Flags.hifz))
          GlassIconButton(
            tooltip: t.quranHifzPlan,
            onPressed: () => context.push('/quran/hifz'),
            icon: const YqIcon(YqIcons.bookmark, size: 20),
          ),
      ],
    );

    return data.when(
      loading: () => YqCanvas(stage: YqStage(child: bar), children: const [_IndexSkeleton()]),
      error: (_, __) => YqCanvas(
        stage: YqStage(child: bar),
        children: [YqErrorState(onRetry: () => ref.invalidate(quranDataProvider))],
      ),
      data: (q) {
        final hits = q.search(_query.text);
        final searching = _query.text.trim().isNotEmpty;
        final lazySurahs = !searching && _browse == _Browse.surahs;
        return YqCanvas(
          stage: YqStage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar,
                const SizedBox(height: YqSpace.xl),
                _Resume(q: q, locale: locale, onOpen: _openPage),
                const SizedBox(height: YqSpace.l),
                _SearchField(
                  controller: _query,
                  focusNode: _focus,
                  hint: t.quranSearchHint,
                  clearLabel: t.clearSearch,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
          slivers: [
            if (lazySurahs)
              DecoratedSliver(
                decoration: _cardDecoration,
                sliver: SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.xs),
                  sliver: SliverList.builder(
                    itemCount: q.surahs.length,
                    itemBuilder: (context, i) {
                      final s = q.surahs[i];
                      return _SurahRow(surah: s, locale: locale, divider: i > 0, onTap: () => _openPage(s.startPage));
                    },
                  ),
                ),
              ),
          ],
          children: [
            if (searching)
              hits.isEmpty
                  ? LiquidGlass(child: YqEmptyState(icon: YqIcons.search, title: t.quranNoResults, hint: t.quranNoResultsHint))
                  : YqGroup(
                      children: [
                        for (final h in hits.take(30))
                          switch (h) {
                            SurahHit(:final surah) => _SurahRow(surah: surah, locale: locale, onTap: () => _openPage(surah.startPage)),
                            AyahHit(:final surah, :final ref, :final page) => YqListRow(
                                dense: true,
                                title: '${t.quranSurahName(surah.nameAr)} · ${t.quranAyahN(ref.ayah)}',
                                subtitle: t.quranPageN(page),
                                onTap: () => _openPage(page),
                              ),
                          },
                      ],
                    )
            else ...[
              _Orbs(q: q, listen: config.isOn(Flags.listen)),
              const SizedBox(height: YqSpace.xl),
              _SavedCards(q: q, locale: locale, onOpen: _openPage),
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
                // Built lazily below (SliverList): only the rows on screen exist.
                _Browse.surahs => const SizedBox.shrink(),
                _Browse.juz => YqGroup(
                    children: [
                      for (var j = 1; j <= 30; j++)
                        Column(
                          children: [
                            YqListRow(
                              dense: true,
                              leading: _Medallion(j),
                              title: t.quranJuz(j),
                              subtitle: t.quranJuzStarts(q.surah(q.firstOfJuz(j).surah).name(locale), q.firstOfJuz(j).ayah),
                              trailing: IconButton(
                                tooltip: t.quranHizbQuarter(j),
                                icon: Icon(_expandedJuz == j ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: YqColors.muted),
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
                                    subtitle: '${q.surah(q.firstOfQuarter(k).surah).name(locale)} ${YqFormat.number(q.firstOfQuarter(k).ayah)}',
                                    trailing: Text(YqFormat.number(q.pageOf(q.firstOfQuarter(k))), style: YqText.numberSmall),
                                    onTap: () => _openPage(q.pageOf(q.firstOfQuarter(k))),
                                  ),
                                ),
                          ],
                        ),
                    ],
                  ),
                _Browse.saved => _Bookmarks(q: q, locale: locale, onOpen: _openPage),
              },
            ],
          ],
        );
      },
    );
  }
}

/// The stage's moment: where you are in the mushaf — the surah in large type (tap to resume),
/// page and juz, and the khatma's progress through the 604 pages. Friday suggests al-Kahf.
class _Resume extends ConsumerWidget {
  const _Resume({required this.q, required this.locale, required this.onOpen});
  final QuranData q;
  final String locale;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final last = ref.watch(lastReadProvider).valueOrNull;
    final page = last?.page ?? 1;
    final first = q.firstOfPage(page);
    final name = q.surah(first.surah).name(locale);
    final meta = t.homeReadingMeta(name, page, q.juzOf(first));
    return GlassTap(
      onTap: () => onOpen(page),
      semanticLabel: '${last == null ? t.homeStartReading : t.continueReading}، $meta',
      child: YqMoment(
        eyebrow: last == null ? t.homeStartReading : t.continueReading,
        value: Text(
          name,
          // The brand display face is Arabic-only; Latin names use Amiri.
          style: YqMoment.display(context, size: 46).copyWith(
            fontFamily: locale == 'ar' ? YqFonts.display : YqFonts.naskh,
            fontFamilyFallback: YqFonts.displayFallback,
          ),
        ),
        caption: Column(
          children: [
            Text(meta),
            const SizedBox(height: YqSpace.s),
            SizedBox(
              width: 180,
              child: YqProgressLine(value: page / QuranData.pageCount, color: YqColors.gold, track: const Color(0x33C6A867)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.hint, required this.clearLabel, required this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final String clearLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.pill), borderSide: const BorderSide(color: Color(0xF2FFFFFF)));
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => onChanged(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Padding(padding: EdgeInsets.all(12), child: YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle)),
        suffixIcon: controller.text.trim().isNotEmpty
            ? IconButton(
                tooltip: clearLabel,
                icon: const Icon(Icons.close_rounded, color: YqColors.muted),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xCCFFFFFF),
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

/// Complications: today's wird as liquid, the khatma as a ring, and listening.
class _Orbs extends ConsumerWidget {
  const _Orbs({required this.q, required this.listen});
  final QuranData q;
  final bool listen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    final done = wird != null && wird.date == Zoned.isoDate(today) ? wird.count : 0;
    final last = ref.watch(lastReadProvider).valueOrNull;
    final page = last?.page ?? 0;
    final khatma = t.quranKhatmaStatus(YqFormat.number(page), YqFormat.number(QuranData.pageCount));
    final surah = last == null ? 1 : q.firstOfPage(last.page).surah;
    return YqOrbRow(
      orbs: [
        WirdOrb(done: done, goal: s.wirdGoalPages),
        YqOrb(
          title: t.quranKhatma,
          status: khatma,
          semanticLabel: '${t.quranKhatma}، $khatma',
          onTap: last == null ? null : () => context.push('/quran/read/${last.page}'),
          disc: YqRing(
            value: page / QuranData.pageCount,
            gold: true,
            size: YqOrb.defaultSize - 12,
            stroke: 5,
            child: Text(
              '${YqFormat.number((page * 100 / QuranData.pageCount).floor())}%',
              textDirection: TextDirection.ltr,
              style: YqText.numberSmall.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: YqColors.ink),
            ),
          ),
        ),
        if (listen)
          YqOrb(
            title: t.quranListen,
            status: t.quranSurahName(q.surah(surah).name(s.locale)),
            semanticLabel: '${t.quranListen}، ${t.quranSurahName(q.surah(surah).name(s.locale))}',
            onTap: () => context.push('/quran/listen/$surah'),
            disc: Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: YqColors.navy, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: YqColors.goldLight, size: 30),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
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
  const _SurahRow({required this.surah, required this.locale, required this.onTap, this.divider = false});
  final Surah surah;
  final String locale;
  final VoidCallback onTap;

  /// A hairline above (rows inside the lazy glass card).
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final row = YqListRow(
      dense: true,
      leading: _Medallion(surah.number),
      title: surah.name(locale),
      subtitle: t.quranSurahMeta(surahTypeLabel(t, surah), t.quranAyahCount(surah.ayahCount)),
      trailing: Text(YqFormat.number(surah.startPage), style: YqText.numberSmall),
      onTap: onTap,
    );
    return divider ? Column(children: [const YqDivider(), row]) : row;
  }
}

/// Bookmarks as a gold strip above the browser (when there are any).
class _SavedCards extends ConsumerWidget {
  const _SavedCards({required this.q, required this.locale, required this.onOpen});
  final QuranData q;
  final String locale;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final marks = ref.watch(bookmarksProvider).valueOrNull ?? const [];
    if (marks.isEmpty) return const SizedBox.shrink();
    final cards = [
      for (final b in marks.take(5))
        _ContinueCard(
          title: t.quranSurahName(q.surah(b.ref?.surah ?? q.firstOfPage(b.page).surah).name(locale)),
          subtitle: '${b.ref != null ? t.quranAyahN(b.ref!.ayah) : t.quranPageN(b.page)} · ${t.quranSavedMark}',
          gold: true,
          onTap: () => onOpen(b.page),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: YqSpace.l),
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: YqSpace.m),
          itemBuilder: (_, i) => cards[i],
        ),
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
          : YqGroup(
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
    );
  }
}

class _IndexSkeleton extends StatelessWidget {
  const _IndexSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.zero,
        child: YqSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YqSkeletonBox(height: 120, radius: YqRadii.card),
              SizedBox(height: 16),
              YqSkeletonBox(height: 400, radius: YqRadii.card),
            ],
          ),
        ),
      );
}

/// The glass card look as a plain decoration, so a long list can be a lazy sliver inside it.
final _cardDecoration = BoxDecoration(
  borderRadius: BorderRadius.circular(YqRadii.card),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [YqColors.white.withAlpha(168), YqColors.white.withAlpha(148)],
  ),
  border: Border.all(color: const Color(0xE6FFFFFF)),
  boxShadow: const [BoxShadow(color: Color(0x260F1A36), blurRadius: 30, spreadRadius: -14, offset: Offset(0, 14))],
);
