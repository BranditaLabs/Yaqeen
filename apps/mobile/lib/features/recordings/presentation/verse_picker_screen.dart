import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_skeleton_mushaf.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/annotations.dart';
import '../../quran/domain/mushaf_layout.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/jump_sheet.dart';
import '../../quran/presentation/madani_page.dart';
import '../../quran/presentation/mushaf_page.dart';
import '../../quran/presentation/quran_providers.dart';
import '../domain/recording_models.dart';
import '../domain/verse_selection.dart';
import 'recording_widgets.dart';

/// `/profile/recordings/new` — «اختر الآيات» (APP_SPEC §5.24 «تلاواتي»): the printed mushaf page (the
/// reader's own rendering and ayah hit-testing — KFGQPC page fonts when on the phone, the Amiri text
/// page otherwise). The person **swipes across ayat** from the first to the last; the selection is
/// tinted lapis with the reader's passage rail, both ends adjust with handles, and a live estimate
/// «≈ {n} ث» (≈ 2.2 words a second) warns before 30 s and blocks ranges clearly over it. One surah
/// per recording. Pages turn with the chevrons (the swipe belongs to the selection); «انتقل إلى»
/// from the title jumps to a surah.
class VersePickerScreen extends ConsumerStatefulWidget {
  const VersePickerScreen({super.key, this.initial});

  /// Start on this range (re-recording a rejected recording).
  final Passage? initial;

  @override
  ConsumerState<VersePickerScreen> createState() => _VersePickerScreenState();
}

class _VersePickerScreenState extends ConsumerState<VersePickerScreen> {
  int? _page;
  VerseSelection? _selection;
  final _madani = GlobalKey<MadaniPageState>();
  final _text = GlobalKey<MushafPageState>();

  void _init(QuranData q) {
    if (_page != null) return;
    final p = checkedPassage(q, widget.initial);
    _page = p == null ? 1 : q.pageOf(p.first);
    if (p != null) _selection = VerseSelection.ofPassage(q, p);
  }

  AyahRef? _hit(Offset global) => _madani.currentState?.ayahAt(global) ?? _text.currentState?.ayahAt(global);

  void _select(QuranData q, AyahRef ref) {
    HapticFeedback.selectionClick().ignore();
    setState(() => _selection = VerseSelection.single(q, ref));
  }

  /// A pan that started between ayat anchors on the first ayah it reaches.
  bool _anchored = false;

  void _drag(QuranData q, Offset global) {
    final ref = _hit(global);
    if (ref == null) return;
    final s = _selection;
    if (s == null || !_anchored) {
      _anchored = true;
      _select(q, ref);
      return;
    }
    final next = s.dragTo(ref);
    if (next != s) {
      HapticFeedback.selectionClick().ignore();
      setState(() => _selection = next);
    }
  }

  void _turn(int delta) {
    final p = (_page! + delta).clamp(1, QuranData.pageCount);
    if (p != _page) setState(() => _page = p);
  }

