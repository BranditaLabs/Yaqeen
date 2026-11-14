import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/outer_shadow.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/data/tafsir_repository.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/jump_sheet.dart';
import '../../quran/presentation/quran_index_screen.dart' show surahTypeLabel;
import '../data/audio_downloads.dart';
import '../domain/audio_models.dart';
import 'downloads_controller.dart';
import 'listen_controller.dart';
import 'repeat_sheet.dart';

String mmss(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}' : '${d.inMinutes}:${two(d.inSeconds.remainder(60))}';
}

/// The expanded player (spec §5.13 `PlayerSheet`), over the reader or from the mini player: the
/// recited ayah with its tafsir line, the orbit scrubber, repeat / speed / sleep, «تغيير القارئ», a
/// jump picker and the surah's download.
Future<void> showPlayerSheet(BuildContext context) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => const PlayerSheet());

class PlayerSheet extends ConsumerStatefulWidget {
  const PlayerSheet({super.key});

  @override
  ConsumerState<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<PlayerSheet> {
  bool _tafsir = false;
  bool _tafsirLoading = false;
  int _tafsirSeq = 0;
  String? _tafsirText;
  TafsirSource? _tafsirSource;
  bool? _downloaded;

  @override
  void initState() {
    super.initState();
    final s = ref.read(listenControllerProvider);
    if (s.reciter != null) Future.microtask(() => _refreshDownloaded(s.reciter!, s.surah));
  }

  Future<void> _refreshDownloaded(Reciter r, int surah) async {
    final has = await ref.read(audioDownloadsProvider).has(r.id, surah);
    if (mounted) setState(() => _downloaded = has);
  }

  Future<void> _download(Reciter r, int surah) async {
    final t = AppLocalizations.of(context);
    try {
      await ref.read(downloadsControllerProvider.notifier).downloadSurah(r, surah);
      if (mounted) setState(() => _downloaded = true);
    } on WifiRequired {
      if (mounted) YqToast.show(context, t.reciterWifiOnly);
    } on DownloadCancelled {
      // the partial file stays; the next tap resumes
    } on Exception {
      if (mounted) YqToast.show(context, t.listenUnavailable);
    }
  }

  /// Opens at once with a skeleton while the text loads (spec §2.5); a late answer for an earlier
  /// ayah or a closed line is dropped.
  Future<void> _toggleTafsir(AyahRef ref0) async {
    final seq = ++_tafsirSeq;
    if (_tafsir) {
      setState(() {
        _tafsir = false;
        _tafsirLoading = false;
      });
      return;
    }
    setState(() {
      _tafsir = true;
      _tafsirLoading = true;
    });
    final found = await ref.read(tafsirRepositoryProvider).lookup(ref0);
    if (!mounted || seq != _tafsirSeq) return;
    setState(() {
      _tafsirLoading = false;
      _tafsirText = found?.text;
      _tafsirSource = found?.source;
    });
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
          Text(t.qsSleepTimer, style: Theme.of(sheet).textTheme.titleLarge),
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

  Future<void> _jump(QuranData q, String locale) async {
    final s = ref.read(listenControllerProvider);
    final target = await showJumpSheet(context, quran: q, currentPage: q.pageOf(s.ref), locale: locale);
    if (target == null) return;
    final at = target.ayah ?? q.firstOfPage(target.page);
    await ref.read(listenControllerProvider.notifier).open(at.surah, ayah: at.ayah);
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
      if (_tafsir && prev != next) {
        _tafsirSeq++;
        setState(() {
          _tafsir = false;
          _tafsirLoading = false;
        });
      }
    });

    if (quran == null || st.status == ListenStatus.idle || st.status == ListenStatus.loading) {
      // Shaped like what arrives: the title, the ayah lines, then the orbit.
      return const YqSkeleton(
        child: Column(
          children: [
            YqSkeletonLine(widthFactor: 0.5, height: 22),
            SizedBox(height: YqSpace.l),
            YqSkeletonText(lines: 3, lineHeight: 22),
            SizedBox(height: YqSpace.xl),
            YqSkeletonBox.circle(200),
          ],
        ),
      );
    }
    if (st.status == ListenStatus.noReciter) return YqEmptyState(icon: YqIcons.listen, title: t.listenNoReciter);
    if (st.status == ListenStatus.unavailable) {
      return YqErrorState(message: t.listenUnavailable, onRetry: () => c.open(st.surah, ayah: st.ayah, reload: true));
    }

    final r = st.reciter;
    final surah = quran.surah(st.surah);
    final total = st.duration ?? Duration.zero;
    final pos = st.position > total && total > Duration.zero ? total : st.position;
    final key = r == null ? null : surahDownloadKey(r.id, st.surah);
    final progress = key == null ? null : ref.watch(surahDownloadsProvider.select((m) => m[key]));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.listenNowPlaying, style: text.labelSmall?.copyWith(color: YqColors.muted)),
                  Text(
                    surah.name(locale),
                    style: TextStyle(
                      fontFamily: locale == 'ar' ? YqFonts.display : YqFonts.naskh,
                      fontFamilyFallback: YqFonts.displayFallback,
                      fontSize: 30,
                      height: 1.3,
                      color: YqColors.ink,
                    ),
                  ),
                  Text(t.listenSurahMeta(surah.number, surahTypeLabel(t, surah), surah.ayahCount), style: text.bodySmall),
                  if (r != null) Text(r.name(locale), style: text.bodyMedium?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (r != null)
              IconButton(
                tooltip: progress != null
                    ? t.reciterDownloading
                    : _downloaded == true
                        ? t.reciterDownloaded
                        : t.listenDownloadSurah,
                onPressed: _downloaded == true || progress != null ? null : () => _download(r, st.surah),
                icon: progress != null
                    ? YqRing(value: progress, size: 22, stroke: 2.4)
                    : _downloaded == true
                        ? const Icon(Icons.download_done_rounded, color: YqColors.success, size: 22)
                        : const YqIcon(YqIcons.download, size: 20),
              ),
          ],
        ),
        const SizedBox(height: YqSpace.m),
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
            style: YqText.quran(size: 22, height: 2.1, color: YqColors.ink),
          ),
        ),
        // The tafsir line: licensed text with its attribution, else the bracketed placeholder (rule 9).
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _toggleTafsir(st.ref),
            icon: Icon(_tafsir ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text(t.tafsirTitle),
          ),
        ),
        if (_tafsir && _tafsirLoading)
          const YqSkeleton(child: YqSkeletonText(lines: 3))
        else if (_tafsir) ...[
          Text(_tafsirText ?? t.tafsirPlaceholder, style: text.bodyMedium?.copyWith(color: _tafsirText == null ? YqColors.muted : YqColors.ink)),
          if (_tafsirText != null)
            Padding(
              padding: const EdgeInsets.only(top: YqSpace.xs),
              child: Text(
                _tafsirSource == TafsirSource.qf ? t.tafsirSourceQf : t.tafsirAttribution,
                style: text.bodySmall?.copyWith(color: YqColors.goldText),
              ),
            ),
        ],
        const SizedBox(height: YqSpace.l),
        // The player as an orbit: the ring is the timeline (drag around it to seek), the ink pill
        // in its heart plays and pauses.
        Center(
          child: OrbitScrubber(
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
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: c.toggle,
                    child: SizedBox(
                      width: 88,
                      height: 60,
                      child: Icon(st.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: YqColors.goldLight, size: 34),
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
        const SizedBox(height: YqSpace.m),
        Semantics(
          container: true,
          label: t.listenControls,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundIcon(
                tooltip: t.listenRepeatTitle,
                icon: st.repeat == ListenRepeat.ayah ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                active: st.repeat != ListenRepeat.off,
                onTap: () => showRepeatSheet(context, ayahCount: surah.ayahCount),
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
        const SizedBox(height: YqSpace.m),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            YqChip(
              label: t.qsChangeReciter,
              selected: false,
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/quran/reciters');
              },
            ),
            YqChip(label: t.qsSleepTimer, selected: st.sleepOn, onTap: _sleepSheet),
            YqChip(label: t.jumpTitle, selected: false, onTap: () => _jump(quran, locale)),
          ],
        ),
      ],
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

/// A ring that is the track's timeline: progress sweeps with the reading direction and dragging
/// (or tapping) around the ring seeks. For screen readers it is a slider that steps 5 %.
class OrbitScrubber extends StatelessWidget {
  const OrbitScrubber({super.key, required this.value, required this.label, required this.onSeek, required this.child});
  final double value;
  final String label;
  final ValueChanged<double>? onSeek;
  final Widget child;

  static const size = 212.0;

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
                  shadows: [BoxShadow(color: YqColors.ink.withValues(alpha: 0.15), blurRadius: 34, spreadRadius: -8, offset: const Offset(0, 14))],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [YqColors.white.withValues(alpha: 0.9), YqColors.white.withValues(alpha: 0.6)],
                      ),
                      border: Border.all(color: YqColors.white.withValues(alpha: 0.95), width: 1.4),
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
