import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/share_card.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/reading_repository.dart';
import '../domain/annotations.dart';
import '../domain/quran_data.dart';
import 'mushaf_download.dart';
import 'note_sheet.dart';
import 'quran_index_screen.dart';
import 'quran_providers.dart';

/// «خيارات الآية» (spec §5.11): bookmark · listen · tafsir · share · copy.
Future<void> showAyahSheet(BuildContext context, {required QuranData quran, required AyahRef ref}) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => _AyahSheet(quran: quran, ayah: ref));

class _AyahSheet extends ConsumerStatefulWidget {
  const _AyahSheet({required this.quran, required this.ayah});
  final QuranData quran;
  final AyahRef ayah;

  @override
  ConsumerState<_AyahSheet> createState() => _AyahSheetState();
}

class _AyahSheetState extends ConsumerState<_AyahSheet> {
  bool? _saved;
  MarkColor _bookmarkColor = MarkColor.gold;
  bool _tafsirOpen = false;
  bool _highlightOpen = false;
  String? _tafsir;
  MarkColor? _highlight;
  bool _hasNote = false;

  @override
  void initState() {
    super.initState();
    final reading = ref.read(readingRepositoryProvider);
    reading.bookmarks().then((all) {
      final b = all.where((b) => b.ref == widget.ayah).firstOrNull;
      if (mounted) {
        setState(() {
          _saved = b != null;
          _bookmarkColor = b?.color ?? MarkColor.gold;
        });
      }
    });
    reading.annotations().then((a) {
      if (mounted) {
        setState(() {
          _highlight = a.highlights[widget.ayah];
          _hasNote = a.notes.containsKey(widget.ayah);
        });
      }
    });
  }

