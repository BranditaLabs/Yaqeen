import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/text/arabic.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/audio_models.dart';
import 'downloads_controller.dart';
import 'listen_controller.dart';

String styleLabel(AppLocalizations t, RecitationStyle s) => s == RecitationStyle.mujawwad ? t.styleMujawwad : t.styleMurattal;
String riwayaLabel(AppLocalizations t, String r) => r == 'hafs' ? t.riwayaHafs : r;

/// `12 · Choose a reciter` (spec §5.14).
class RecitersScreen extends ConsumerStatefulWidget {
  const RecitersScreen({super.key});

  @override
  ConsumerState<RecitersScreen> createState() => _RecitersScreenState();
}

class _RecitersScreenState extends ConsumerState<RecitersScreen> {
  final _query = TextEditingController();
  bool _downloadedOnly = false;
  RecitationStyle? _style;
  bool _metered = false;

  @override
  void initState() {
    super.initState();
    ref.read(listenStoreProvider).allowMetered().then((v) {
      if (mounted) setState(() => _metered = v);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Reciter> _filter(List<Reciter> all, Map<String, ReciterDownload> dl) {
    final q = ArabicText.normalize(_query.text);
    return [
      for (final r in all)
        if ((q.isEmpty || ArabicText.normalize('${r.nameAr} ${r.nameEn}').contains(q)) &&
            (!_downloadedOnly || (dl[r.id]?.surahs ?? 0) > 0) &&
            (_style == null || r.style == _style))
          r,
    ];
  }

  Future<void> _confirmDelete(Reciter r) async {
    final t = AppLocalizations.of(context);
    final locale = ref.read(settingsProvider).locale;
    final ok = await showYqSheet<bool>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.reciterDeleteTitle(r.name(locale)), style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.s),
          Text(t.reciterDeleteBody, style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.delete, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
        ],
      ),
    );
    if (ok ?? false) await ref.read(downloadsControllerProvider.notifier).delete(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final reciters = ref.watch(recitersProvider);
    final dl = ref.watch(downloadsControllerProvider);
    final listen = ref.watch(listenControllerProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    ref.listen(recitersProvider, (_, next) {
      final list = next.valueOrNull;
      if (list != null) ref.read(downloadsControllerProvider.notifier).refresh(list);
    });

    final all = reciters.valueOrNull;
    final selected = all?.where((r) => r.id == listen.reciter?.id).firstOrNull;
    final text = Theme.of(context).textTheme;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.pill), borderSide: const BorderSide(color: Color(0xF2FFFFFF)));

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.xxl,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(back: true, title: t.recitersTitle, backLabel: t.recitersBack),
              if (selected != null) ...[
                const SizedBox(height: YqSpace.l),
                // The voice you listen to: its medallion ringed by how much of the mushaf is offline.
                Row(
                  children: [
                    YqRing(
                      value: (dl[selected.id] ?? const ReciterDownload()).fraction,
                      gold: (dl[selected.id] ?? const ReciterDownload()).complete,
                      size: 76,
                      stroke: 4,
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: YqColors.lapis,
                        child: Text(
                          selected.initial(locale),
                          style: const TextStyle(fontFamily: YqFonts.naskh, fontSize: 24, fontWeight: FontWeight.w700, color: YqColors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: YqSpace.l),
                    Expanded(
                      child: YqMoment(
                        center: false,
                        eyebrow: t.reciterSelected,
                        value: Text(selected.name(locale), style: YqMoment.display(context, size: 24)),
                        caption: Text(t.reciterRow(styleLabel(t, selected.style), riwayaLabel(t, selected.riwaya))),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: YqSpace.l),
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: t.recitersSearch,
                  prefixIcon: const Padding(padding: EdgeInsets.all(12), child: YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle)),
                  filled: true,
                  fillColor: const Color(0xCCFFFFFF),
                  border: border,
                  enabledBorder: border,
                ),
              ),
            ],
          ),
        ),
        children: reciters.when(
          loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 300, radius: YqRadii.card))],
          error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(recitersProvider))],
          data: (all) {
            final shown = _filter(all, dl);
            final selectedId = listen.reciter?.id;
            return [
              Wrap(
                spacing: YqSpace.s,
                runSpacing: YqSpace.s,
                children: [
                  YqChip(label: t.recitersAll, selected: !_downloadedOnly, onTap: () => setState(() => _downloadedOnly = false)),
                  YqChip(label: t.recitersDownloaded, selected: _downloadedOnly, onTap: () => setState(() => _downloadedOnly = true)),
                  for (final s in RecitationStyle.values)
                    YqChip(label: styleLabel(t, s), selected: _style == s, onTap: () => setState(() => _style = _style == s ? null : s)),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              if (all.isEmpty)
                LiquidGlass(child: YqEmptyState(icon: YqIcons.listen, title: t.listenNoReciter))
              else if (shown.isEmpty)
                LiquidGlass(child: YqEmptyState(icon: YqIcons.search, title: t.recitersEmpty, hint: t.recitersEmptyHint))
              else
                YqGroup(
                  children: [
                    for (final r in shown)
                      _ReciterRow(
                        reciter: r,
                        locale: locale,
                        selected: r.id == selectedId,
                        sampling: listen.sampleOf == r.id,
                        download: dl[r.id] ?? const ReciterDownload(),
                        onSelect: () async {
                          await ref.read(listenControllerProvider.notifier).stopSample();
                          await ref.read(listenControllerProvider.notifier).selectReciter(r);
                          if (context.mounted && context.canPop()) context.pop();
                        },
                        onSample: () => listen.sampleOf == r.id
                            ? ref.read(listenControllerProvider.notifier).stopSample()
                            : ref.read(listenControllerProvider.notifier).playSample(r),
                        onDownload: () async {
                          final d = dl[r.id] ?? const ReciterDownload();
                          final c = ref.read(downloadsControllerProvider.notifier);
                          if (d.running) {
                            c.cancel(r.id);
                          } else if (d.complete) {
                            await _confirmDelete(r);
                          } else {
                            await c.downloadAll(r);
                            final after = ref.read(downloadsControllerProvider)[r.id];
                            if (context.mounted && after?.error != null) YqToast.show(context, t.reciterWifiOnly);
                          }
                        },
                      ),
                  ],
                ),
              const SizedBox(height: YqSpace.l),
              LiquidGlass(
                padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
                child: Row(
                  children: [
                    Expanded(child: Text(t.useMobileData, style: text.bodyMedium)),
                    YqSwitch(
                      label: t.useMobileData,
                      value: _metered,
                      onChanged: (v) {
                        setState(() => _metered = v);
                        ref.read(listenStoreProvider).setAllowMetered(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.m),
              Text(t.recitersFooter, textAlign: TextAlign.center, style: text.bodySmall),
            ];
          },
        ),
      ),
    );
  }
}

class _ReciterRow extends StatelessWidget {
  const _ReciterRow({
    required this.reciter,
    required this.locale,
    required this.selected,
    required this.sampling,
    required this.download,
    required this.onSelect,
    required this.onSample,
    required this.onDownload,
  });

  final Reciter reciter;
  final String locale;
  final bool selected;
  final bool sampling;
  final ReciterDownload download;
  final VoidCallback onSelect;
  final VoidCallback onSample;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final name = reciter.name(locale);
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(YqRadii.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // The ring shows how much of this voice is on the device (gold when all of it is).
                  YqRing(
                    value: download.fraction,
                    gold: download.complete,
                    size: 52,
                    stroke: 3,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: selected ? YqColors.lapis : YqColors.sky100,
                      child: Text(
                        reciter.initial(locale),
                        style: TextStyle(
                          fontFamily: YqFonts.naskh,
                          fontWeight: FontWeight.w700,
                          color: selected ? YqColors.white : YqColors.lapis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: YqSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(t.reciterRow(styleLabel(t, reciter.style), riwayaLabel(t, reciter.riwaya)), style: text.bodySmall),
                      ],
                    ),
                  ),
                  if (reciter.sampleUrl != null)
                    IconButton(
                      tooltip: sampling ? t.reciterSampleStop : t.reciterSample(name),
                      onPressed: onSample,
                      icon: Icon(sampling ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded, color: YqColors.lapis),
                    ),
                  if (selected) Semantics(label: t.reciterSelected, child: const Icon(Icons.check_circle_rounded, color: YqColors.lapis)),
                ],
              ),
              const SizedBox(height: YqSpace.s),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: download.running
                    ? TextButton.icon(
                        onPressed: onDownload,
                        icon: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(value: download.fraction, strokeWidth: 2.2, color: YqColors.lapis),
                        ),
                        label: Text('${t.reciterDownloading} · ${t.reciterProgress(download.surahs)}'),
                      )
                    : download.complete
                        ? TextButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_done_rounded, color: YqColors.success, size: 18),
                            label: Text(t.reciterDownloaded),
                          )
                        : TextButton.icon(
                            onPressed: onDownload,
                            icon: const YqIcon(YqIcons.download, size: 18),
                            label: Text(
                              download.error != null
                                  ? t.reciterDownloadFailed
                                  : download.surahs > 0
                                      ? '${t.reciterDownloadAll} · ${t.reciterProgress(download.surahs)}'
                                      : t.reciterDownloadAll,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
