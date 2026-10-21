import 'dart:async';

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
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/reading_repository.dart';
import '../domain/quran_data.dart';
import '../domain/wird.dart';
import 'ayah_sheet.dart';
import '../../listen/presentation/listen_controller.dart';
import 'mushaf_page.dart';
import 'quran_index_screen.dart';

final todayWirdProvider = FutureProvider.autoDispose((ref) => ref.watch(readingRepositoryProvider).wird());

/// `09 · Reading mode` (spec §5.11) — full screen, offline, the heart of the app.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.initialPage});
  final int initialPage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialPage.clamp(1, QuranData.pageCount) - 1);
  late int _page = widget.initialPage.clamp(1, QuranData.pageCount);
  bool _chrome = true;
  bool _locked = false;
  bool _hint = false;
  AyahRef? _selected;
  Timer? _hideTimer;
  Timer? _wirdTimer;
  DateTime _pageShownAt = DateTime.now();
  bool _pageMarked = false;
  // Wird counting outlives the widget (the last page counts on exit), so it reads the container, not `ref`.
  late final ProviderContainer _c;

  @override
  void initState() {
    super.initState();
    _c = ProviderScope.containerOf(context, listen: false);
    final s = ref.read(settingsProvider);
    _hint = !s.readerHintSeen;
    if (s.keepAwake) ref.read(deviceServicesProvider).keepAwake(true);
    _onPageShown(_page);
    _scheduleHide();
  }

  @override
  void dispose() {
    _countPage(_page); // the last page counts too if it was read long enough
    _hideTimer?.cancel();
    _wirdTimer?.cancel();
    _pages.dispose();
    _c.read(deviceServicesProvider).keepAwake(false);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_hint) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  Future<void> _onPageShown(int page) async {
    _pageShownAt = DateTime.now();
    _wirdTimer?.cancel();
    // Counting at 20 s while still on the page — the user may keep reading the same page.
    _wirdTimer = Timer(const Duration(seconds: WirdRules.minSecondsPerPage), () => _countPage(page));
    final q = await _c.read(quranDataProvider.future);
    final reading = _c.read(readingRepositoryProvider);
    await reading.saveLastRead(page, q.firstOfPage(page).surah, _c.read(clockProvider)());
    final marks = await reading.bookmarks();
    if (mounted) setState(() => _pageMarked = marks.any((b) => b.kind == BookmarkKind.page && b.page == page));
  }

  /// Wird: page counted after ≥ 20 s visible; reaching the goal ticks the challenge task once a day.
  Future<void> _countPage(int page) async {
    final s = _c.read(settingsProvider);
    final now = _c.read(clockProvider)();
    final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, now));
    final reading = _c.read(readingRepositoryProvider);
    final r = WirdRules.read(
      await reading.wird(),
      today: today,
      page: page,
      visibleFor: DateTime.now().difference(_pageShownAt),
      goalPages: s.wirdGoalPages,
    );
    if (!r.counted) return;
    await reading.saveWird(r.day);
    _c.invalidate(todayWirdProvider);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final data = ref.watch(quranDataProvider);
    final colors = MushafColors.of(s.mushafTheme);
    final night = s.mushafTheme == MushafTheme.night;
    // Highlight the ayah the player is on while recitation is playing (spec §5.13).
    final playing = ref.watch(listenControllerProvider.select((l) => l.playing && l.sampleOf == null ? l.ref : null));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: night ? YqColors.nightBg : colors.page,
        body: data.when(
          loading: () => const Center(child: YqSkeleton(child: YqSkeletonBox(height: 400, width: 300, radius: YqRadii.card))),
          error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(quranDataProvider)),
          data: (q) {
            final first = q.firstOfPage(_page);
            return Stack(
              children: [
                // Pages: in RTL, dragging left → right turns to the next page (mushaf order) — also in English.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _locked ? null : _toggleChrome,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: PageView.builder(
                      controller: _pages,
                      physics: _locked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                      itemCount: QuranData.pageCount,
                      allowImplicitScrolling: true, // keeps neighbours built for smooth turns
                      onPageChanged: (i) {
                        _countPage(_page);
                        setState(() {
                          _page = i + 1;
                          _selected = null;
                        });
                        _onPageShown(_page);
                      },
                      itemBuilder: (context, i) => _PageFrame(
                        quran: q,
                        page: i + 1,
                        settings: s,
                        selected: _selected,
                        playing: playing,
                        onAyahLongPress: _locked
                            ? null
                            : (ref0) async {
                                HapticFeedback.mediumImpact();
                                setState(() => _selected = ref0);
                                await showAyahSheet(context, quran: q, ref: ref0);
                                if (mounted) setState(() => _selected = null);
                              },
                      ),
                    ),
                  ),
                ),
                if (!_locked) ...[
                  _TopChrome(
                    visible: _chrome,
                    marked: _pageMarked,
                    onExit: () => context.canPop() ? context.pop() : context.go('/quran'),
                    onSettings: () => showReaderSettings(context),
                    onLock: () => setState(() {
                      _locked = true;
                      _chrome = false;
                    }),
                    onMark: _togglePageMark,
                    title: q.surah(first.surah).name(s.locale),
                    subtitle: t.quranJuzHizb(q.juzOf(first), q.hizbOf(first)),
                  ),
                  _BottomChrome(visible: _chrome, page: _page, quran: q, onJump: (p) => _pages.jumpToPage(p - 1)),
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

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.quran, required this.page, required this.settings, this.selected, this.playing, this.onAyahLongPress});
  final QuranData quran;
  final AyahRef? playing;
  final int page;
  final AppSettings settings;
  final AyahRef? selected;
  final ValueChanged<AyahRef>? onAyahLongPress;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = MushafColors.of(settings.mushafTheme);
    final first = quran.firstOfPage(page);
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
              padding: const EdgeInsets.fromLTRB(YqSpace.xl, YqSpace.s, YqSpace.xl, YqSpace.l),
              child: MushafPage(
                quran: quran,
                page: page,
                theme: settings.mushafTheme,
                fontSize: settings.quranFontSize,
                comfortable: settings.comfortableSpacing,
                locale: settings.locale,
                selected: selected,
                playing: playing,
                onAyahLongPress: onAyahLongPress,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: pad.bottom + 10),
            child: Text(
              t.quranPageOf(page),
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
    required this.title,
    required this.subtitle,
  });

  final bool visible;
  final bool marked;
  final VoidCallback onExit;
  final VoidCallback onSettings;
  final VoidCallback onLock;
  final VoidCallback onMark;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(YqSpace.l, YqSpace.s, YqSpace.l, 0),
            child: Row(
              children: [
                GlassIconButton(
                  tooltip: t.readerExit,
                  onPressed: onExit,
                  icon: Icon(rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, color: YqColors.ink),
                ),
                const SizedBox(width: YqSpace.s),
                Expanded(
                  child: LiquidGlass(
                    radius: YqRadii.pill,
                    highlight: false,
                    padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: 6),
                    child: Column(
                      children: [
                        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: const TextStyle(fontSize: 11, color: YqColors.muted)),
                      ],
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
    );
  }
}

class _BottomChrome extends ConsumerWidget {
  const _BottomChrome({required this.visible, required this.page, required this.quran, required this.onJump});
  final bool visible;
  final int page;
  final QuranData quran;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final goal = ref.watch(settingsProvider.select((s) => s.wirdGoalPages));
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final config = ref.watch(remoteConfigProvider);
    final s = ref.watch(settingsProvider);
    final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)()));
    final read = wird?.date == today ? wird!.count : 0;
    final surah = quran.firstOfPage(page).surah;
    return AnimatedPositioned(
      duration: YqMotion.base,
      curve: YqMotion.ease,
      bottom: visible ? 0 : -200,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          top: false,
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
                              '${t.readerWird} · ${t.pagesOf(read.clamp(0, goal), goal)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            YqProgressLine(value: goal == 0 ? 0 : read / goal),
                          ],
                        ),
                      ),
                      if (config.isOn(Flags.listen)) ...[
                        const SizedBox(width: YqSpace.m),
                        YqButton.text(
                          label: t.readerListen,
                          icon: const YqIcon(YqIcons.listen, size: 18),
                          onPressed: () => context.push('/quran/listen/$surah'),
                        ),
                      ],
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