  Future<void> _setHighlight(MarkColor? c) async {
    await ref.read(readingRepositoryProvider).setHighlight(widget.ayah, c);
    ref.invalidate(annotationsProvider);
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _highlight = c);
  }

  Future<void> _setBookmarkColor(MarkColor c) async {
    await ref.read(readingRepositoryProvider).recolor('a${widget.ayah}', c);
    ref.invalidate(bookmarksProvider);
    if (mounted) setState(() => _bookmarkColor = c);
  }

  String get _surahName => widget.quran.surah(widget.ayah.surah).nameAr;

  Future<void> _toggleBookmark() async {
    final now = ref.read(clockProvider)();
    final saved = await ref.read(readingRepositoryProvider).toggle(
          Bookmark(kind: BookmarkKind.ayah, page: widget.quran.pageOf(widget.ayah), ref: widget.ayah, at: now),
        );
    ref.invalidate(bookmarksProvider);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _openTafsir() async {
    final text = await ref.read(tafsirRepositoryProvider).forAyah(widget.ayah);
    if (!mounted) return;
    setState(() {
      _tafsirOpen = !_tafsirOpen;
      _tafsir = text;
    });
  }

  Future<void> _copy() async {
    final t = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: '${widget.quran.text(widget.ayah)}\n${t.ayahRefLabel(_surahName, widget.ayah.ayah)}'));
    if (mounted) YqToast.show(context, t.copied);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final listenOn = ref.watch(remoteConfigProvider).isOn(Flags.listen);
    final theme = Theme.of(context).textTheme;
    final saved = _saved ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.ayahOptions, style: theme.titleLarge),
        Text('${t.quranSurahName(_surahName)} · ${t.quranAyahN(widget.ayah.ayah)}', style: theme.bodySmall),
        const SizedBox(height: YqSpace.l),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            _Action(icon: YqIcons.bookmark, label: saved ? t.ayahBookmarked : t.ayahBookmark, active: saved, onTap: _toggleBookmark),
            if (listenOn)
              _Action(
                icon: YqIcons.listen,
                label: t.ayahListen,
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/quran/listen/${widget.ayah.surah}?ayah=${widget.ayah.ayah}');
                },
              ),
            _Action(icon: YqIcons.quran, label: t.ayahTafsir, active: _tafsirOpen, onTap: _openTafsir),
            _Action(
              icon: YqIcons.share,
              label: t.ayahShare,
              onTap: () => showShareCard(context, ref, quran: widget.quran, ayah: widget.ayah),
            ),
            _Action(icon: YqIcons.dua, material: Icons.content_copy_rounded, label: t.ayahCopy, onTap: _copy),
            _Action(
              icon: YqIcons.dua,
              material: Icons.format_color_fill_rounded,
              label: t.ayahHighlight,
              active: _highlight != null || _highlightOpen,
              onTap: () => setState(() => _highlightOpen = !_highlightOpen),
            ),
            _Action(
              icon: YqIcons.dua,
              material: Icons.sticky_note_2_outlined,
              label: _hasNote ? t.ayahNoteEdit : t.ayahNote,
              active: _hasNote,
              onTap: () {
                Navigator.of(context).pop();
                showNoteSheet(context, quran: widget.quran, ref: widget.ayah);
              },
            ),
          ],
        ),
        if (saved) ...[
          const SizedBox(height: YqSpace.m),
          _ColorRow(label: t.ayahBookmarkColor, selected: _bookmarkColor, onPick: (c) => _setBookmarkColor(c ?? MarkColor.gold)),
        ],
        if (_highlightOpen) ...[
          const SizedBox(height: YqSpace.m),
          _ColorRow(label: t.ayahHighlight, selected: _highlight, onPick: _setHighlight, allowNone: true),
        ],
        AnimatedSize(
          duration: YqMotion.base,
          curve: YqMotion.ease,
          child: _tafsirOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: YqSpace.l),
                  child: Container(
                    padding: const EdgeInsets.all(YqSpace.l),
                    decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(YqRadii.tile)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.tafsirTitle, style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: YqSpace.s),
                        // Licensed text only; until a pack is installed the placeholder stays bracketed (rule 9).
                        Text(
                          _tafsir ?? t.tafsirPlaceholder,
                          style: theme.bodyLarge?.copyWith(color: _tafsir == null ? YqColors.muted : YqColors.ink),
                        ),
                        // Credit every time the licensed text is shown (QuranEnc republishing terms).
                        if (_tafsir != null) ...[
                          const SizedBox(height: YqSpace.s),
                          Text(t.tafsirAttribution, style: theme.bodySmall?.copyWith(color: YqColors.goldText)),
                        ],
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Four token colours (+ «بلا تظليل» for highlights).
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.label, required this.selected, required this.onPick, this.allowNone = false});
  final String label;
  final MarkColor? selected;
  final ValueChanged<MarkColor?> onPick;
  final bool allowNone;

  static Color swatch(MarkColor c) => switch (c) {
        MarkColor.gold => YqColors.gold,
        MarkColor.lapis => YqColors.lapis,
        MarkColor.sky => YqColors.sky,
        MarkColor.green => YqColors.success,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String name(MarkColor c) => switch (c) {
          MarkColor.gold => t.markColorGold,
          MarkColor.lapis => t.markColorLapis,
          MarkColor.sky => t.markColorSky,
          MarkColor.green => t.markColorGreen,
        };
    Widget dot(MarkColor? c) {
      final on = c == selected;
      return Semantics(
        button: true,
        selected: on,
        label: c == null ? t.ayahHighlightRemove : name(c),
        excludeSemantics: true,
        child: InkResponse(
          onTap: () => onPick(c),
          radius: 26,
          child: AnimatedContainer(
            duration: YqMotion.fast,
            width: YqSpace.touch,
            height: YqSpace.touch,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: on ? YqColors.ink : const Color(0x00000000), width: 2),
            ),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c == null ? YqColors.white : swatch(c),
                border: c == null ? Border.all(color: YqColors.line) : null,
              ),
              child: c == null ? const Icon(Icons.block_rounded, size: 16, color: YqColors.muted) : null,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
        if (allowNone) dot(null),
        for (final c in MarkColor.values) dot(c),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.active = false, this.material});
  final YqIcons icon;

  /// For actions the 20-icon set doesn't cover (copy).
  final IconData? material;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 60,
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(YqRadii.tile),
            onTap: onTap,
            child: Column(
              children: [
                if (material != null)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: const Color(0x141F3F94), borderRadius: BorderRadius.circular(YqRadii.chip)),
                    child: Icon(material, color: YqColors.lapis, size: 22),
                  )
                else
                  YqIconTile(icon, gold: active, size: 52),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}

