import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/outer_shadow.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
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

    final r = st.reciter;
    final ready = quran != null && st.status != ListenStatus.loading && st.status != ListenStatus.idle;
    final download = r != null && st.status != ListenStatus.noReciter
        ? GlassIconButton(
            tooltip: _progress != null
                ? t.reciterDownloading
                : _downloaded == true
                    ? t.reciterDownloaded
                    : t.listenDownloadSurah,
            onPressed: _downloaded == true ? null : () => _download(r, st.surah),
            icon: _progress != null
                ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(value: _progress, strokeWidth: 2.4, color: YqColors.lapis))
                : _downloaded == true
                    ? const Icon(Icons.download_done_rounded, color: YqColors.success, size: 22)
                    : const YqIcon(YqIcons.download, size: 20),
          )
        : null;

    final surah = ready && st.status != ListenStatus.noReciter ? quran.surah(st.surah) : null;
    final stage = YqStage(
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [YqBackButton(label: t.listenBack), const Spacer(), if (download != null) download]),
          if (surah != null) ...[
            const SizedBox(height: YqSpace.l),
            YqMoment(
              eyebrow: t.listenNowPlaying,
              value: Text(
                surah.name(locale),
                style: YqMoment.display(context, size: 48).copyWith(
                  fontFamily: locale == 'ar' ? YqFonts.display : YqFonts.naskh,
                  fontFamilyFallback: YqFonts.displayFallback,
                ),
              ),
              caption: Column(
                children: [
                  Text(t.listenSurahMeta(surah.number, surahTypeLabel(t, surah), surah.ayahCount)),
                  Text(r!.name(locale), style: text.bodyMedium?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final List<Widget> children;
    if (!ready) {
      children = const [Center(child: Padding(padding: EdgeInsets.all(YqSpace.xxl), child: CircularProgressIndicator(color: YqColors.lapis)))];
    } else if (st.status == ListenStatus.noReciter) {
      children = [YqEmptyState(icon: YqIcons.listen, title: t.listenNoReciter)];
    } else if (st.status == ListenStatus.unavailable) {
      children = [YqErrorState(message: t.listenUnavailable, onRetry: () => c.open(st.surah, ayah: st.ayah))];
    } else {
      final total = st.duration ?? Duration.zero;
      final pos = st.position > total && total > Duration.zero ? total : st.position;
      children = [
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
                      TextSpan(text: '﴿${YqFormat.toArabicIndic(st.ayah)}﴾', style: const TextStyle(color: YqColors.goldText)),
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
              if (_tafsir && _tafsirText != null)
                Padding(
                  padding: const EdgeInsets.only(top: YqSpace.xs),
                  child: Text(t.tafsirAttribution, style: text.bodySmall?.copyWith(color: YqColors.goldText)),
                ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.xl),
        // The player as an orbit: the ring is the timeline (drag around it to seek), the ink pill
        // in its heart plays and pauses.
        Center(
          child: _OrbitScrubber(
            value: total.inMilliseconds == 0 ? 0 : pos.inMilliseconds / total.inMilliseconds,
            label: '${mmss(pos)} / ${mmss(total)}',
            onSeek: total.inMilliseconds == 0 ? null : (v) => c.seek(total * v),
            child: Tooltip(
              message: st.playing ? t.listenPause : t.listenPlay,
              child: Semantics(
                button: true,
                label: st.playing ? t.listenPause : t.listenPlay,
                child: Material(
                  color: YqColors.navy,
                  shape: const StadiumBorder(),
                  elevation: 0,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: c.toggle,
                    child: SizedBox(
                      width: 96,
                      height: 64,
                      child: Icon(st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: YqColors.goldLight, size: 36),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: YqSpace.s),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text('${mmss(pos)}  ·  ${mmss(total)}', textAlign: TextAlign.center, style: YqText.numberSmall.copyWith(color: YqColors.muted)),
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
              _RoundIcon(tooltip: t.listenNext, icon: Icons.skip_previous_rounded, onTap: st.synced ? c.next : null),
              Tooltip(
                message: t.listenSpeed(_speed(st.speed)),
                child: TextButton(
                  onPressed: c.cycleSpeed,
                  child: Text('${_speed(st.speed)}×', style: YqText.numberSmall.copyWith(color: YqColors.lapis, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.l),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            YqChip(label: t.listenChangeReciter, selected: false, onTap: () => context.push('/quran/reciters')),
            YqChip(label: t.listenSleepTimer, selected: st.sleepOn, onTap: _sleepSheet),
          ],
        ),
      ];
    }

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(bottom: YqSpace.xxl, stage: stage, children: children),
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

/// A ring that is the track's timeline: progress sweeps with the reading direction, a gold bead
/// marks the position, and dragging (or tapping) around the ring seeks. For screen readers it is
/// a slider that steps 5 %.
class _OrbitScrubber extends StatelessWidget {
  const _OrbitScrubber({required this.value, required this.label, required this.onSeek, required this.child});
  final double value;
  final String label;
  final ValueChanged<double>? onSeek;
  final Widget child;

  static const size = 232.0;

  double _fraction(Offset local, bool rtl) {
    final d = local - const Offset(size / 2, size / 2);
    var a = math.atan2(d.dx, -d.dy); // 0 at the top, clockwise
    if (a < 0) a += math.pi * 2;
    final f = a / (math.pi * 2);
    return rtl ? (1 - f) % 1 : f;
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    void seek(Offset p) => onSeek?.call(_fraction(p, rtl).clamp(0.0, 1.0));
    String pct(double v) => '${(v.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      slider: true,
      label: label,
      value: pct(value),
      increasedValue: pct(value + 0.05),
      decreasedValue: pct(value - 0.05),
      onIncrease: onSeek == null ? null : () => onSeek!((value + 0.05).clamp(0.0, 1.0)),
      onDecrease: onSeek == null ? null : () => onSeek!((value - 0.05).clamp(0.0, 1.0)),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => seek(d.localPosition),
                onPanUpdate: (d) => seek(d.localPosition),
                child: OuterShadow(
                  circle: true,
                  shadows: const [BoxShadow(color: Color(0x260F1A36), blurRadius: 34, spreadRadius: -8, offset: Offset(0, 14))],
                  child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6FFFFFF), Color(0x99FFFFFF)]),
                    border: Border.all(color: const Color(0xF2FFFFFF), width: 1.4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: YqRing(value: value, size: size - 28, stroke: 6),
                  ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
