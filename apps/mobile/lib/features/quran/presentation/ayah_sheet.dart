import 'dart:ui' as ui;

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
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_logo.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/reading_repository.dart';
import '../domain/quran_data.dart';
import 'quran_index_screen.dart';

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
  bool _tafsirOpen = false;
  String? _tafsir;

  @override
  void initState() {
    super.initState();
    ref.read(readingRepositoryProvider).bookmarks().then((all) {
      if (mounted) setState(() => _saved = all.any((b) => b.ref == widget.ayah));
    });
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
          ],
        ),
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
Future<void> showShareCard(BuildContext context, WidgetRef ref, {required QuranData quran, required AyahRef ayah}) async {
  final t = AppLocalizations.of(context);
  final key = GlobalKey();
  final surah = quran.surah(ayah.surah).nameAr;
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(YqSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: key,
            child: Container(
              padding: const EdgeInsets.fromLTRB(YqSpace.xxl, YqSpace.xxl, YqSpace.xxl, YqSpace.l),
              decoration: BoxDecoration(color: YqColors.porcelain, borderRadius: BorderRadius.circular(YqRadii.card)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    quran.text(ayah),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: YqText.quran(size: 24, color: YqColors.ink),
                  ),
                  const SizedBox(height: YqSpace.m),
                  Text(t.ayahRefLabel(surah, ayah.ayah), style: const TextStyle(color: YqColors.goldText, fontSize: 13)),
                  const SizedBox(height: YqSpace.xl),
                  const YqLogo(variant: YqLogoVariant.mark, width: 32),
                ],
              ),
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqButton(
            label: t.share,
            icon: const YqIcon(YqIcons.share, size: 18, tone: YqIconTone.light),
            onPressed: () async {
              final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              final image = await boundary?.toImage(pixelRatio: 3);
              final png = await image?.toByteData(format: ui.ImageByteFormat.png);
              if (png != null) {
                await ref.read(deviceServicesProvider).sharePng(
                      png.buffer.asUint8List(),
                      fileName: 'yaqeen-${ayah.surah}-${ayah.ayah}.png',
                      text: t.ayahRefLabel(surah, ayah.ayah),
                    );
              }
              if (c.mounted) Navigator.of(c).pop();
            },
          ),
        ],
      ),
    ),
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
        const SizedBox(height: YqSpace.l),
        Text(t.readerFontSize, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: YqSpace.s),
        YqSegmented<double>(
          segments: [
            for (final (i, size) in AppSettings.fontSizes.indexed) (size, const ['S', 'M', 'L', 'XL'][i]),
          ],
          selected: AppSettings.fontSizes.reduce((a, b) => (a - s.quranFontSize).abs() <= (b - s.quranFontSize).abs() ? a : b),
          onChanged: (v) => ctl.update((x) => x.copyWith(quranFontSize: v), sync: false),
        ),
        const SizedBox(height: YqSpace.m),
        YqListRow(
          title: t.readerSpacing,
          trailing: YqSwitch(
            value: s.comfortableSpacing,
            onChanged: (v) => ctl.update((x) => x.copyWith(comfortableSpacing: v), sync: false),
            label: t.readerSpacing,
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
        const SizedBox(height: YqSpace.s),
        Text(YqFormat.number(s.quranFontSize.round()), textAlign: TextAlign.center, style: YqText.numberSmall),
      ],
    );
  }
}