/// Image card for sharing an ayah: porcelain, the verse, its reference and the brand mark.
Future<void> showShareCard(BuildContext context, WidgetRef ref, {required QuranData quran, required AyahRef ayah}) {
  final t = AppLocalizations.of(context);
  return showTextShareCard(
    context,
    ref,
    text: quran.text(ayah),
    reference: t.ayahRefLabel(quran.surah(ayah.surah).nameAr, ayah.ayah),
    fileName: 'yaqeen-${ayah.surah}-${ayah.ayah}.png',
    quranic: true,
  );
}

/// «إعدادات القراءة».
Future<void> showReaderSettings(BuildContext context) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => const _ReaderSettings());

class _ReaderSettings extends ConsumerWidget {
  const _ReaderSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final reciteOn = ref.watch(remoteConfigProvider).isOn(Flags.recite);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.readerSettings, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: YqSpace.l),
        Text(t.readerPageColor, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: YqSpace.s),
        YqSegmented<MushafTheme>(
          segments: [(MushafTheme.paper, t.themePaper), (MushafTheme.white, t.themeWhite), (MushafTheme.night, t.themeNight)],
          selected: s.mushafTheme,
          onChanged: (v) => ctl.update((x) => x.copyWith(mushafTheme: v), sync: false),
        ),
        // The printed page sets the text size (no font-size control: a page always fits, like print).
        const SizedBox(height: YqSpace.l),
        Text(t.readerPageTurn, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: YqSpace.s),
        YqSegmented<PageTurn>(
          segments: [(PageTurn.book, t.pageTurnBook), (PageTurn.slide, t.pageTurnSlide)],
          selected: s.pageTurn,
          onChanged: (v) => ctl.update((x) => x.copyWith(pageTurn: v), sync: false),
        ),
        const SizedBox(height: YqSpace.s),
        YqListRow(
          title: t.readerAutoNight,
          trailing: YqSwitch(
            value: s.autoNight,
            onChanged: (v) => ctl.update((x) => x.copyWith(autoNight: v), sync: false),
            label: t.readerAutoNight,
          ),
        ),
        YqListRow(
          title: t.readerImmersive,
          trailing: YqSwitch(
            value: s.immersiveReading,
            onChanged: (v) => ctl.update((x) => x.copyWith(immersiveReading: v), sync: false),
            label: t.readerImmersive,
          ),
        ),
        YqListRow(
          title: t.readerKeepAwake,
          trailing: YqSwitch(
            value: s.keepAwake,
            onChanged: (v) => ctl.update((x) => x.copyWith(keepAwake: v), sync: false),
            label: t.readerKeepAwake,
          ),
        ),
        const YqDivider(),
        YqListRow(
          leading: const YqIconTile(YqIcons.listen),
          title: t.readerListenMode,
          onTap: () {
            Navigator.of(context).pop();
            final page = int.tryParse(GoRouterState.of(context).pathParameters['page'] ?? '') ?? 1;
            ref.read(quranDataProvider).whenData((q) => context.push('/quran/listen/${q.firstOfPage(page).surah}'));
          },
        ),
        if (reciteOn)
          YqListRow(
            leading: const YqIconTile(YqIcons.azkar),
            title: t.readerReciteMode,
            onTap: () {
              Navigator.of(context).pop();
              final page = int.tryParse(GoRouterState.of(context).pathParameters['page'] ?? '') ?? 1;
              ref.read(quranDataProvider).whenData((q) => context.push('/quran/recite/${q.firstOfPage(page).surah}'));
            },
          ),
        const YqDivider(),
        const SizedBox(height: YqSpace.s),
        const MushafDownloadSection(),
      ],
    );
  }
}