  Future<void> _jump(QuranData q) async {
    final locale = Localizations.localeOf(context).languageCode;
    final target = await showJumpSheet(context, quran: q, currentPage: _page!, locale: locale);
    if (target == null || !mounted) return;
    setState(() {
      _page = target.page;
      if (target.ayah != null) _selection = VerseSelection.single(q, target.ayah!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final layout = ref.watch(mushafLayoutProvider);
    final locale = Localizations.localeOf(context).languageCode;
    if (quran != null) _init(quran);
    final page = _page;
    final sel = _selection;
    final title = quran == null || page == null ? t.recPickTitle : t.quranSurahName(quran.surah(quran.firstOfPage(page).surah).name(locale));

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: YqInsets.page,
                child: YqTopBar(
                  title: t.recPickTitle,
                  actions: [
                    if (quran != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170, minHeight: YqSpace.touch),
                        child: TextButton(
                          key: const ValueKey('rec-pick-jump'),
                          onPressed: () => _jump(quran),
                          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: YqInsets.page,
                child: Text(sel == null ? t.recPickHint : t.recOneSurah, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: YqColors.muted)),
              ),
              const SizedBox(height: YqSpace.s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.m),
                  child: quran == null || page == null || layout.isLoading
                      ? const YqSkeletonMushafPage()
                      : _PageSurface(
                          key: ValueKey('rec-page-$page'),
                          quran: quran,
                          layout: layout.valueOrNull,
                          page: page,
                          selection: sel,
                          madaniKey: _madani,
                          textKey: _text,
                          onTap: (r) => _select(quran, r),
                          onPanStart: (g) {
                            _anchored = false;
                            _drag(quran, g);
                          },
                          onPanUpdate: (g) => _drag(quran, g),
                        ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Reading order: the next page is to the left in Arabic, to the right in English —
                  // the chevrons follow the text direction.
                  IconButton(
                    key: const ValueKey('rec-page-prev'),
                    tooltip: t.recPrevPage,
                    onPressed: page == null || page <= 1 ? null : () => _turn(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(page == null ? '' : YqFormat.number(page), style: const TextStyle(color: YqColors.muted)),
                  IconButton(
                    key: const ValueKey('rec-page-next'),
                    tooltip: t.recNextPage,
                    onPressed: page == null || page >= QuranData.pageCount ? null : () => _turn(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(YqSpace.gutter, 0, YqSpace.gutter, YqSpace.m),
                child: _SelectionPanel(
                  selection: sel,
                  onChanged: (s) => setState(() => _selection = s),
                  onContinue: sel == null || !sel.fit.canRecord
                      ? null
                      : () => context.push('/profile/recordings/record?surah=${sel.surah}&from=${sel.from}&to=${sel.to}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page itself with the selection painted by the reader's own layers (a lapis highlight per
/// ayah, the passage rail), and a pan that selects.
class _PageSurface extends ConsumerStatefulWidget {
  const _PageSurface({
    super.key,
    required this.quran,
    required this.layout,
    required this.page,
    required this.selection,
    required this.madaniKey,
    required this.textKey,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
  });

  final QuranData quran;
  final MushafLayout? layout;
  final int page;
  final VerseSelection? selection;
  final GlobalKey<MadaniPageState> madaniKey;
  final GlobalKey<MushafPageState> textKey;
  final ValueChanged<AyahRef> onTap;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;

  @override
  ConsumerState<_PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends ConsumerState<_PageSurface> {
  @override
  void initState() {
    super.initState();
    final layout = widget.layout;
    if (layout != null) {
      final fonts = ref.read(mushafFontsProvider);
      for (final p in layout.fontsFor(widget.page)) {
        fonts.ensure(p).ignore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final fonts = ref.watch(mushafFontsProvider);
    final sel = widget.selection;
    final annotations = Annotations(
      highlights: {
        if (sel != null)
          for (var a = sel.from; a <= sel.to; a++) AyahRef(sel.surah, a): MarkColor.lapis,
      },
    );
    return Semantics(
      label: t.recPickHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => widget.onPanStart(d.globalPosition),
        onPanUpdate: (d) => widget.onPanUpdate(d.globalPosition),
        child: LiquidGlass(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
          child: ListenableBuilder(
            listenable: fonts,
            builder: (context, _) {
              final layout = widget.layout;
              final ready = layout != null && fonts.allReady(layout.fontsFor(widget.page));
              if (ready) {
                return MadaniPage(
                  key: widget.madaniKey,
                  layout: layout,
                  quran: widget.quran,
                  page: widget.page,
                  theme: MushafTheme.white,
                  annotations: annotations,
                  passage: sel?.passage,
                  onAyahTap: widget.onTap,
                );
              }
              return FittedMushafPage(
                page: MushafPage(
                  key: widget.textKey,
                  quran: widget.quran,
                  page: widget.page,
                  theme: MushafTheme.white,
                  fontSize: 20,
                  comfortable: false,
                  locale: Localizations.localeOf(context).languageCode,
                  annotations: annotations,
                  passage: sel?.passage,
                  onAyahTap: widget.onTap,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The selection, its estimate, the two handles and «تابع للتسجيل».
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.selection, required this.onChanged, required this.onContinue});
  final VerseSelection? selection;
  final ValueChanged<VerseSelection> onChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = selection;
    final limit = YqFormat.number(kRecordingMaxMs ~/ 1000);
    if (s == null) {
      return LiquidGlass(
        child: Row(
          children: [
            const Icon(Icons.swipe_rounded, color: YqColors.lapis),
            const SizedBox(width: YqSpace.m),
            Expanded(child: Text(t.recPickNone, style: text.bodyMedium)),
          ],
        ),
      );
    }
    final seconds = YqFormat.number((s.estimate.inMilliseconds / 1000).ceil());
    final (String? note, bool strong) = switch (s.fit) {
      RangeFit.ok => (null, false),
      RangeFit.near => (t.recEstimateNear(limit), false),
      RangeFit.over => (t.recEstimateOver(limit), true),
      RangeFit.blocked when s.unrecordable => (t.recAyahTooLong(limit), true),
      RangeFit.blocked => (t.recEstimateBlocked(limit), true),
    };
    return LiquidGlass(
      key: const ValueKey('rec-pick-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: VerseRefText(surah: s.surah, from: s.from, to: s.to, style: text.titleSmall)),
              const SizedBox(width: YqSpace.s),
              Text(
                t.recEstimate(seconds),
                key: const ValueKey('rec-estimate'),
                style: TextStyle(fontWeight: FontWeight.w700, color: strong ? YqColors.ink : YqColors.lapis),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: YqSpace.xs),
            Text(note, key: ValueKey(s.unrecordable ? 'rec-fit-unrecordable' : 'rec-fit-${s.fit.name}'), style: TextStyle(fontSize: 12.5, color: strong ? YqColors.ink : YqColors.muted, fontWeight: strong ? FontWeight.w600 : FontWeight.w400)),
          ],
          const SizedBox(height: YqSpace.s),
          Row(
            children: [
              Expanded(
                child: _Handle(
                  label: t.recStartHandle,
                  value: s.from,
                  onLess: s.from > 1 ? () => onChanged(s.moveStart(-1)) : null,
                  onMore: s.from < s.to ? () => onChanged(s.moveStart(1)) : null,
                  keyPrefix: 'rec-start',
                ),
              ),
              const SizedBox(width: YqSpace.s),
              Expanded(
                child: _Handle(
                  label: t.recEndHandle,
                  value: s.to,
                  onLess: s.to > s.from ? () => onChanged(s.moveEnd(-1)) : null,
                  onMore: s.to < s.ayahCount ? () => onChanged(s.moveEnd(1)) : null,
                  keyPrefix: 'rec-end',
                ),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          if (s.unrecordable)
            // Trimming cannot help (its first ayah alone is too long): the note says why.
            YqButton(key: const ValueKey('rec-continue'), label: t.recContinue, onPressed: null)
          else if (s.fit == RangeFit.blocked)
            YqButton.secondary(key: const ValueKey('rec-trim'), label: t.recTrim, onPressed: () => onChanged(s.trimmedToFit()))
          else
            YqButton(key: const ValueKey('rec-continue'), label: t.recContinue, onPressed: onContinue),
        ],
      ),
    );
  }
}

/// One end of the range: «أول آية 3» with − / + (44-pt targets).
class _Handle extends StatelessWidget {
  const _Handle({required this.label, required this.value, required this.onLess, required this.onMore, required this.keyPrefix});
  final String label;
  final int value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(color: YqColors.ice, borderRadius: BorderRadius.circular(YqRadii.chip)),
      child: Row(
        children: [
          IconButton(key: ValueKey('$keyPrefix-less'), tooltip: t.recFewer, onPressed: onLess, icon: const Icon(Icons.remove_rounded, size: 20)),
          Expanded(
            child: Column(
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: YqColors.muted)),
                Text(YqFormat.number(value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: YqColors.ink)),
              ],
            ),
          ),
          IconButton(key: ValueKey('$keyPrefix-more'), tooltip: t.recMore, onPressed: onMore, icon: const Icon(Icons.add_rounded, size: 20)),
        ],
      ),
    );
  }
}
