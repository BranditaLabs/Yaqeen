import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../listen/presentation/listen_controller.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/reading_repository.dart';
import '../domain/annotations.dart';
import '../domain/mushaf_layout.dart';
import '../domain/quran_data.dart';
import '../domain/reading_stats.dart';
import '../domain/wird.dart';
import 'ayah_sheet.dart';
import 'jump_sheet.dart';
import 'madani_page.dart';
import 'mushaf_page.dart';
import 'note_sheet.dart';
import 'page_curl.dart';
import 'quran_index_screen.dart';
import 'quran_providers.dart';

final todayWirdProvider = FutureProvider.autoDispose((ref) => ref.watch(readingRepositoryProvider).wird());

/// Two mushaf pages side by side when the screen is wide (tablet, or a phone in landscape).
bool spreadLayout(Size size) => size.width > size.height && size.width >= 700;

/// `09 · Reading mode` (spec §5.11) — full screen, offline, the heart of the app.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.initialPage, this.focus});
  final int initialPage;

  /// An ayah to light briefly and bring into view (search, bookmarks, «انتقل إلى»).
  final AyahRef? focus;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _pager = MushafPagerController();
  bool _spread = false;
  late int _page = widget.initialPage.clamp(1, QuranData.pageCount);
  bool _chrome = true;
  bool _locked = false;
  bool _hint = false;
  AyahRef? _selected;
  AyahRef? _focus;
  Timer? _focusTimer;
  Timer? _hideTimer;
  Timer? _wirdTimer;
  DateTime _pageShownAt = DateTime.now();
  bool _pageMarked = false;
  MemoriseMode _memorise = MemoriseMode.off;
  final Set<AyahRef> _revealed = {};
  // Wird counting outlives the widget (the last page counts on exit), so it reads the container, not `ref`.
  late final ProviderContainer _c;

  @override
  void initState() {
    super.initState();
    _c = ProviderScope.containerOf(context, listen: false);
    final s = ref.read(settingsProvider);
    _hint = !s.readerHintSeen;
    if (s.keepAwake) ref.read(deviceServicesProvider).keepAwake(true);
    _setFocus(widget.focus);
    _onPageShown(_page);
    _scheduleHide();
  }

  @override
  void dispose() {
    _leavePage(); // the last page counts too if it was read long enough
    _hideTimer?.cancel();
    _wirdTimer?.cancel();
    _focusTimer?.cancel();
    _pager.dispose();
    _c.read(deviceServicesProvider).keepAwake(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Pages on screen for [page] (both of a spread).
  List<int> _visible(int page) {
    if (!_spread) return [page];
    final first = page.isOdd ? page : page - 1;
    return [first, if (first < QuranData.pageCount) first + 1];
  }

  int _indexOf(int page, bool spread) => spread ? (page - 1) ~/ 2 : page - 1;

  /// Pages at a pager index: one, or the spread's two (odd on the right).
  List<int> _pagesAt(int index) => _spread ? [index * 2 + 1, if (index * 2 + 2 <= QuranData.pageCount) index * 2 + 2] : [index + 1];

  /// The pager moved (a turn, the slider, a jump): the old page counts, the new one starts.
  void _showPage(int page) {
    if (page == _page) return;
    _leavePage();
    setState(() {
      _page = page;
      _selected = null;
      _revealed.clear();
    });
    _onPageShown(page);
  }

  /// Fonts for the open pages first, then ±2 neighbours once the page has settled.
  void _warmFonts(int page) {
    final layout = _c.read(mushafLayoutProvider).valueOrNull;
    if (layout == null) return;
    final fonts = _c.read(mushafFontsProvider);
    for (final p in _visible(page)) {
      fonts.prefetch(layout.fontsFor(p));
    }
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _page != page) return;
      final near = _spread ? [page - 2, page - 1, page + 2, page + 3] : [page - 2, page - 1, page + 1, page + 2];
      for (final p in near) {
        if (p >= 1 && p <= QuranData.pageCount) fonts.prefetch(layout.fontsFor(p));
      }
    });
  }

  /// Taps on a page: the outer third turns (left → next, as in a mushaf), the middle shows the tools.
  void _onPageTap(Offset global) {
    if (_locked) return;
    final w = MediaQuery.sizeOf(context).width;
    if (global.dx < w / 3) {
      _pager.next();
    } else if (global.dx > w * 2 / 3) {
      _pager.previous();
    } else {
      _toggleChrome();
    }
  }

  void _setFocus(AyahRef? ref) {
    _focusTimer?.cancel();
    _focus = ref;
    if (ref != null) {
      _focusTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _focus = null);
      });
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_hint) _setChrome(false);
    });
  }

  void _setChrome(bool on) {
    setState(() => _chrome = on);
    if (ref.read(settingsProvider).immersiveReading) {
      SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    }
  }

  void _toggleChrome() {
    _setChrome(!_chrome);
    if (_chrome) _scheduleHide();
  }

  Future<void> _onPageShown(int page) async {
    _pageShownAt = DateTime.now();
    _warmFonts(page);
    _wirdTimer?.cancel();
    // Counting at 20 s while still on the page — the user may keep reading the same page.
    _wirdTimer = Timer(const Duration(seconds: WirdRules.minSecondsPerPage), () {
      for (final p in _visible(page)) {
        _countPage(p, const Duration(seconds: WirdRules.minSecondsPerPage));
      }
    });
    final q = await _c.read(quranDataProvider.future);
    final reading = _c.read(readingRepositoryProvider);
    await reading.saveLastRead(page, q.firstOfPage(page).surah, _c.read(clockProvider)());
    final marks = await reading.bookmarks();
    if (mounted) setState(() => _pageMarked = marks.any((b) => b.kind == BookmarkKind.page && _visible(page).contains(b.page)));
  }

  /// Leaving the current page: its pages may count, and the time goes into the reading stats.
  void _leavePage() {
    final shown = DateTime.now().difference(_pageShownAt);
    for (final p in _visible(_page)) {
      _countPage(p, shown);
    }
    _addSeconds(shown.inSeconds.clamp(0, ReadingStats.maxSecondsPerView));
  }

  String _today() {
    final s = _c.read(settingsProvider);
    return Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, _c.read(clockProvider)()));
  }

  Future<void> _addSeconds(int seconds) async {
    if (seconds <= 0) return;
    await _c.read(readingRepositoryProvider).addStats(_today(), seconds: seconds);
  }

  /// Wird: page counted after ≥ 20 s visible; reaching the goal ticks the challenge task once a day.
  /// The same reading moves the khatma plan and the week's stats.
  Future<void> _countPage(int page, Duration visibleFor) async {
    final s = _c.read(settingsProvider);
    final today = _today();
    final reading = _c.read(readingRepositoryProvider);
    if (visibleFor.inSeconds >= WirdRules.minSecondsPerPage) {
      final k = await reading.khatmaRead(page, today);
      if (k.plan != null) _c.invalidate(khatmaProvider);
      if (k.justFinished) {
        _c.invalidate(khatmaHistoryProvider);
        if (mounted) {
          HapticFeedback.heavyImpact();
          YqToast.show(context, AppLocalizations.of(context).khatmaDoneToast, duration: const Duration(seconds: 4));
        }
      }
    }
    final r = WirdRules.read(await reading.wird(), today: today, page: page, visibleFor: visibleFor, goalPages: s.wirdGoalPages);
    if (!r.counted) return;
    await reading.saveWird(r.day);
    await reading.addStats(today, pages: 1);
    _c.invalidate(todayWirdProvider);
    _c.invalidate(readingStatsProvider);
    if (r.tickNow) {
      if (_c.read(sessionProvider).canEarnPoints) {
        await _c.read(challengeRepositoryProvider).complete(TaskKey.wird, today);
        _c.invalidate(challengeControllerProvider);
      }
      // The «wird missing before Isha» reminder is no longer needed today.
      _c.read(remindersControllerProvider.notifier).replan().ignore();
    }
  }

  Future<void> _togglePageMark() async {
    final now = ref.read(clockProvider)();
    final saved = await ref.read(readingRepositoryProvider).toggle(Bookmark(kind: BookmarkKind.page, page: _page, ref: null, at: now));
    ref.invalidate(bookmarksProvider);
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _pageMarked = saved);
  }

  void _dismissHint() {
    setState(() => _hint = false);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(readerHintSeen: true), sync: false);
    _scheduleHide();
  }

  void _goTo(int page, {AyahRef? focus}) {
    setState(() => _setFocus(focus));
    // In a spread the index's first page is what counts as shown (as a turn would).
    _showPage(_pagesAt(_indexOf(page.clamp(1, QuranData.pageCount), _spread)).first);
  }

  Future<void> _openJump(QuranData q, String locale) async {
    _hideTimer?.cancel();
    final target = await showJumpSheet(context, quran: q, currentPage: _page, locale: locale);
    if (target != null && mounted) _goTo(target.page, focus: target.ayah);
    if (mounted) _scheduleHide();
  }

  Future<void> _openMemorise() async {
    _hideTimer?.cancel();
    final t = AppLocalizations.of(context);
    final picked = await showYqSheet<MemoriseMode>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.memoriseTitle, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.xs),
          Text(t.memoriseHint, style: Theme.of(c).textTheme.bodySmall),
          const SizedBox(height: YqSpace.m),
          for (final (m, label) in [
            (MemoriseMode.off, t.memoriseOff),
            (MemoriseMode.ayat, t.memoriseAyat),
            (MemoriseMode.words, t.memoriseWords),
          ])
            YqListRow(
              title: label,
              trailing: m == _memorise ? const Icon(Icons.check_rounded, color: YqColors.lapis) : const SizedBox.shrink(),
              onTap: () => Navigator.of(c).pop(m),
            ),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _memorise = picked;
        _revealed.clear();
      });
      if (picked != MemoriseMode.off) _setChrome(false);
    }
  }

  /// Night pages from Maghrib until sunrise when «تلقائياً» is on.
  MushafTheme _effectiveTheme(AppSettings s, DateTime now) {
    if (!s.autoNight) return s.mushafTheme;
    final repo = ref.read(prayerRepositoryProvider);
    final times = repo.forDate(s, repo.today(s, now));
    final t = now.toUtc();
    return t.isAfter(times.maghrib) || t.isBefore(times.sunrise) ? MushafTheme.night : s.mushafTheme;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Only what the pages draw: other settings writes (e.g. readerHintSeen, wird counters) must not
    // rebuild the reader and its pre-built neighbour pages.
    final look0 = ref.watch(
      settingsProvider.select(
        (s) => (
          theme: s.mushafTheme,
          autoNight: s.autoNight,
          fontSize: s.quranFontSize,
          comfortable: s.comfortableSpacing,
          locale: s.locale,
          turn: s.pageTurn,
        ),
      ),
    );
    final theme = look0.autoNight ? _effectiveTheme(ref.read(settingsProvider), ref.read(clockProvider)()) : look0.theme;
    final look = (theme: theme, fontSize: look0.fontSize, comfortable: look0.comfortable, locale: look0.locale);
    final data = ref.watch(quranDataProvider);
    final layout = ref.watch(mushafLayoutProvider).valueOrNull;
    final annotations = ref.watch(annotationsProvider).valueOrNull ?? Annotations.empty;
    final colors = MushafColors.of(look.theme);
    final night = look.theme == MushafTheme.night;
    // Highlight the ayah the player is on while recitation is playing (spec §5.13).
    final playing = ref.watch(listenControllerProvider.select((l) => l.playing && l.sampleOf == null ? l.ref : null));
    // Rotation switches between one page and a spread, keeping the page.
    _spread = spreadLayout(MediaQuery.sizeOf(context));
    final spread = _spread;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: night ? YqColors.nightBg : colors.page,
        body: data.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(YqSpace.gutter),
            child: Center(child: YqSkeleton(child: YqSkeletonText(lines: 12, lineHeight: 18))),
          ),
          error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(quranDataProvider)),
          data: (q) {
            final first = q.firstOfPage(_page);
            Widget frame(int page) => _PageFrame(
                  quran: q,
                  layout: layout,
                  page: page,
                  look: look,
                  spread: spread,
                  selected: _selected ?? _focus,
                  playing: playing,
                  onBackgroundTap: _onPageTap,
                  onOpenSettings: () => showReaderSettings(context),
                  annotations: annotations,
                  memorise: _memorise,
                  revealed: _revealed,
                  onAyahTap: (r) => setState(() => _revealed.contains(r) ? _revealed.remove(r) : _revealed.add(r)),
                  onNoteTap: (r) => showNoteSheet(context, quran: q, ref: r),
                  onAyahLongPress: _locked
                      ? null
                      : (ref0) async {
                          HapticFeedback.mediumImpact();
                          setState(() => _selected = ref0);
                          await showAyahSheet(context, quran: q, ref: ref0);
                          if (mounted) setState(() => _selected = null);
                        },
                );
            return Stack(
              children: [
                // Pages: in RTL mushaf order — dragging left → right (or tapping the left third) turns to
                // the next page, also in English. Each page always fits the screen: nothing scrolls.
                Semantics(
                  customSemanticsActions: _locked
                      ? null
                      : {
                          CustomSemanticsAction(label: t.readerNextPage): _pager.next,
                          CustomSemanticsAction(label: t.readerPreviousPage): _pager.previous,
                        },
                  child: MushafPager(
                    controller: _pager,
                    count: spread ? (QuranData.pageCount / 2).ceil() : QuranData.pageCount,
                    index: _indexOf(_page, spread),
                    spread: spread,
                    pagesOf: _pagesAt,
                    pageBuilder: (context, p) => frame(p),
                    onIndexChanged: (i) => _showPage(_pagesAt(i).first),
                    style: turnStyleOf(look0.turn, reduceMotion: reduceMotion),
                    enabled: !_locked,
                    paper: colors.page,
                    shade: night ? YqColors.nightBg : YqColors.paperInk,
                    onTap: _onPageTap,
                    spineBuilder: (_) => _Spine(night: night),
                  ),
                ),
                if (_memorise != MemoriseMode.off && !_locked && !_chrome)
                  _MemoriseBanner(
                    mode: _memorise,
                    onShowAll: () => setState(() {
                      for (final p in _visible(_page)) {
                        for (final seg in q.page(p)) {
                          _revealed.addAll(seg.ayat.map((a) => a.ref));
                        }
                      }
                    }),
                    onHideAll: () => setState(_revealed.clear),
                    onExit: () => setState(() {
                      _memorise = MemoriseMode.off;
                      _revealed.clear();
                    }),
                  ),
                if (!_locked) ...[
                  _TopChrome(
                    visible: _chrome,
                    night: night,
                    marked: _pageMarked,
                    onExit: () => context.canPop() ? context.pop() : context.go('/quran'),
                    onSettings: () => showReaderSettings(context),
                    onLock: () => setState(() {
                      _locked = true;
                      _setChrome(false);
                    }),
                    onMark: _togglePageMark,
                    onTitle: () => _openJump(q, look.locale),
                    title: q.surah(first.surah).name(look.locale),
                    subtitle: t.quranJuzHizb(q.juzOf(first), q.hizbOf(first)),
                  ),
                  _BottomChrome(
                    visible: _chrome,
                    night: night,
                    page: _page,
                    quran: q,
                    memorise: _memorise != MemoriseMode.off,
                    onJump: (p) => _goTo(p),
                    onMemorise: _openMemorise,
                  ),
                ] else
                  _LockOverlay(onUnlock: () => setState(() => _locked = false)),
                if (_hint) _FirstOpenHint(onDismiss: _dismissHint),
              ],
            );
          },
        ),
      ),
    );
  }
}

