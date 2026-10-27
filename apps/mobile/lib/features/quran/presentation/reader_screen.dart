import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import '../domain/quran_data.dart';
import '../domain/reading_stats.dart';
import '../domain/wird.dart';
import 'ayah_sheet.dart';
import 'jump_sheet.dart';
import 'mushaf_page.dart';
import 'note_sheet.dart';
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
  PageController? _pages;
  bool? _spread;
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
    _pages?.dispose();
    _c.read(deviceServicesProvider).keepAwake(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Pages on screen for [page] (both of a spread).
  List<int> _visible(int page) {
    if (_spread != true) return [page];
    final first = page.isOdd ? page : page - 1;
    return [first, if (first < QuranData.pageCount) first + 1];
  }

  int _indexOf(int page, bool spread) => spread ? (page - 1) ~/ 2 : page - 1;

  /// One controller per layout; switching layout (rotation) keeps the current page.
  PageController _controllerFor(bool spread) {
    if (_spread != spread || _pages == null) {
      _pages?.dispose();
      _pages = PageController(initialPage: _indexOf(_page, spread));
      _spread = spread;
    }
    return _pages!;
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
    final p = _pages;
    if (p == null) return;
    setState(() => _setFocus(focus));
    p.jumpToPage(_indexOf(page, _spread == true));
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
    final annotations = ref.watch(annotationsProvider).valueOrNull ?? Annotations.empty;
    final colors = MushafColors.of(look.theme);
    final night = look.theme == MushafTheme.night;
    // Highlight the ayah the player is on while recitation is playing (spec §5.13).
    final playing = ref.watch(listenControllerProvider.select((l) => l.playing && l.sampleOf == null ? l.ref : null));
    final spread = spreadLayout(MediaQuery.sizeOf(context));
    final controller = _controllerFor(spread);

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
                  page: page,
                  look: look,
                  selected: _selected ?? _focus,
                  focus: _focus,
                  playing: playing,
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
                // Pages: in RTL, dragging left → right turns to the next page (mushaf order) — also in English.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _locked ? null : _toggleChrome,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: PageView.builder(
                      controller: controller,
                      physics: _locked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                      itemCount: spread ? (QuranData.pageCount / 2).ceil() : QuranData.pageCount,
                      allowImplicitScrolling: true, // keeps neighbours built for smooth turns
                      onPageChanged: (i) {
                        _leavePage();
                        setState(() {
                          _page = spread ? i * 2 + 1 : i + 1;
                          _selected = null;
                          _revealed.clear();
                        });
                        _onPageShown(_page);
                      },
                      itemBuilder: (context, i) {
                        final child = spread
                            ? Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  Expanded(child: frame(i * 2 + 1)),
                                  Container(width: 1, color: colors.frame),
                                  Expanded(child: i * 2 + 2 <= QuranData.pageCount ? frame(i * 2 + 2) : ColoredBox(color: colors.page)),
                                ],
                              )
                            : frame(i + 1);
                        return look0.turn == PageTurn.book
                            ? _BookTurn(controller: controller, index: i, shade: colors.ink, child: child)
                            : child;
                      },
                    ),
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

/// A book-like turn: the page lifts from the spine with a little perspective and a soft shade as
/// it moves; at rest it is flat. Transform only — the text inside is not re-laid out.
class _BookTurn extends StatelessWidget {
  const _BookTurn({required this.controller, required this.index, required this.shade, required this.child});
  final PageController controller;
  final int index;
  final Color shade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return child;
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(child: child),
      builder: (context, page) {
        final pos = controller.hasClients && controller.position.haveDimensions ? (controller.page ?? index.toDouble()) : index.toDouble();
        final delta = (pos - index).clamp(-1.0, 1.0);
        if (delta.abs() < 0.001) return page!;
        // RTL page order: a positive delta means this page is turning away to the right.
        final angle = delta * math.pi / 9;
        return Transform(
          alignment: delta > 0 ? Alignment.centerRight : Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY(-angle),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              page!,
              IgnorePointer(child: ColoredBox(color: shade.withAlpha((delta.abs() * 40).round()), child: const SizedBox.expand())),
            ],
          ),
        );
      },
    );
  }
}

