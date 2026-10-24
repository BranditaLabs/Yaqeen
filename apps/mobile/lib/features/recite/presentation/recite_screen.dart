import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/platform/recitation_engine.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../hifz/presentation/hifz_controller.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/reader_screen.dart';
import '../domain/recitation.dart';

enum _Mode { read, listen, recite }

/// `10 · Recitation check (تسميع)` (spec §5.12) — beta behind flag `recite`. Recognition runs on
/// the device; audio never leaves it. Copy says «تنبيه», never «خطأ».
class ReciteScreen extends ConsumerStatefulWidget {
  const ReciteScreen({super.key, required this.surah, this.from, this.to, this.fromHifz = false});
  final int surah;
  final int? from;
  final int? to;
  final bool fromHifz;

  @override
  ConsumerState<ReciteScreen> createState() => _ReciteScreenState();
}

class _ReciteScreenState extends ConsumerState<ReciteScreen> {
  static const _rationaleKey = 'recite.rationaleSeen';
  bool _showAyat = true;
  bool _listening = false;
  bool? _available;
  String _heard = '';
  List<AyahResult> _results = const [];
  StreamSubscription<String>? _sub;
  late final RecitationEngine _engine = ref.read(recitationEngineProvider);

  @override
  void initState() {
    super.initState();
    _engine.isAvailable().then((v) {
      if (mounted) setState(() => _available = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_listening) _engine.stop();
    super.dispose();
  }

  /// The passage: the hifz range, or the ayat of this surah on its first page (keeps alignment light).
  List<(AyahRef, String)> _expected(QuranData q) {
    final s = q.surah(widget.surah);
    final from = (widget.from ?? 1).clamp(1, s.ayahCount);
    var to = widget.to ?? from;
    if (widget.to == null) {
      final page = q.pageOf(AyahRef(s.number, from));
      while (to < s.ayahCount && q.pageOf(AyahRef(s.number, to + 1)) == page) {
        to++;
      }
    }
    to = to.clamp(from, s.ayahCount);
    return [for (var a = from; a <= to; a++) (AyahRef(s.number, a), q.text(AyahRef(s.number, a)))];
  }

  Future<void> _toggle(QuranData q) async {
    final engine = _engine;
    if (_listening) {
      await _sub?.cancel();
      await engine.stop();
      setState(() => _listening = false);
      return;
    }
    final kv = ref.read(kvStoreProvider);
    if (await kv.read(_rationaleKey) == null) {
      if (!mounted) return;
      final ok = await _rationale();
      if (ok != true) return;
      await kv.write(_rationaleKey, '1');
    }
    final expected = _expected(q);
    setState(() {
      _listening = true;
      _heard = '';
      _results = RecitationAligner.align(expected, '');
    });
    _sub = engine.start().listen(
      (transcript) {
        if (!mounted) return;
        setState(() {
          _heard = transcript;
          _results = RecitationAligner.align(expected, transcript);
        });
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  Future<bool?> _rationale() {
    final t = AppLocalizations.of(context);
    return showYqSheet<bool>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mic_none_rounded, size: 40, color: YqColors.lapis),
          const SizedBox(height: YqSpace.m),
          Text(t.reciteMicRationale, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.reciteStart, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final quran = ref.watch(quranDataProvider);
    if (!ref.watch(remoteConfigProvider).isOn(Flags.recite)) {
      // Flag off: the tab doesn't exist — deep links land in the reader instead.
      final q = quran.valueOrNull;
      return ReaderScreen(initialPage: q == null ? 1 : q.surah(widget.surah).startPage);
    }
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: quran.when(
            loading: () => const Center(child: CircularProgressIndicator(color: YqColors.lapis)),
            error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(quranDataProvider)),
            data: (q) => _body(context, t, q),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations t, QuranData q) {
    final text = Theme.of(context).textTheme;
    final expected = _expected(q);
    final first = expected.first.$1;
    final page = q.pageOf(first);
    final results = _results.isEmpty ? RecitationAligner.align(expected, _heard) : _results;
    final recited = RecitationAligner.recitedCount(results);
    final okAyat = results.take(recited).where((r) => r.ok).length;
    final warnings = [for (final r in results.take(recited)) ...r.words.where((w) => w.mark == WordMark.warn)];
    final started = _heard.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: YqPage(
            header: YqTopBar(
              title: q.surah(widget.surah).nameAr,
              subtitle: '${t.quranJuz(q.juzOf(first))} · ${t.quranPageN(page)}',
            ),
            children: [
              YqSegmented<_Mode>(
                segments: [
                  (_Mode.read, t.reciteModeRead),
                  (_Mode.listen, t.reciteModeListen),
                  (_Mode.recite, '${t.reciteModeRecite} · ${t.reciteBeta}'),
                ],
                selected: _Mode.recite,
                onChanged: (m) => switch (m) {
                  _Mode.read => context.pushReplacement('/quran/read/$page'),
                  _Mode.listen => context.pushReplacement('/quran/listen/${widget.surah}?ayah=${first.ayah}'),
                  _Mode.recite => null,
                },
              ),
              const SizedBox(height: YqSpace.m),
              Row(
                children: [
                  Expanded(child: Text(t.reciteShowAyat, style: text.bodyMedium)),
                  YqSwitch(label: t.reciteShowAyat, value: _showAyat, onChanged: (v) => setState(() => _showAyat = v)),
                ],
              ),
              const SizedBox(height: YqSpace.m),
              if (_available == false)
                LiquidGlass(child: YqEmptyState(icon: YqIcons.quran, title: t.reciteUnavailable))
              else
                LiquidGlass(
                  padding: const EdgeInsets.all(YqSpace.l),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final (i, r) in results.indexed)
                            // Memorisation test: ayat stay hidden until recited when «إظهار الآيات» is off.
                            if (_showAyat || i < recited) ...[
                              for (final w in r.words)
                                TextSpan(
                                  text: '${w.word} ',
                                  style: w.mark == WordMark.warn
                                      ? const TextStyle(
                                          decoration: TextDecoration.underline,
                                          decorationColor: YqColors.gold,
                                          decorationThickness: 2,
                                          color: YqColors.goldText,
                                        )
                                      : TextStyle(color: started && w.mark == WordMark.skipped && i < recited ? YqColors.muted : null),
                                ),
                              TextSpan(text: '﴿${YqFormat.toArabicIndic(r.ayah.ayah)}﴾ ', style: const TextStyle(color: YqColors.goldText)),
                            ] else
                              TextSpan(text: '﴿${YqFormat.toArabicIndic(r.ayah.ayah)}﴾ ', style: const TextStyle(color: YqColors.slate200)),
                        ],
                      ),
                      textAlign: TextAlign.justify,
                      style: YqText.quran(size: 24, height: 2.2, color: YqColors.ink),
                    ),
                  ),
                ),
              if (started) ...[
                const SizedBox(height: YqSpace.m),
                Wrap(
                  spacing: YqSpace.s,
                  runSpacing: YqSpace.s,
                  children: [
                    if (okAyat > 0) _ResultChip(label: t.reciteOk(okAyat), color: YqColors.success),
                    for (final w in warnings)
                      _ResultChip(
                        label: t.reciteWarn(w.word),
                        color: YqColors.goldText,
                        onTap: () => context.push('/quran/listen/${w.ayah.surah}?ayah=${w.ayah.ayah}'),
                      ),
                  ],
                ),
                if (widget.fromHifz && !_listening && recited == results.length && warnings.isEmpty) ...[
                  const SizedBox(height: YqSpace.m),
                  YqButton.secondary(
                    label: t.hifzMarkDone,
                    onPressed: () async {
                      await ref.read(hifzControllerProvider.notifier).memoriseToday();
                      if (context.mounted) context.pop();
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
        if (_available != false)
          Padding(
            padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.s, YqSpace.gutter, YqSpace.l),
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: _listening ? t.reciteStop : t.reciteStart,
                  child: GestureDetector(
                    onTap: _available == null ? null : () => _toggle(q),
                    child: AnimatedContainer(
                      duration: YqMotion.base,
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening ? YqColors.lapis : YqColors.ink,
                        boxShadow: [if (_listening) const BoxShadow(color: Color(0x551F3F94), blurRadius: 24, spreadRadius: 4)],
                      ),
                      child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: YqColors.white, size: 34),
                    ),
                  ),
                ),
                const SizedBox(height: YqSpace.s),
                Text(_listening ? t.reciteListening : t.reciteStart, style: text.labelMedium),
                TextButton(
                  onPressed: () => context.push('/quran/listen/${widget.surah}?ayah=${first.ayah}'),
                  child: Text(t.reciteHearReciter),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YqRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
          decoration: BoxDecoration(
            color: const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(YqRadii.pill),
            border: Border.all(color: YqColors.line),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ),
      );
}
