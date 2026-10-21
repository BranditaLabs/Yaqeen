import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/quran_index_screen.dart';
import '../data/audio_downloads.dart';
import '../domain/audio_models.dart';
import 'listen_controller.dart';

String mmss(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0
      ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
      : '${d.inMinutes}:${two(d.inSeconds.remainder(60))}';
}

/// `11 · Now playing` (spec §5.13).
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key, required this.surah, this.ayah});
  final int surah;
  final int? ayah;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _tafsir = false;
  String? _tafsirText;
  bool? _downloaded;
  double? _progress;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    final s = ref.read(listenControllerProvider);
    if (s.status == ListenStatus.idle || s.surah != widget.surah || widget.ayah != null) {
      Future.microtask(() => ref.read(listenControllerProvider.notifier).open(widget.surah, ayah: widget.ayah));
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _refreshDownloaded(Reciter r, int surah) async {
    final has = await ref.read(audioDownloadsProvider).has(r.id, surah);
    if (mounted) setState(() => _downloaded = has);
  }

  Future<void> _download(Reciter r, int surah) async {
    final t = AppLocalizations.of(context);
    if (_cancel != null) {
      _cancel!.cancel();
      return;
    }
    final token = _cancel = CancelToken();
    setState(() => _progress = 0);
    try {
      await ref.read(audioDownloadsProvider).downloadSurah(
        r,
        surah,
        cancel: token,
        allowMetered: await ref.read(listenStoreProvider).allowMetered(),
        onProgress: (got, total) {
          if (mounted && total != null && total > 0) setState(() => _progress = got / total);
        },
      );
      if (mounted) setState(() => _downloaded = true);
    } on WifiRequired {
      if (mounted) YqToast.show(context, t.reciterWifiOnly);
    } on DownloadCancelled {
      // the partial file stays; the next tap resumes
    } on Exception {
      if (mounted) YqToast.show(context, t.listenUnavailable);
    } finally {
      _cancel = null;
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _toggleTafsir(AyahRef ref0) async {
    final text = _tafsir ? _tafsirText : await ref.read(tafsirRepositoryProvider).forAyah(ref0);
    if (mounted) {
      setState(() {
        _tafsir = !_tafsir;
        _tafsirText = text;
      });
    }
  }

  void _sleepSheet() {
    final t = AppLocalizations.of(context);
    final c = ref.read(listenControllerProvider.notifier);
    showYqSheet<void>(
      context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.listenSleepTimer, style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: YqSpace.m),
          for (final m in sleepTimerMinutes)
            YqListRow(
              title: t.minutesN(m),
              onTap: () {
                c.setSleep(m);
                Navigator.of(sheet).pop();
              },
            ),
          YqListRow(
            title: t.listenSleepEnd,
            onTap: () {
              c.setSleep(0);
              Navigator.of(sheet).pop();
            },
          ),
          YqListRow(
            title: t.listenSleepOff,
            titleColor: YqColors.muted,
            onTap: () {
              c.setSleep(null);
              Navigator.of(sheet).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final st = ref.watch(listenControllerProvider);
    final c = ref.read(listenControllerProvider.notifier);
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final text = Theme.of(context).textTheme;

    ref.listen(listenControllerProvider.select((s) => (s.reciter?.id, s.surah)), (prev, next) {
      final r = ref.read(listenControllerProvider).reciter;
      if (r != null && prev != next) _refreshDownloaded(r, next.$2);
    });
    ref.listen(listenControllerProvider.select((s) => s.ref), (prev, next) {
      if (_tafsir && prev != next) setState(() => _tafsir = false);
    });

    Widget body;
    if (quran == null || st.status == ListenStatus.loading || st.status == ListenStatus.idle) {
      body = const Center(child: CircularProgressIndicator(color: YqColors.lapis));
    } else if (st.status == ListenStatus.noReciter) {
      body = Center(child: YqEmptyState(icon: YqIcons.listen, title: t.listenNoReciter));
    } else {
      final surah = quran.surah(st.surah);
      final r = st.reciter!;
      final total = st.duration ?? Duration.zero;
      final pos = st.position > total && total > Duration.zero ? total : st.position;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.s, YqSpace.gutter, YqSpace.xxl),
        children: [
          Text(t.listenNowPlaying, style: text.labelMedium?.copyWith(color: YqColors.goldText, letterSpacing: 0.2)),
          const SizedBox(height: YqSpace.s),
          LiquidGlass(
            padding: const EdgeInsets.all(YqSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.listenSurahMeta(surah.number, surahTypeLabel(t, surah), surah.ayahCount), style: text.bodySmall),
                const SizedBox(height: YqSpace.xs),
                Text(surah.name(locale), style: YqText.display.copyWith(fontSize: 34)),
                const SizedBox(height: YqSpace.xs),
                Text(r.name(locale), style: text.bodyMedium?.copyWith(color: YqColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.m),
          if (st.status == ListenStatus.unavailable)
            YqErrorState(message: t.listenUnavailable, onRetry: () => c.open(st.surah, ayah: st.ayah))
          else ...[
            LiquidGlass(
              padding: const EdgeInsets.all(YqSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${quran.text(st.ref)} '),
                          TextSpan(
                            text: '﴿${YqFormat.toArabicIndic(st.ayah)}﴾',
                            style: const TextStyle(color: YqColors.goldText),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: YqText.quran(size: 24, height: 2.1, color: YqColors.ink),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => _toggleTafsir(st.ref),
                      icon: Icon(_tafsir ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                      label: Text(t.tafsirTitle),
                    ),
                  ),
                  if (_tafsir)
                    Text(
                      _tafsirText ?? t.tafsirPlaceholder,
                      style: text.bodyMedium?.copyWith(color: _tafsirText == null ? YqColors.muted : YqColors.ink),
                    ),
                ],
              ),
            ),
            const SizedBox(height: YqSpace.l),
            Semantics(
              label: '${mmss(pos)} / ${mmss(total)}',
              child: Slider(
                value: total.inMilliseconds == 0 ? 0 : pos.inMilliseconds / total.inMilliseconds,
                onChanged: total.inMilliseconds == 0 ? null : (v) => c.seek(total * v),
                activeColor: YqColors.lapis,
                inactiveColor: YqColors.sky200,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.l),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(mmss(pos), style: YqText.numberSmall), Text(mmss(total), style: YqText.numberSmall)],
                ),
              ),
            ),
            const SizedBox(height: YqSpace.l),
            Semantics(
              container: true,
              label: t.listenControls,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundIcon(
                    tooltip: t.listenRepeat,
                    icon: Icons.repeat_one_rounded,
                    active: st.repeat == ListenRepeat.ayah,
                    onTap: st.synced ? c.toggleRepeatAyah : null,
                  ),
                  // RTL: «previous ayah» sits on the right, matching reading direction.
                  _RoundIcon(tooltip: t.listenPrev, icon: Icons.skip_next_rounded, onTap: st.synced ? c.previous : null),
                  Tooltip(
                    message: st.playing ? t.listenPause : t.listenPlay,
                    child: Semantics(
                      button: true,
                      label: st.playing ? t.listenPause : t.listenPlay,
                      child: Material(
                        color: YqColors.ink,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: c.toggle,
                          child: SizedBox(
                            width: 88,
                            height: 64,
                            child: Icon(st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: YqColors.white, size: 34),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _RoundIcon(tooltip: t.listenNext, icon: Icons.skip_previous_rounded, onTap: st.synced ? c.next : null),
                  Tooltip(
                    message: t.listenSpeed(_speed(st.speed)),
                    child: TextButton(
                      onPressed: c.cycleSpeed,
                      child: Text('${_speed(st.speed)}×', style: YqText.numberSmall.copyWith(color: YqColors.lapis)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: YqSpace.xl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: YqSpace.s,
            runSpacing: YqSpace.s,
            children: [
              YqChip(label: t.listenChangeReciter, selected: false, onTap: () => context.push('/quran/reciters')),
              YqChip(label: t.listenSleepTimer, selected: st.sleepOn, onTap: _sleepSheet),
            ],
          ),
        ],
      );
    }

    final r = st.reciter;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.s, YqSpace.gutter, 0),
                child: Row(
                  children: [
                    YqBackButton(label: t.listenBack),
                    const Spacer(),
                    if (r != null && st.status != ListenStatus.noReciter)
                      GlassIconButton(
                        tooltip: _progress != null
                            ? t.reciterDownloading
                            : _downloaded == true
                                ? t.reciterDownloaded
                                : t.listenDownloadSurah,
                        onPressed: _downloaded == true ? null : () => _download(r, st.surah),
                        icon: _progress != null
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(value: _progress, strokeWidth: 2.4, color: YqColors.lapis),
                              )
                            : _downloaded == true
                                ? const Icon(Icons.download_done_rounded, color: YqColors.success, size: 22)
                                : const YqIcon(YqIcons.download, size: 20),
                      ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  static String _speed(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.tooltip, required this.icon, required this.onTap, this.active = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: active ? true : null,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          iconSize: 28,
          color: active ? YqColors.lapis : YqColors.ink,
          disabledColor: YqColors.slate200,
          style: active ? IconButton.styleFrom(backgroundColor: YqColors.sky100) : null,
          icon: Icon(icon),
        ),
      );
}