class _PageFrame extends StatefulWidget {
  const _PageFrame({
    required this.quran,
    required this.page,
    required this.look,
    required this.annotations,
    required this.memorise,
    required this.revealed,
    this.selected,
    this.focus,
    this.playing,
    this.onAyahLongPress,
    this.onAyahTap,
    this.onNoteTap,
  });
  final QuranData quran;
  final AyahRef? playing;
  final int page;
  final _Look look;
  final AyahRef? selected;
  final AyahRef? focus;
  final Annotations annotations;
  final MemoriseMode memorise;
  final Set<AyahRef> revealed;
  final ValueChanged<AyahRef>? onAyahLongPress;
  final ValueChanged<AyahRef>? onAyahTap;
  final ValueChanged<AyahRef>? onNoteTap;

  @override
  State<_PageFrame> createState() => _PageFrameState();
}

class _PageFrameState extends State<_PageFrame> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _bringFocusIntoView();
  }

  @override
  void didUpdateWidget(_PageFrame old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) _bringFocusIntoView();
  }

  /// Long pages at large sizes scroll: put the focused ayah roughly where its text sits.
  void _bringFocusIntoView() {
    final f = widget.focus;
    if (f == null || widget.quran.pageOf(f) != widget.page) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ayat = [for (final s in widget.quran.page(widget.page)) ...s.ayat];
      final total = ayat.fold<int>(0, (n, a) => n + a.text.length);
      var before = 0;
      for (final a in ayat) {
        if (a.ref == f) break;
        before += a.text.length;
      }
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0 || total == 0) return;
      _scroll.animateTo((before / total * max).clamp(0, max), duration: YqMotion.base, curve: YqMotion.ease);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final look = widget.look;
    final quran = widget.quran;
    final colors = MushafColors.of(look.theme);
    final first = quran.firstOfPage(widget.page);
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: colors.page,
      child: Column(
        children: [
          SizedBox(height: pad.top + 8),
          // Page header (always visible, quiet): surah · juz/hizb.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl),
            child: Row(
              children: [
                Text(quran.surah(first.surah).nameAr, style: TextStyle(fontSize: 12, color: colors.muted)),
                const Spacer(),
                Text(t.quranJuzHizb(quran.juzOf(first), quran.hizbOf(first)), style: TextStyle(fontSize: 12, color: colors.muted)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(YqSpace.xl, YqSpace.s, YqSpace.xl, YqSpace.l),
              child: MushafPage(
                quran: quran,
                page: widget.page,
                theme: look.theme,
                fontSize: look.fontSize,
                comfortable: look.comfortable,
                locale: look.locale,
                selected: widget.selected,
                playing: widget.playing,
                annotations: widget.annotations,
                memorise: widget.memorise,
                revealed: widget.revealed,
                onAyahLongPress: widget.onAyahLongPress,
                onAyahTap: widget.onAyahTap,
                onNoteTap: widget.onNoteTap,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: pad.bottom + 10),
            child: Text(
              t.quranPageOf(widget.page),
              style: TextStyle(fontSize: 12, color: colors.muted, fontFamily: 'Jost', fontFamilyFallback: const ['Tajawal']),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.visible,
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
                    tooltip: marked ? t.readerUnmarkPage : t.readerMarkPage,
                    onPressed: onMark,
                    icon: YqIcon(YqIcons.bookmark, size: 20, tone: marked ? YqIconTone.gold : YqIconTone.idle),
                  ),
                  const SizedBox(width: YqSpace.s),
                  GlassIconButton(
                    tooltip: t.readerLock,
                    onPressed: onLock,
                    icon: const Icon(Icons.lock_outline_rounded, size: 20, color: YqColors.muted),
                  ),
                  const SizedBox(width: YqSpace.s),
                  GlassIconButton(
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
    required this.page,
    required this.quran,
    required this.memorise,
    required this.onJump,
    required this.onMemorise,
  });
  final bool visible;
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