typedef _Look = ({MushafTheme theme, double fontSize, bool comfortable, String locale});

/// The fold between the two pages of a spread: a soft shade, darkest at the spine.
class _Spine extends StatelessWidget {
  const _Spine({required this.night});
  final bool night;

  @override
  Widget build(BuildContext context) {
    final ink = night ? YqColors.nightBg : YqColors.paperInk;
    return Center(
      child: SizedBox(
        width: 56,
        height: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ink.withAlpha(0),
                ink.withAlpha(night ? 70 : 26),
                ink.withAlpha(night ? 120 : 52),
                ink.withAlpha(night ? 70 : 26),
                ink.withAlpha(0),
              ],
              stops: const [0, 0.4, 0.5, 0.6, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// One page of the mushaf: a thin header (surah · juz / hizb), the page itself — always fitted, never
/// scrolled — and the page number. The page's free edge shows a hint of the pages stacked under it.
class _PageFrame extends ConsumerWidget {
  const _PageFrame({
    required this.quran,
    required this.layout,
    required this.page,
    required this.look,
    required this.spread,
    required this.annotations,
    required this.memorise,
    required this.revealed,
    this.selected,
    this.playing,
    this.onAyahLongPress,
    this.onAyahTap,
    this.onNoteTap,
    this.onBackgroundTap,
    this.onOpenSettings,
  });
  final QuranData quran;
  final MushafLayout? layout;
  final AyahRef? playing;
  final int page;
  final _Look look;
  final bool spread;
  final AyahRef? selected;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;
  final ValueChanged<AyahRef>? onAyahLongPress;
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;
  final ValueChanged<Offset>? onBackgroundTap;
  final VoidCallback? onOpenSettings;

  /// «¼ الحزب 5» when a hizb quarter starts on this page, else «الجزء N · الحزب N».
  String _place(AppLocalizations t, AyahRef first) {
    for (final seg in quran.page(page)) {
      for (final a in seg.ayat) {
        final q = quran.quarterStartingAt(a.ref);
        if (q == null || a.ref == const AyahRef(1, 1)) continue;
        final hizb = (q - 1) ~/ 4 + 1;
        final part = (q - 1) % 4;
        final mark = (q - 1) % 8 == 0
            ? t.quranMarkJuz(YqFormat.number((q - 1) ~/ 8 + 1))
            : part == 0
                ? t.quranMarkHizb(YqFormat.number(hizb))
                : t.quranMarkQuarter(const ['', '¼', '½', '¾'][part], YqFormat.number(hizb));
        return '${t.quranJuzHizb(quran.juzOf(first), quran.hizbOf(first))} · $mark';
      }
    }
    return t.quranJuzHizb(quran.juzOf(first), quran.hizbOf(first));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final colors = MushafColors.of(look.theme);
    final first = quran.firstOfPage(page);
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width / (spread ? 2 : 1);
    // Print-like margins: a little wider on tablets; the outer side keeps room for the page edge.
    final side = (width * 0.045).clamp(10.0, 30.0);
    final sajdah = quran.page(page).any((s) => s.ayat.any((a) => quran.sajdas.contains(a.ref)));
    final label = TextStyle(fontSize: 11.5, height: 1.2, color: colors.muted, fontFamily: YqFonts.ui);
    // Free edge: left in single-page view (where the next pages are); outer edge of each spread page.
    final edgeLeft = !spread || page.isEven;
    final fonts = ref.watch(mushafFontsProvider);
    return ColoredBox(
      color: colors.page,
      child: CustomPaint(
        foregroundPainter: _PaperEdge(left: edgeLeft, color: colors.frame, night: look.theme == MushafTheme.night),
        child: MediaQuery.withNoTextScaling(
          child: Column(
            children: [
              SizedBox(height: pad.top + 6),
              // Page header (always visible, quiet): surah · juz / hizb (+ where a quarter starts).
              SizedBox(
                height: 18,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side + 4),
                  child: Row(
                    children: [
                      Text(quran.surah(first.surah).nameAr, style: label),
                      const Spacer(),
                      if (sajdah) ...[
                        Text(t.quranMarkSajdah, style: label.copyWith(color: YqColors.goldText)),
                        Text('  ·  ', style: label),
                      ],
                      Flexible(child: Text(_place(t, first), style: label, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: _PageBody(
                    quran: quran,
                    layout: layout,
                    page: page,
                    look: look,
                    selected: selected,
                    playing: playing,
                    annotations: annotations,
                    memorise: memorise,
                    revealed: revealed,
                    onAyahLongPress: onAyahLongPress,
                    onAyahTap: onAyahTap,
                    onNoteTap: onNoteTap,
                    onBackgroundTap: onBackgroundTap,
                  ),
                ),
              ),
              SizedBox(
                height: 22,
                child: ListenableBuilder(
                  listenable: fonts,
                  builder: (context, _) {
                    final number = Text(
                      t.quranPageOf(page),
                      style: label.copyWith(fontFamily: YqFonts.numbers, fontFamilyFallback: const [YqFonts.ui], fontSize: 12.5),
                    );
                    if (layout == null || !fonts.hasFailed(page)) return Center(child: number);
                    // Offline and the page font isn't here yet: the text page is shown; say how to get the print.
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        number,
                        Text('  ·  ', style: label),
                        GestureDetector(
                          onTap: () {
                            fonts.ensure(page);
                            onOpenSettings?.call();
                          },
                          child: Text(t.readerFallbackHint, style: label.copyWith(color: YqColors.lapis)),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: pad.bottom + 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hint of the paper stacked under the page: a few hairlines along its free edge.
class _PaperEdge extends CustomPainter {
  const _PaperEdge({required this.left, required this.color, required this.night});
  final bool left;
  final Color color;
  final bool night;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final x = left ? 1.0 + i * 2.2 : size.width - 1 - i * 2.2;
      final paint = Paint()
        ..color = color.withAlpha(((night ? 70 : 110) * (1 - i / 3)).round())
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(x, size.height * 0.03 + i * 3), Offset(x, size.height * 0.97 - i * 3), paint);
    }
  }

  @override
  bool shouldRepaint(_PaperEdge old) => old.left != left || old.color != color || old.night != night;
}

/// The page itself: the printed Madani page once its font is on the device, else (briefly while it
/// loads, or offline) the text page auto-fitted to the same box. Swaps with a short fade.
class _PageBody extends ConsumerStatefulWidget {
  const _PageBody({
    required this.quran,
    required this.layout,
    required this.page,
    required this.look,
    required this.annotations,
    required this.memorise,
    required this.revealed,
    this.selected,
    this.playing,
    this.onAyahLongPress,
    this.onAyahTap,
    this.onNoteTap,
    this.onBackgroundTap,
  });
  final QuranData quran;
  final MushafLayout? layout;
  final int page;
  final _Look look;
  final AyahRef? selected;
  final AyahRef? playing;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;
  final ValueChanged<AyahRef>? onAyahLongPress;
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;
  final ValueChanged<Offset>? onBackgroundTap;

  @override
  ConsumerState<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends ConsumerState<_PageBody> {
  /// How long a page waits for its font (disk or network) before the text page stands in.
  static const _grace = Duration(milliseconds: 650);
  Timer? _timer;
  bool _waited = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_PageBody old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.layout != widget.layout) {
      _waited = false;
      _request();
    }
  }

  void _request() {
    final layout = widget.layout;
    _timer?.cancel();
    if (layout == null) return;
    final fonts = ref.read(mushafFontsProvider);
    final need = layout.fontsFor(widget.page);
    if (fonts.allReady(need)) return;
    for (final p in need) {
      fonts.ensure(p);
    }
    _timer = Timer(_grace, () {
      if (mounted) setState(() => _waited = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fonts = ref.watch(mushafFontsProvider);
    return ListenableBuilder(
      listenable: fonts,
      builder: (context, _) {
        final layout = widget.layout;
        final ready = layout != null && fonts.allReady(layout.fontsFor(widget.page));
        final failed = layout != null && layout.fontsFor(widget.page).any(fonts.hasFailed);
        final Widget child;
        if (ready) {
          child = MadaniPage(
            key: const ValueKey('madani'),
            layout: layout,
            quran: widget.quran,
            page: widget.page,
            theme: widget.look.theme,
            selected: widget.selected,
            playing: widget.playing,
            annotations: widget.annotations,
            memorise: widget.memorise,
            revealed: widget.revealed,
            onAyahLongPress: widget.onAyahLongPress,
            onAyahTap: widget.onAyahTap,
            onNoteTap: widget.onNoteTap,
            onBackgroundTap: widget.onBackgroundTap,
          );
        } else if (layout == null || _waited || failed) {
          child = FittedMushafPage(
            key: const ValueKey('text'),
            page: MushafPage(
              quran: widget.quran,
              page: widget.page,
              theme: widget.look.theme,
              fontSize: widget.look.fontSize,
              comfortable: widget.look.comfortable,
              locale: widget.look.locale,
              selected: widget.selected,
              playing: widget.playing,
              annotations: widget.annotations,
              memorise: widget.memorise,
              revealed: widget.revealed,
              onAyahLongPress: widget.onAyahLongPress,
              onAyahTap: widget.onAyahTap,
              onNoteTap: widget.onNoteTap,
            ),
          );
        } else {
          child = const SizedBox.expand(key: ValueKey('wait'));
        }
        return AnimatedSwitcher(
          duration: YqMotion.fast,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
          child: child,
        );
      },
    );
  }
}

/// Chrome glass fill over the night page: lapis and muted labels keep AA contrast on it.
const _nightGlass = 0.86;

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.visible,
    required this.night,
    required this.marked,
    required this.onExit,
    required this.onSettings,
    required this.onLock,
    required this.onMark,
    required this.onTitle,
    required this.title,
    required this.subtitle,
  });

  final bool visible;

  /// Night page: the glass is filled more so the labels stay readable over the dark page.
  final bool night;
  final bool marked;
  final VoidCallback onExit;
  final VoidCallback onSettings;
  final VoidCallback onLock;
  final VoidCallback onMark;
  final VoidCallback onTitle;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AnimatedPositioned(
      duration: YqMotion.base,
      curve: YqMotion.ease,
      top: visible ? 0 : -140,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          bottom: false,
          child: _ChromeWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(YqSpace.l, YqSpace.s, YqSpace.l, 0),
              child: Row(
                children: [
                  GlassIconButton(
                    opacity: night ? _nightGlass : 0.58,
                    tooltip: t.readerExit,
                    onPressed: onExit,
                    icon: const Icon(Icons.chevron_left_rounded, color: YqColors.ink),
                  ),
                  const SizedBox(width: YqSpace.s),
                  // The title is the way to move around: tap → surah / juz / page / ayah.
                  Expanded(
                    child: GlassTap(
                      onTap: onTitle,
                      semanticLabel: '$title، $subtitle. ${t.readerOpenJump}',
                      child: LiquidGlass(
                        radius: YqRadii.pill,
                        highlight: false,
                        opacity: night ? _nightGlass : 0.58,
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Column(
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(subtitle, style: const TextStyle(fontSize: 11, color: YqColors.muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.expand_more_rounded, size: 18, color: YqColors.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: YqSpace.s),
                  GlassIconButton(
                    opacity: night ? _nightGlass : 0.58,
                    tooltip: marked ? t.readerUnmarkPage : t.readerMarkPage,
                    onPressed: onMark,
                    icon: YqIcon(YqIcons.bookmark, size: 20, tone: marked ? YqIconTone.gold : YqIconTone.idle),
                  ),
                  const SizedBox(width: YqSpace.s),
                  GlassIconButton(
                    opacity: night ? _nightGlass : 0.58,
                    tooltip: t.readerLock,
                    onPressed: onLock,
                    icon: const Icon(Icons.lock_outline_rounded, size: 20, color: YqColors.muted),
                  ),
                  const SizedBox(width: YqSpace.s),
                  GlassIconButton(
                    opacity: night ? _nightGlass : 0.58,
                    tooltip: t.readerSettings,
                    onPressed: onSettings,
                    icon: const YqIcon(YqIcons.settings, size: 20, tone: YqIconTone.idle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomChrome extends ConsumerWidget {
  const _BottomChrome({
    required this.visible,
    required this.night,
    required this.page,
    required this.quran,
    required this.memorise,
    required this.onJump,
    required this.onMemorise,
  });
  final bool visible;
  final bool night;
  final int page;
  final QuranData quran;
  final bool memorise;
  final ValueChanged<int> onJump;
  final VoidCallback onMemorise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final goal = ref.watch(settingsProvider.select((s) => s.wirdGoalPages));
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final config = ref.watch(remoteConfigProvider);
    final s = ref.watch(settingsProvider);
    final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)()));
    final read = wird?.date == today ? wird!.count : 0;
    final khatma = ref.watch(khatmaProvider).valueOrNull;
    final surah = quran.firstOfPage(page).surah;
    return AnimatedPositioned(
      duration: YqMotion.base,
      curve: YqMotion.ease,
      bottom: visible ? 0 : -220,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          top: false,
          child: _ChromeWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(YqSpace.l, 0, YqSpace.l, YqSpace.s),
              child: LiquidGlass(
                radius: YqRadii.card,
                opacity: night ? _nightGlass : 0.58,
                padding: const EdgeInsets.fromLTRB(YqSpace.l, YqSpace.m, YqSpace.l, YqSpace.s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                khatma != null && !khatma.finished
                                    ? '${t.readerWird} · ${t.pagesOf(read.clamp(0, goal), goal)} · ${t.quranKhatma} ${YqFormat.number((khatma.progress * 100).round())}%'
                                    : '${t.readerWird} · ${t.pagesOf(read.clamp(0, goal), goal)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              YqProgressLine(value: goal == 0 ? 0 : read / goal),
                            ],
                          ),
                        ),
                        const SizedBox(width: YqSpace.s),
                        YqButton.text(
                          label: t.readerMemorise,
                          icon: Icon(Icons.visibility_off_outlined, size: 18, color: memorise ? YqColors.goldText : YqColors.lapis),
                          onPressed: onMemorise,
                        ),
                        if (config.isOn(Flags.listen))
                          YqButton.text(
                            label: t.readerListen,
                            icon: const YqIcon(YqIcons.listen, size: 18),
                            onPressed: () => context.push('/quran/listen/$surah'),
                          ),
                        if (config.isOn(Flags.recite))
                          YqButton.text(
                            label: t.readerRecite,
                            icon: const YqIcon(YqIcons.azkar, size: 18),
                            onPressed: () => context.push('/quran/recite/$surah'),
                          ),
                      ],
                    ),
                    Semantics(
                      label: t.readerSlider,
                      value: t.quranPageOf(page),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Slider(
                          min: 1,
                          max: QuranData.pageCount.toDouble(),
                          divisions: QuranData.pageCount - 1,
                          value: page.toDouble(),
                          label: YqFormat.number(page),
                          activeColor: YqColors.lapis,
                          inactiveColor: YqColors.line,
                          onChanged: (v) => onJump(v.round()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reader chrome keeps a comfortable width on tablets and in landscape, centred over the pages.
class _ChromeWidth extends StatelessWidget {
  const _ChromeWidth({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child),
      );
}

/// While memorising: what's hidden, show / hide all, and the way out.
class _MemoriseBanner extends StatelessWidget {
  const _MemoriseBanner({required this.mode, required this.onShowAll, required this.onHideAll, required this.onExit});
  final MemoriseMode mode;
  final VoidCallback onShowAll;
  final VoidCallback onHideAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(YqSpace.l, 0, YqSpace.l, YqSpace.s),
          child: LiquidGlass(
            tone: GlassTone.gold,
            radius: YqRadii.pill,
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.visibility_off_outlined, size: 18, color: YqColors.goldText),
                const SizedBox(width: YqSpace.s),
                Expanded(
                  child: Text(
                    t.memoriseBanner(mode == MemoriseMode.ayat ? t.memoriseAyat : t.memoriseWords),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: onShowAll, child: Text(t.memoriseShowAll)),
                TextButton(onPressed: onHideAll, child: Text(t.memoriseHideAll)),
                IconButton(tooltip: t.memoriseExit, onPressed: onExit, icon: const Icon(Icons.close_rounded, color: YqColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Touch lock: ignores taps/swipes; a 1.2 s hold unlocks (spec §5.11).
class _LockOverlay extends StatefulWidget {
  const _LockOverlay({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.mediumImpact();
        widget.onUnlock();
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _hold.forward(from: 0),
        onLongPressEnd: (_) {
          if (!_hold.isCompleted) _hold.reverse();
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: YqSpace.xl),
              child: LiquidGlass(
                radius: YqRadii.pill,
                padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
                child: AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          value: _hold.value,
                          strokeWidth: 2.4,
                          color: YqColors.lapis,
                          backgroundColor: YqColors.line,
                        ),
                      ),
                      const SizedBox(width: YqSpace.s),
                      Text(_hold.value > 0 ? t.readerKeepHolding : t.readerLocked, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstOpenHint extends StatelessWidget {
  const _FirstOpenHint({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x590A1530),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(YqSpace.xxl),
            child: LiquidGlass(
              padding: const EdgeInsets.all(YqSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const YqIcon(YqIcons.quran, size: 36),
                  const SizedBox(height: YqSpace.m),
                  Text(t.readerHint, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: YqSpace.l),
                  YqButton(label: t.readerGotIt, onPressed: onDismiss),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
