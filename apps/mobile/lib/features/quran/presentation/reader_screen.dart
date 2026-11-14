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
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_skeleton_mushaf.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../hifz/domain/grade_suggestion.dart';
import '../../hifz/domain/hifz_guide.dart';
import '../../hifz/presentation/grade_sheet.dart';
import '../../hifz/presentation/hifz_controller.dart';
import '../../listen/presentation/listen_controller.dart';
import '../../listen/presentation/mini_player.dart';
import '../../listen/presentation/player_sheet.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../hifz/presentation/voice_rehearsal.dart';
import '../../recite/domain/recite_progress.dart';
import '../../recite/presentation/asr_model_sheet.dart';
import '../../recite/presentation/recite_available.dart';
import '../../recite/presentation/recite_controller.dart';
import '../../recite/presentation/recite_end_card.dart';
import '../../recite/presentation/recite_overlay.dart';
import '../data/reading_repository.dart';
import '../domain/annotations.dart';
import '../domain/mushaf_layout.dart';
import '../domain/passage.dart';
import '../domain/quran_data.dart';
import '../domain/quran_session.dart';
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
import 'session/active_session.dart';
import 'session/follow_audio.dart';
import 'session/listen_strip.dart';
import 'session/memorise_strip.dart';
import 'session/mode_dock.dart';
import 'session/passage_picker_sheet.dart';
import 'session/quran_entry.dart';
import 'session/quran_session_controller.dart';
import 'session/read_strip.dart';
import 'session/recite_strip.dart';
import 'session/session_end_card.dart';
import 'session/session_line.dart';

export 'session/read_strip.dart' show todayWirdProvider;

/// Two mushaf pages side by side when the screen is wide (tablet, or a phone in landscape).
bool spreadLayout(Size size) => size.width > size.height && size.width >= 700;

/// `09 · Reading mode` (spec §5.11) — «صفحة واحدة»: the printed page is the only Quran surface.
/// Reading, listening, memorising and reciting are layers over it ([QuranModeDock]); switching
/// layers never pushes a route. Full screen, offline, the heart of the app.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.initialPage,
    this.focus,
    this.mode = QuranMode.read,
    this.passage,
    this.session,
    this.portion,
    this.openPlayer = false,
  });
  final int initialPage;

  /// An ayah to light briefly and bring into view (search, bookmarks, «انتقل إلى»).
  final AyahRef? focus;

  /// The layer to open on (`?mode=`).
  final QuranMode mode;

  /// The passage a layer works on (`?surah=&from=&to=`).
  final Passage? passage;

  /// A guided session to start or resume (`?session=wird|khatma|hifz|review|resume`).
  final String? session;

  /// The hifz portion a review session grades (`?portion=`).
  final String? portion;

  /// Open the full player at once (`?player=open`, from «استماع» entries).
  final bool openPlayer;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
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
  final _wirdClock = WirdClock();
  Future<void> _lastSave = Future.value();
  bool _pageMarked = false;

  /// Following the recitation: a page change made by the reader itself is not a manual look-ahead.
  late final _guard = FollowGuard(onEnd: _refresh);
  bool _following = false;

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Wird counting outlives the widget (the last page counts on exit), so it reads the container, not `ref`.
  late final ProviderContainer _c;

  QuranSessionController get _layers => ref.read(quranSessionControllerProvider.notifier);
  ActiveSessionController get _sessions => ref.read(activeSessionProvider.notifier);

  /// The session's end card was shown (once per reader).
  bool _endShown = false;

  /// Echo practice running («تكرار ×10» with the recitation).
  bool _echoing = false;

  /// Leaving is allowed although the guided test is not graded (the grade sheet was offered).
  bool _allowPop = false;

  /// The session this reader began or resumed: closing lets go of that one only.
  String? _ownSession;

  /// This reader started its session just now (not a resume): taking over another surah's
  /// recitation asks first.
  bool _freshSession = false;

  /// The end card's «التالي» replaced this reader with the next step's: it no longer reacts to the
  /// shared layers, session or recitation (they are the next reader's now).
  bool _handedOff = false;

  /// The route's `?surah=&from=&to=`, checked against the mushaf (null until it has loaded, or when
  /// it names no ayah of that surah).
  Passage? _routePassage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c = ProviderScope.containerOf(context, listen: false);
    final s = ref.read(settingsProvider);
    _hint = !s.readerHintSeen;
    if (s.keepAwake) ref.read(deviceServicesProvider).keepAwake(true);
    _setFocus(widget.focus);
    _onPageShown(_page);
    _scheduleHide();
    // Providers can't change while the tree builds: the layers are set right after this frame.
    Future.microtask(() async {
      if (!mounted) return;
      // The app-wide mini player steps aside while a reader is open.
      ref.read(readerPresenceProvider.notifier).enter();
      final q0 = ref.read(quranDataProvider).valueOrNull;
      _routePassage = q0 == null ? null : checkedPassage(q0, widget.passage);
      _layers.init(passage: _routePassage);
      if (q0 == null && widget.passage != null) {
        final q = await ref.read(quranDataProvider.future).then<QuranData?>((q) => q, onError: (Object _) => null);
        if (!mounted || q == null) return;
        _routePassage = checkedPassage(q, widget.passage);
        _layers.setPassage(_routePassage);
      }
      final session = await _openSession();
      if (!mounted) return;
      if (session != null) {
        await _applySession(session);
      } else if (widget.mode != QuranMode.read) {
        await _setMode(widget.mode, ask: false);
      }
      if (widget.openPlayer && mounted) _openPlayer();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A full-screen page pushed over the reader takes it offstage (tickers off): the wird clock
    // stops. A sheet (popup route) leaves the page on screen, so reading time keeps counting.
    _setCovered(!TickerMode.valuesOf(context).enabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only while the app is in the foreground with the screen on.
    _wirdClock.foreground = state == AppLifecycleState.resumed;
    _syncWirdClock();
  }

  void _setCovered(bool covered) {
    if (_wirdClock.covered == covered) return;
    _wirdClock.covered = covered;
    _syncWirdClock();
  }

  /// Starts or stops the visible-time clock; the page counts once it has been visible 20 s.
  void _syncWirdClock() {
    final page = _page;
    if (!_wirdClock.sync()) {
      _wirdTimer?.cancel();
      return;
    }
    _wirdTimer?.cancel();
    final left = const Duration(seconds: WirdRules.minSecondsPerPage) - _wirdClock.visible;
    if (left <= Duration.zero) return;
    // Counting at 20 s while still on the page — the user may keep reading the same page.
    _wirdTimer = Timer(left, () {
      for (final p in _visible(page)) {
        _countPage(p, const Duration(seconds: WirdRules.minSecondsPerPage));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The last page counts too if it was read long enough. Home, the Quran index and the khatma
    // orb stay mounted under the tabs, so «continue reading» and the week's minutes reload once the
    // last writes land.
    Future.wait([_leavePage(), _lastSave]).whenComplete(() {
      _c
        ..invalidate(lastReadProvider)
        ..invalidate(readingStatsProvider);
    }).ignore();
    _hideTimer?.cancel();
    _wirdTimer?.cancel();
    _focusTimer?.cancel();
    _guard.clear();
    _pager.dispose();
    final presence = _c.read(readerPresenceProvider.notifier);
    Future.microtask(presence.leave);
    // The session stays saved for «أكمل جلستك»; it is simply no longer on screen.
    final sessions = _c.read(activeSessionProvider.notifier);
    final mine = _ownSession;
    Future.microtask(() => sessions.detach(mine));
    // Echo practice is this reader's: closing it stops the ayah it was playing (and its wait).
    if (_echoing) {
      _echoing = false;
      _c.read(listenControllerProvider.notifier).pause().ignore();
    }
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
    final manual = !_following;
    _following = false;
    _leavePage().ignore();
    setState(() {
      _page = page;
      _selected = null;
    });
    _layers.pageChanged();
    _sessions.update((s) => s.withPage(page));
    if (manual && _isFollowing) {
      // A look ahead while listening: following waits 8 s, with the way back on a chip.
      _guard.hold();
    }
    _onPageShown(page);
  }

  bool get _isFollowing {
    final l = ref.read(listenControllerProvider);
    return ref.read(quranSessionControllerProvider).mode == QuranMode.listen && l.playing && l.sampleOf == null;
  }

  /// ±2 neighbours once the page has settled (the open pages ask for their own fonts, ahead of these).
  void _warmFonts(int page) {
    final layout = _c.read(mushafLayoutProvider).valueOrNull;
    if (layout == null) return;
    final fonts = _c.read(mushafFontsProvider);
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
    _wirdClock.restart();
    _warmFonts(page);
    _syncWirdClock();
    final q = await _c.read(quranDataProvider.future);
    if (!mounted) return; // closed before the mushaf text arrived: nothing was read here
    final reading = _c.read(readingRepositoryProvider);
    await (_lastSave = reading.saveLastRead(page, q.firstOfPage(page).surah, _c.read(clockProvider)()));
    final marks = await reading.bookmarks();
    if (mounted) setState(() => _pageMarked = marks.any((b) => b.kind == BookmarkKind.page && _visible(page).contains(b.page)));
  }

  /// Leaving the current page: its pages may count, and the time goes into the reading stats.
  Future<void> _leavePage() {
    final shown = _wirdClock.visible;
    return Future.wait([
      for (final p in _visible(_page)) _countPage(p, shown),
      _addSeconds(shown.inSeconds.clamp(0, ReadingStats.maxSecondsPerView)),
    ]);
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
        // The daily reminder stops speaking of the khatma portion.
        _c.read(remindersControllerProvider.notifier).replan().ignore();
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

  /// `?session=`: resumes the saved session (`resume`, or the same kind on the same passage when it is
  /// still today's), else starts one of that kind here. Null: free reading without a session.
  Future<QuranSession?> _openSession() async {
    final raw = widget.session;
    if (raw == null) return null;
    final saved = await loadValidSession(ref.read);
    if (!mounted) return null;
    if (raw == 'resume') {
      if (saved != null) await _begin(saved);
      return saved;
    }
    final kind = QuranSessionKind.tryParse(raw);
    if (kind == null) return null;
    if (saved != null && saved.kind == kind && (_routePassage == null || saved.passage == _routePassage)) {
      await _begin(saved);
      return saved;
    }
    final q = await ref.read(quranDataProvider.future);
    final passage = _routePassage ?? await _sessionPassage(q, kind);
    final planKey = await sessionPlanKey(ref.read, kind);
    final goal = await sessionGoal(ref.read, kind);
    if (!mounted) return null;
    final s = QuranSession.start(
      kind,
      passage,
      now: ref.read(clockProvider)(),
      day: sessionDay(ref.read, kind),
      mode: widget.mode,
      page: _page,
      planKey: planKey,
      portion: switch (kind) {
        QuranSessionKind.review => widget.portion,
        QuranSessionKind.hifz => passage.toString(),
        _ => null,
      },
      goal: goal,
    );
    _freshSession = true;
    await _begin(s);
    return s;
  }

  /// Puts [s] in the reader, as this reader's own.
  Future<void> _begin(QuranSession s) {
    _ownSession = s.id;
    return _sessions.begin(s);
  }

  /// What a session started without `surah/from/to` covers: the khatma portion from this page, else
  /// the page's own passage.
  Future<Passage> _sessionPassage(QuranData q, QuranSessionKind kind) async {
    if (kind == QuranSessionKind.khatma) {
      final k = await ref.read(readingRepositoryProvider).khatma();
      if (k != null && !k.finished) {
        final today = sessionToday(ref.read);
        final left = k.dailyTarget(today, readToday: k.readOn(today)) - k.readOn(today);
        return Passage.ofKhatma(q, _page, _page + khatmaSessionPages(left) - 1);
      }
    }
    return Passage.ofPage(q, _page);
  }

  /// Puts a (resumed) session on screen: its page, its passage, its layer.
  Future<void> _applySession(QuranSession s) async {
    // Reading sessions start somewhere; only memorising and the guided ones work on their passage.
    if (s.kind == QuranSessionKind.free || s.kind.guided) _layers.setPassage(s.passage);
    final page = s.page;
    if (widget.session == 'resume' && page != null && page != _page) _goTo(page);
    if (s.stage == SessionStage.reading) {
      var mode = widget.mode != QuranMode.read ? widget.mode : s.mode;
      // A session starting here with the recitation (the khatma's «استمع إلى الحصّة») asks before
      // it replaces another surah's; kept, the portion is read instead. A resume never asks.
      if (mode == QuranMode.listen && _freshSession) {
        final q = ref.read(quranDataProvider).valueOrNull;
        if (q != null && playingOtherSurah(ref.read(listenControllerProvider), q.firstOfPage(_page).surah)) {
          if (!await confirmReplacePlayback(context)) mode = QuranMode.read;
          if (!mounted) return;
        }
      }
      if (mode != QuranMode.read) await _setMode(mode, ask: false);
      if (mode == QuranMode.memorise && s.reveals.isNotEmpty) _layers.revealAll(s.reveals);
    } else if (s.kind.guided) {
      await _enterStage(s, fresh: _freshSession);
    }
  }

  /// Sets the page up for a guided stage: «استماع ×3» plays the passage three times; «تكرار ×10»
  /// shows it with the «كرّرت» counter (and echo); «اختبار» hides it — the microphone when this build
  /// can recite, else every other word with a tap to reveal.
  ///
  /// [fresh]: the session was started just now — another surah's recitation is replaced only after
  /// «استبدال التشغيل الحالي؟»; kept, the stage waits with «تخطَّ إلى التكرار».
  Future<void> _enterStage(QuranSession s, {bool fresh = false}) async {
    final listen = ref.read(listenControllerProvider.notifier);
    switch (s.stage) {
      case SessionStage.listen:
        // No listening in this build: straight to repeating.
        if (!ref.read(quranModesProvider).contains(QuranMode.listen)) return _skipToRepeat();
        _layers.setMode(QuranMode.listen);
        _sessions.update((x) => x.withMode(QuranMode.listen));
        if (fresh && playingOtherSurah(ref.read(listenControllerProvider), s.passage.surah)) {
          final replace = await confirmReplacePlayback(context);
          if (!mounted) return;
          if (!replace) {
            _keptPlayback = true;
            break;
          }
        }
        _keptPlayback = false;
        await listen.playPassage(s.passage, times: HifzGuide.listenTimes);
      case SessionStage.repeat:
        await listen.pause();
        if (!mounted) return;
        _layers.setMode(QuranMode.memorise);
        _layers.setMemorise(MemoriseMode.ayat);
        _layers.revealAll(s.passage.range);
        _layers.setRepeats(s.round);
        _sessions.update((x) => x.withMode(QuranMode.memorise));
        // With the model on the phone (and the microphone allowed before), each full recitation
        // counts by itself; «كرّرت» stays as fallback and override.
        if (ref.read(reciteReadyProvider) && await ref.read(reciteControllerProvider.notifier).rationaleSeen()) {
          await _voiceRepeats(true);
        }
      case SessionStage.test:
        _echoing = false;
        await ref.read(voiceRehearsalProvider.notifier).stop();
        await listen.pause();
        final recite = await _testByVoice();
        if (!mounted) return;
        if (recite) {
          _layers.setMode(QuranMode.recite);
          // The recite layer is built with the next frame; then its passage (and a restored attempt).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final q = ref.read(quranDataProvider).valueOrNull;
            if (!mounted || q == null || ref.read(quranSessionControllerProvider).mode != QuranMode.recite) return;
            final c = ref.read(reciteControllerProvider.notifier);
            s.results.isEmpty ? c.prepare(s.passage, q) : c.restore(s.passage, q, s.results);
            c.setShowAyat(false);
          });
        } else {
          _layers.setMode(QuranMode.memorise);
          _layers.setMemorise(MemoriseMode.words);
          _layers.hideAll();
          if (s.reveals.isNotEmpty) _layers.revealAll(s.reveals);
        }
        _sessions.update((x) => x.withMode(recite ? QuranMode.recite : QuranMode.memorise));
      case SessionStage.reading || SessionStage.done:
        break;
    }
    if (mounted && !_chrome) _setChrome(true);
    if (mounted) setState(() {});
  }

  /// The user kept another surah's recitation over the guided «استماع ×3»: the stage offers
  /// «تخطَّ إلى التكرار» instead of taking the player over.
  bool _keptPlayback = false;

  /// A guided stage ended by itself: its step of the plan ticks, and the next stage begins.
  Future<void> _completeStage() async {
    final s = ref.read(activeSessionProvider);
    if (s == null || !s.kind.guided || s.stage == SessionStage.test || s.finished) return;
    final step = s.stage.hifzStep;
    HapticFeedback.mediumImpact();
    _echoing = false;
    // Not awaited: this may run from inside the microphone's own update (the tenth repetition).
    ref.read(voiceRehearsalProvider.notifier).stop().ignore();
    _sessions.update((x) => x.advance());
    if (step != null && s.kind == QuranSessionKind.hifz) await ref.read(hifzControllerProvider.notifier).completeStep(step);
    final next = ref.read(activeSessionProvider);
    if (next != null && mounted) await _enterStage(next);
  }

  /// «تخطَّ إلى التكرار»: no recitation here; repeating works without it.
  Future<void> _skipToRepeat() async {
    final s = ref.read(activeSessionProvider);
    if (s == null || s.stage != SessionStage.listen) return;
    _keptPlayback = false;
    _sessions.update((x) => x.skipToRepeat());
    final next = ref.read(activeSessionProvider);
    if (next != null && mounted) await _enterStage(next);
  }

  /// Guided listening: rounds counted, and the stage ends when the passage has played three times.
  void _guidedListen(ListenState? prev, ListenState next) {
    final s = ref.read(activeSessionProvider);
    if (s == null || s.stage != SessionStage.listen || next.surah != s.passage.surah) return;
    if (next.roundsDone != s.round) _sessions.update((x) => x.withRound(next.roundsDone));
    final ended = next.loopEnded && !(prev?.loopEnded ?? false) && next.rangeFrom == s.passage.from && next.rangeTo == s.passage.to;
    if (ended) _completeStage();
  }

  /// Echo practice: each ayah plays once, then a pause of about its length to repeat it; one pass of
  /// the passage is one «كرّرت». Without timings or audio it stops (the counter still works).
  Future<void> _echo() async {
    if (_echoing) {
      setState(() => _echoing = false);
      await ref.read(listenControllerProvider.notifier).pause();
      return;
    }
    final s = ref.read(activeSessionProvider);
    if (s == null || s.stage != SessionStage.repeat) return;
    setState(() => _echoing = true);
    final listen = ref.read(listenControllerProvider.notifier);
    final rehearsal = ref.read(voiceRehearsalProvider.notifier);
    // «ردّد بعد القارئ»: with the model on the phone the microphone opens after each ayah and the
    // next one starts once it has been repeated — hands-free.
    final q = ref.read(quranDataProvider).valueOrNull;
    final byVoice = q != null && ref.read(reciteReadyProvider) && await ref.read(reciteControllerProvider.notifier).rationaleSeen();
    final counting = ref.read(voiceRehearsalProvider).mode == RehearsalMode.repeats;
    if (counting) await rehearsal.stop();
    // Echo cuts the recitation into single ayat; the repeat the user had set comes back after it.
    final before = ref.read(listenControllerProvider);
    while (_echoing && mounted && ref.read(activeSessionProvider)?.stage == SessionStage.repeat) {
      for (final a in s.passage.range) {
        if (!_echoing || !mounted) break;
        final gap = await listen.playAyahThenPause(a);
        if (gap == null) {
          _echoing = false;
          break;
        }
        if (byVoice) {
          await rehearsal.echoAyah(a, q, timeout: gap * 2 + const Duration(seconds: 3));
        } else {
          await Future<void>.delayed(gap);
        }
      }
      if (_echoing && mounted) {
        _layers.countRepeat();
        HapticFeedback.selectionClick();
      }
    }
    listen.restoreRepeat(before);
    if (mounted) setState(() => _echoing = false);
    if (counting && mounted && ref.read(activeSessionProvider)?.stage == SessionStage.repeat) await _voiceRepeats(true);
  }

  /// «تكرار ×10» by voice: each full recitation of the passage counts (a soft haptic as the disc
  /// fills). [on] false closes the microphone; the «كرّرت» counter works either way.
  Future<void> _voiceRepeats(bool on) async {
    final rehearsal = ref.read(voiceRehearsalProvider.notifier);
    final s = ref.read(activeSessionProvider);
    final q = ref.read(quranDataProvider).valueOrNull;
    if (!on || s == null || q == null || s.stage != SessionStage.repeat) {
      await rehearsal.stop();
      return;
    }
    if (!await reciteRationale(context, ref) || !mounted) return;
    await rehearsal.listenForRepeats(
      s.passage,
      q,
      onRepeat: () {
        if (!mounted) return;
        _layers.countRepeat();
        HapticFeedback.lightImpact();
      },
    );
  }

  /// Whether the guided test listens to the voice: the flag on and the model on the phone. The
  /// first time the model is missing the calm sheet is offered once; «ليس الآن» → the self-check.
  Future<bool> _testByVoice() async {
    if (!ref.read(remoteConfigProvider).isOn(Flags.recite) || !await ref.read(recitationEngineProvider).isSupported()) return false;
    if (await ref.read(recitationEngineProvider).isAvailable()) return true;
    final kv = ref.read(kvStoreProvider);
    if (await kv.read(asrSheetOfferedKey) != null || !mounted) return false;
    await kv.write(asrSheetOfferedKey, '1');
    if (!mounted) return false;
    return ensureReciteModel(context, ref);
  }

  /// The guided test is open and not graded yet.
  bool get _needsGrade {
    final s = ref.read(activeSessionProvider);
    return s != null && s.kind.guided && s.stage == SessionStage.test;
  }

  /// «انتهيت» (or leaving the test): the grade sheet with the suggestion; after «تأكيد» the grade
  /// goes to the hifz plan — today's passage is memorised, a review rated — and the session ends.
  Future<bool> _finishTest() async {
    final s = ref.read(activeSessionProvider);
    if (s == null || !s.kind.guided || s.stage != SessionStage.test) return false;
    final reciting = ref.read(quranSessionControllerProvider).mode == QuranMode.recite;
    var recite = reciting ? ref.read(reciteControllerProvider) : null;
    if (reciting) {
      final c = ref.read(reciteControllerProvider.notifier);
      if (recite!.listening || recite.phase == RecitePhase.paused) await c.finish();
      recite = ref.read(reciteControllerProvider);
      // The attempt's card first (notes to hear again, «سمّع الملاحظات فقط»), then the grade.
      final progress = recite.progress;
      if (recite.started && progress != null && mounted) {
        final action = await showReciteEndCard(context, progress: progress, graded: true, onPlay: (a) => playAyahOnce(ref, a));
        if (!mounted) return false;
        final q = ref.read(quranDataProvider).valueOrNull;
        if (action == ReciteEndAction.retryFlagged && q != null) {
          await c.retryFlagged(q);
          return false;
        }
        if (action == null) {
          c.acknowledge();
          return false;
        }
      }
      c.acknowledge();
    }
    final plan = await ref.read(hifzControllerProvider.future);
    if (!mounted) return false;
    final portion = plan?.portions.where((p) => p.id == s.portion).firstOrNull;
    final suggestion = suggestGrade(
      recite: recite != null && recite.started && !recite.retrying ? recite.results : null,
      reveals: s.reveals.length,
      helps: recite?.helps ?? 0,
      ayat: s.passage.length,
    );
    final grade = await showGradeSheet(
      context,
      suggestion: suggestion,
      previousInterval: portion?.review.intervalDays ?? 0,
      fresh: s.kind == QuranSessionKind.hifz,
    );
    if (grade == null || !mounted) return false;
    final hifz = ref.read(hifzControllerProvider.notifier);
    if (s.kind == QuranSessionKind.hifz) {
      await hifz.completeStep(2);
      // Only the passage this session studied, and only while it is still the plan's next one: had
      // «حفظت» on the hifz screen recorded it meanwhile, the plan has moved on to a passage this
      // session never covered.
      final q = ref.read(quranDataProvider).valueOrNull;
      final t = q == null ? null : plan?.today(q);
      if (t != null && Passage(t.surah, t.from, t.to) == s.passage) await hifz.memoriseToday();
    } else if (s.portion != null) {
      await hifz.rate(s.portion!, grade);
    }
    _sessions.update((x) => x.finish());
    await _sessions.end();
    if (!mounted) return true;
    HapticFeedback.mediumImpact();
    _endShown = true;
    final next = await _nextStep();
    if (!mounted) return true;
    final router = GoRouter.maybeOf(context);
    final goal = s.kind == QuranSessionKind.hifz ? HifzGuide.steps : 1;
    final go = await showSessionEndCard(context, met: true, done: goal, goal: goal, next: next?.$1);
    if (go == true && next != null && mounted) _handOff(router, next.$2);
    return true;
  }

  /// «التالي»: the next step's reader takes this one's place (not on top of it — the layers, the
  /// session and the recitation are app-wide, and a reader left underneath would come back showing
  /// the next one's).
  void _handOff(GoRouter? router, String location) {
    if (router == null) return;
    _handedOff = true;
    _hideTimer?.cancel();
    router.pushReplacement(location).ignore();
  }

  /// Back / «خروج»: an ungraded test asks for its grade first (dismissing it still leaves; the
  /// session stays saved for later).
  Future<void> _exit() async {
    if (_needsGrade && !_allowPop) {
      await _finishTest();
      if (!mounted) return;
      setState(() => _allowPop = true);
    }
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.of(context).maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go('/quran');
    }
  }

  /// A passage chosen by hand («احفظ من هنا», «إلى هنا», the picker) is a free session: kept on the
  /// device so a kill comes back to it.
  void _choosePassage(Passage p, QuranMode mode) {
    _layers.setPassage(p);
    if (ref.read(activeSessionProvider) != null) {
      _sessions.update((s) => s.withPassage(p));
      return;
    }
    _begin(
          QuranSession.start(
            QuranSessionKind.free,
            p,
            now: ref.read(clockProvider)(),
            day: sessionDay(ref.read, QuranSessionKind.free),
            mode: mode,
            page: _page,
          ),
        )
        .ignore();
  }

  /// A reading session reached its goal: «أتممت جلستك» (gold), then what is next.
  Future<void> _sessionMet(({int done, int goal}) p) async {
    if (_endShown) return;
    _endShown = true;
    final next = await _nextStep();
    _sessions.update((s) => s.finish());
    await _sessions.end();
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    final go = await showSessionEndCard(context, met: true, done: p.done, goal: p.goal, next: next?.$1);
    if (go == true && next != null && mounted) _handOff(router, next.$2);
  }

  /// After a session: a due review first, then today's hifz passage.
  Future<(SessionNext, String)?> _nextStep() async {
    final plan = await ref.read(hifzRepositoryProvider).load();
    final q = ref.read(quranDataProvider).valueOrNull;
    if (plan == null || q == null) return null;
    final today = sessionLocalDay(ref.read);
    final due = plan.due(today).firstOrNull;
    if (due != null) {
      final page = q.pageOf(AyahRef(due.surah, due.from));
      return (
        SessionNext.review,
        '/quran/read/$page?session=review&surah=${due.surah}&from=${due.from}&to=${due.to}&portion=${Uri.encodeQueryComponent(due.id)}',
      );
    }
    final t = plan.memorisedToday(today) ? null : plan.today(q);
    if (t != null) {
      final page = q.pageOf(AyahRef(t.surah, t.from));
      return (SessionNext.hifz, '/quran/read/$page?session=hifz&surah=${t.surah}&from=${t.from}&to=${t.to}');
    }
    return null;
  }

  /// Switches the layer over the page. [ask]: confirm before taking over another surah's audio.
  Future<void> _setMode(QuranMode mode, {bool ask = true}) async {
    // A layer this build doesn't offer (recite without the flag or a model) opens as reading. The
    // model check is asked directly: a deep link may arrive before the dock has its answer.
    final offered = mode == QuranMode.recite
        ? ref.read(remoteConfigProvider).isOn(Flags.recite) && await ref.read(recitationEngineProvider).isSupported()
        : ref.read(quranModesProvider).contains(mode);
    if (!mounted) return;
    if (!offered) mode = QuranMode.read;
    // Before the model is on the phone, the first «تسميع» opens the calm download sheet; «ليس الآن»
    // keeps the layer the reader was on.
    if (mode == QuranMode.recite && !await ensureReciteModel(context, ref)) {
      if (ref.read(quranSessionControllerProvider).mode == QuranMode.recite) _layers.setMode(QuranMode.read);
      return;
    }
    if (!mounted) return;
    if (mode == QuranMode.listen && !await _startListening(ask: ask)) return;
    // Reciting is the reader's own voice: recitation playing pauses first.
    if (mode == QuranMode.recite) await ref.read(listenControllerProvider.notifier).pause();
    if (!mounted) return;
    _layers.setMode(mode);
    _sessions.update((s) => s.withMode(mode));
    _hideTimer?.cancel();
    // Reading and listening fold their tools away after 4 s; memorising and reciting keep them.
    if (mode == QuranMode.read || mode == QuranMode.listen) {
      if (!_chrome) _setChrome(true);
      _scheduleHide();
    } else if (!_chrome) {
      _setChrome(true);
    }
  }

  /// «استماع» from the page on screen: the surah already playing only seeks here; another surah's
  /// audio is replaced only after «استبدال التشغيل الحالي؟». Returns false when the user keeps it.
  Future<bool> _startListening({bool ask = true}) async {
    final q = ref.read(quranDataProvider).valueOrNull;
    if (q == null) return false;
    final ctl = ref.read(listenControllerProvider.notifier);
    final l = ref.read(listenControllerProvider);
    final passage = ref.read(quranSessionControllerProvider).passage;
    final focus = widget.focus;
    final onScreen = _visible(_page);
    // From the chosen passage, else the ayah the reader was opened at, else the page's first ayah.
    final start = passage != null && onScreen.contains(q.pageOf(passage.first))
        ? passage.first
        : focus != null && onScreen.contains(q.pageOf(focus))
            ? focus
            : q.firstOfPage(_page);
    final busy = l.status == ListenStatus.ready && l.playing && l.sampleOf == null;
    if (busy && _visible(_page).contains(q.pageOf(l.ref))) return true; // already reciting this page
    if (busy && l.surah != start.surah && ask) {
      final replace = await _confirmReplace();
      if (!mounted) return false;
      // Keeping what plays: the layer still opens and the page follows that recitation.
      if (replace != true) return true;
    }
    // A chosen passage loops (a hifz portion); otherwise the recitation runs on from here.
    (passage != null && start == passage.first ? ctl.playPassage(passage) : ctl.open(start.surah, ayah: start.ayah)).ignore();
    return true;
  }

  Future<bool?> _confirmReplace() => confirmReplacePlayback(context);

  /// «تسميع» reached its end: the guided test goes on to its grade; free recitation shows its card
  /// (notes to hear again, «سمّع الملاحظات فقط», «تم»).
  Future<void> _reciteDone() async {
    if (_needsGrade) {
      await _finishTest();
      return;
    }
    final c = ref.read(reciteControllerProvider.notifier);
    final progress = ref.read(reciteControllerProvider).progress;
    final q = ref.read(quranDataProvider).valueOrNull;
    if (progress == null || q == null || !mounted) return;
    HapticFeedback.mediumImpact();
    final action = await showReciteEndCard(context, progress: progress, onPlay: (a) => playAyahOnce(ref, a));
    if (!mounted) return;
    if (action == ReciteEndAction.retryFlagged) {
      await c.retryFlagged(q);
    } else {
      c.acknowledge();
    }
  }

  /// The voice moved onto a word of a page not on screen: a real turn to it (the next page), or a
  /// jump. Not while the page is locked, a sheet is open, or the user is browsing away.
  void _followVoice(ReciteProgress? progress, int? current) {
    final q = ref.read(quranDataProvider).valueOrNull;
    if (progress == null || current == null || q == null || !mounted) return;
    final target = q.pageOf(progress.words[current].ayah);
    if (_visible(_page).contains(target)) return;
    final sheetOpen = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (_locked || sheetOpen) return;
    _following = true;
    if (_indexOf(target, _spread) == _indexOf(_page, _spread) + 1) {
      _pager.next(); // a real page curl (a cross-fade under reduce-motion)
    } else {
      _goTo(target);
    }
  }

  /// The page follows the recitation (see [FollowAudio]).
  void _follow(ListenState? prev, ListenState next) {
    if (!mounted || ref.read(quranSessionControllerProvider).mode != QuranMode.listen) return;
    if (prev != null && prev.ref == next.ref && prev.playing == next.playing && prev.status == next.status) return;
    final sheetOpen = !(ModalRoute.of(context)?.isCurrent ?? true);
    final target = FollowAudio.target(
      now: next,
      previousSurah: prev?.surah,
      visible: _visible(_page),
      quran: ref.read(quranDataProvider).valueOrNull,
      blocked: _locked || sheetOpen || _guard.active,
    );
    if (target == null) return;
    _following = true;
    if (_indexOf(target, _spread) == _indexOf(_page, _spread) + 1) {
      _pager.next(); // a real turn (a cross-fade under reduce-motion)
    } else {
      _goTo(target);
    }
    FollowAudio.announce(context, target);
  }

  /// «عُد إلى موضع التلاوة».
  void _backToRecitation(QuranData q) {
    _guard.clear();
    _following = true;
    _goTo(q.pageOf(ref.read(listenControllerProvider).ref));
  }

  Future<void> _openPlayer() async {
    _hideTimer?.cancel();
    await showPlayerSheet(context);
    if (mounted && ref.read(quranSessionControllerProvider).mode == QuranMode.listen) _scheduleHide();
  }

  /// A tap on an ayah, per layer: reveal it (memorise), play from it (listen), hear a noted ayah
  /// once (recite).
  ValueChanged<AyahRef>? _ayahTap(ReaderLayers layers, ReciteState? recite) => switch (layers.mode) {
        QuranMode.memorise => (r) {
            if (layers.passage == null || layers.passage!.contains(r)) _layers.toggleReveal(r);
          },
        QuranMode.listen => (r) => ref.read(listenControllerProvider.notifier).open(r.surah, ayah: r.ayah),
        QuranMode.recite => (r) {
            if (recite?.notes.any((w) => w.ayah == r) ?? false) playAyahOnce(ref, r);
          },
        _ => null,
      };

  /// «من هنا» waiting for its «إلى هنا»: the ayah and the layer it starts.
  ({AyahRef from, QuranMode mode})? _pendingFrom;

  /// The rest of [r]'s surah on the pages on screen: a first guess for «من هنا».
  Passage _fromHere(QuranData q, AyahRef r) {
    var to = r.ayah;
    final onScreen = _visible(_page);
    final n = q.surah(r.surah).ayahCount;
    while (to < n && onScreen.contains(q.pageOf(AyahRef(r.surah, to + 1)))) {
      to++;
    }
    return Passage(r.surah, r.ayah, to);
  }

  /// «احفظ من هنا» / «سمّع من هنا»: the passage starts here; the picker sets its end (or a later
  /// «إلى هنا» on another ayah does).
  Future<void> _layerFrom(QuranMode mode, AyahRef r, QuranData q) async {
    _pendingFrom = (from: r, mode: mode);
    final picked = await showPassagePicker(context, quran: q, initial: _fromHere(q, r));
    if (picked == null || !mounted) return;
    _pendingFrom = null;
    _choosePassage(picked, mode);
    await _setMode(mode);
  }

  void _toHere(AyahRef r) {
    final pending = _pendingFrom;
    if (pending == null) return;
    _pendingFrom = null;
    _choosePassage(Passage(r.surah, pending.from.ayah, r.ayah), pending.mode);
    _setMode(pending.mode);
  }

  /// «استمع من هنا».
  Future<void> _listenFrom(AyahRef r) async {
    await ref.read(listenControllerProvider.notifier).open(r.surah, ayah: r.ayah);
    if (mounted) await _setMode(QuranMode.listen, ask: false);
  }

  AyahLayerActions _sheetLayers(QuranData q, AyahRef r) {
    final modes = ref.read(quranModesProvider);
    final pending = _pendingFrom;
    return AyahLayerActions(
      listenFrom: modes.contains(QuranMode.listen) ? () => _listenFrom(r) : null,
      memoriseFrom: () => _layerFrom(QuranMode.memorise, r, q),
      reciteFrom: modes.contains(QuranMode.recite) ? () => _layerFrom(QuranMode.recite, r, q) : null,
      toHere: pending != null && pending.from.surah == r.surah && r.ayah >= pending.from.ayah ? () => _toHere(r) : null,
    );
  }

  /// What the memorise layer covers: the chosen passage, or every ayah on screen.
  Iterable<AyahRef> _memoriseScope(QuranData q, ReaderLayers layers) =>
      layers.passage?.range ?? [for (final p in _visible(_page)) for (final seg in q.page(p)) ...seg.ayat.map((a) => a.ref)];

  Future<void> _pickPassage(QuranData q, Passage current) async {
    final picked = await showPassagePicker(context, quran: q, initial: current);
    if (picked == null || !mounted) return;
    _choosePassage(picked, ref.read(quranSessionControllerProvider).mode);
    if (!_visible(_page).contains(q.pageOf(picked.first))) _goTo(q.pageOf(picked.first));
  }

  Widget _strip(QuranData q, ReaderLayers layers) => switch (layers.mode) {
        QuranMode.read => ReadStrip(page: _page, onJump: _goTo),
        QuranMode.listen => ListenStrip(onOpenPlayer: _openPlayer, onRetry: () => _startListening(ask: false)),
        QuranMode.memorise => MemoriseStrip(
            quran: q,
            passage: layers.passage ?? Passage.ofPage(q, _page),
            onShowAll: () => _layers.revealAll(_memoriseScope(q, layers)),
            onPickPassage: () => _pickPassage(q, layers.passage ?? Passage.ofPage(q, _page)),
            onListen3: () => ref.read(listenControllerProvider.notifier).playPassage(layers.passage ?? Passage.ofPage(q, _page), times: 3),
          ),
        QuranMode.recite => ReciteStrip(quran: q, passage: layers.passage ?? Passage.ofPage(q, _page)),
      };

  /// The running session over the strip.
  Widget _sessionLine(QuranSession s) => SessionLine(
        session: s,
        onSkipToRepeat: _skipToRepeat,
        onAudioReady: () {
          final now = ref.read(activeSessionProvider);
          if (now != null) _enterStage(now);
        },
        onFinished: () => _finishTest(),
        onEcho: ref.read(quranModesProvider).contains(QuranMode.listen) ? _echo : null,
        echoing: _echoing,
        voice: ref.read(reciteReadyProvider) && s.stage == SessionStage.repeat ? ref.read(voiceRehearsalProvider) : null,
        onVoice: ref.read(reciteReadyProvider) && s.stage == SessionStage.repeat
            ? () => _voiceRepeats(ref.read(voiceRehearsalProvider).mode != RehearsalMode.repeats)
            : null,
        onListenKept: _keptPlayback
            ? () {
                final now = ref.read(activeSessionProvider);
                setState(() => _keptPlayback = false);
                if (now != null) _enterStage(now);
              }
            : null,
      );

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
    // «إبقاء الشاشة مضاءة» takes effect while reading, not only on the next open.
    ref.listen(settingsProvider.select((s) => s.keepAwake), (_, on) => ref.read(deviceServicesProvider).keepAwake(on));
    ref.listen<ListenState>(listenControllerProvider, (prev, next) {
      if (_handedOff) return;
      _follow(prev, next);
      _guidedListen(prev, next);
    });
    // «تكرار ×10»: the tenth repetition ends the stage.
    ref.listen(quranSessionControllerProvider.select((l) => l.repeats), (_, n) {
      if (_handedOff) return;
      final s = ref.read(activeSessionProvider);
      if (s == null || s.stage != SessionStage.repeat) return;
      _sessions.update((x) => x.withRound(n));
      if (n >= HifzGuide.repeatTimes) _completeStage();
    });
    // A reading session meeting its goal ends with its card.
    // Only a change that crosses the goal: a session that opens already met (no progress before)
    // does not end the moment it opens.
    ref.listen(sessionProgressProvider, (prev, next) {
      if (_handedOff) return;
      final s = ref.read(activeSessionProvider);
      if (s == null || s.kind.guided || next == null || next.goal <= 0 || next.done < next.goal) return;
      if (prev == null || prev.done >= prev.goal) return;
      _sessionMet(next);
    });
    // Reveals made while memorising come back after a kill.
    ref.listen(quranSessionControllerProvider.select((l) => l.revealed), (_, revealed) {
      if (revealed.isEmpty || _handedOff) return;
      _sessions.update((s) => s.stage == SessionStage.test || s.kind == QuranSessionKind.free ? s.reveal(revealed) : s);
    });
    // A recitation during the guided test comes back after a kill (on the device only).
    if (ref.read(quranSessionControllerProvider).mode == QuranMode.recite) {
      ref.listen(reciteControllerProvider.select((r) => r.heard), (_, heard) {
        if (_handedOff) return;
        _sessions.update((s) => s.stage == SessionStage.test ? s.withResults(heard) : s);
      });
      // The voice reached the end (or «إنهاء»): the end card — in a guided test, then the grade.
      ref.listen(reciteControllerProvider.select((r) => r.phase), (prev, next) {
        if (_handedOff || next != RecitePhase.done || prev == RecitePhase.done) return;
        _reciteDone();
      });
      // The page turns by itself when the voice is past its last word (spread and follow rules).
      ref.listen(reciteControllerProvider.select((r) => (r.progress, r.progress?.current)), (_, next) {
        if (_handedOff) return;
        _followVoice(next.$1, next.$2);
      });
    }
    // Voice-aware «تحفيظ» lives with the reader (never started by itself: see [_voiceRepeats]).
    ref.watch(voiceRehearsalProvider);
    final session = ref.watch(activeSessionProvider);
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
    final layers = ref.watch(quranSessionControllerProvider);
    // The microphone lives only while the recite layer is on (leaving it stops listening).
    final recite = layers.mode == QuranMode.recite ? ref.watch(reciteControllerProvider) : null;
    final colors = MushafColors.of(look.theme);
    final night = look.theme == MushafTheme.night;
    // The ayah being recited is lit while recitation plays (spec §5.13), in every layer.
    final playing = ref.watch(listenControllerProvider.select((l) => l.playing && l.sampleOf == null ? l.ref : null));
    // Rotation switches between one page and a spread, keeping the page.
    _spread = spreadLayout(MediaQuery.sizeOf(context));
    final spread = _spread;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Memorising, reciting and guided hifz keep their tools on screen; reading and listening fold
    // them away after 4 s.
    final pinned = layers.mode == QuranMode.memorise || layers.mode == QuranMode.recite || (session?.kind.guided ?? false);
    final dockVisible = _chrome || pinned;

    final page = AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: night ? YqColors.nightBg : colors.page,
        body: data.when(
          loading: () => SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: (MediaQuery.sizeOf(context).width * 0.045).clamp(10.0, 30.0), vertical: 6),
              child: const YqSkeletonMushafPage(header: true),
            ),
          ),
          error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(quranDataProvider)),
          data: (q) {
            final first = q.firstOfPage(_page);
            final recitedPage = playing == null ? null : q.pageOf(playing);
            final showBack = layers.mode == QuranMode.listen && _guard.active && recitedPage != null && !_visible(_page).contains(recitedPage);
            // Reciting with «إظهار الآيات» off hides the passage and reveals each ayah as it is recited.
            final reciting = recite != null;
            final layerPassage = layers.mode == QuranMode.read
                ? null
                : reciting
                    ? (recite.passage ?? layers.passage ?? Passage.ofPage(q, _page))
                    : layers.passage;
            Widget frame(int page) => _PageFrame(
                  quran: q,
                  layout: layout,
                  page: page,
                  look: look,
                  spread: spread,
                  selected: _selected ?? _focus,
                  playing: playing,
                  onBackgroundTap: _onPageTap,
                  onOpenSettings: () => showReaderSettings(context, page: _page),
                  annotations: annotations,
                  memorise: reciting ? MemoriseMode.off : layers.hiding,
                  revealed: reciting ? const {} : layers.revealed,
                  passage: layerPassage,
                  marks: reciting ? recite.marks : const {},
                  recite: reciting && recite.progress != null
                      ? ReciteView(progress: recite.progress!, version: recite.version, showText: recite.showText, live: recite.live)
                      : null,
                  onAyahTap: _locked ? null : _ayahTap(layers, recite),
                  onNoteTap: (r) => showNoteSheet(context, quran: q, ref: r),
                  onAyahLongPress: _locked
                      ? null
                      : (ref0) async {
                          HapticFeedback.mediumImpact();
                          setState(() => _selected = ref0);
                          await showAyahSheet(context, quran: q, ref: ref0, layers: _sheetLayers(q, ref0));
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
                if (!_locked) ...[
                  _TopChrome(
                    visible: _chrome,
                    night: night,
                    marked: _pageMarked,
                    onExit: _exit,
                    onSettings: () => showReaderSettings(context, page: _page),
                    onLock: () => setState(() {
                      _locked = true;
                      _setChrome(false);
                    }),
                    onMark: _togglePageMark,
                    onTitle: () => _openJump(q, look.locale),
                    title: q.surah(first.surah).name(look.locale),
                    subtitle: t.quranJuzHizb(q.juzOf(first), q.hizbOf(first)),
                  ),
                  if (layers.mode == QuranMode.listen && !dockVisible)
                    Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: ListenHairline(onShow: () => _setChrome(true)))),
                  AnimatedPositioned(
                    duration: reduceMotion ? Duration.zero : YqMotion.base,
                    curve: YqMotion.ease,
                    bottom: dockVisible ? 0 : -320,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !dockVisible,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(YqSpace.l, 0, YqSpace.l, YqSpace.s),
                          child: QuranModeDock(
                            mode: layers.mode,
                            night: night,
                            onChanged: _setMode,
                            strip: session == null
                                ? _strip(q, layers)
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [_sessionLine(session), _strip(q, layers)],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showBack)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: dockVisible ? 210 : 72,
                      child: SafeArea(top: false, child: Center(child: BackToRecitationChip(onTap: () => _backToRecitation(q)))),
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
    return PopScope(
      // An ungraded guided test asks for its grade before the reader closes.
      canPop: _allowPop || !(session != null && session.kind.guided && session.stage == SessionStage.test),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: page,
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
    this.passage,
    this.marks = const {},
    this.recite,
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
  final Passage? passage;
  final Map<AyahRef, Set<int>> marks;
  final ReciteView? recite;
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
                    passage: passage,
                    marks: marks,
                    recite: recite,
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
    this.passage,
    this.marks = const {},
    this.recite,
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
  final Passage? passage;
  final Map<AyahRef, Set<int>> marks;
  final ReciteView? recite;
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
            passage: widget.passage,
            marks: widget.marks,
            recite: widget.recite,
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
              passage: widget.passage,
              marks: widget.marks,
              recite: widget.recite,
              onAyahLongPress: widget.onAyahLongPress,
              onAyahTap: widget.onAyahTap,
              onNoteTap: widget.onNoteTap,
            ),
          );
        } else {
          // The page's font is on its way (≤ 650 ms): the page's shape, shimmering, not a blank.
          child = const Padding(key: ValueKey('wait'), padding: EdgeInsets.symmetric(vertical: 4), child: YqSkeletonMushafPage());
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
                      YqRing(value: _hold.value, size: 20, stroke: 2.4, track: YqColors.line),
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
        color: YqColors.ink.withValues(alpha: 0.35),
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
