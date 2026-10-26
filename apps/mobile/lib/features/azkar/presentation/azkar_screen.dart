import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/outer_shadow.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_misbaha.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/data/content_controller.dart';
import '../../content/domain/content_item.dart';
import 'azkar_controller.dart';

String zikrSetTab(AppLocalizations t, ZikrSet s) => switch (s) {
      ZikrSet.morning => t.azkarMorning,
      ZikrSet.evening => t.azkarEvening,
      ZikrSet.afterPrayer => t.azkarAfterPrayer,
      ZikrSet.sleep => t.azkarSleep,
    };

String zikrSetTitle(AppLocalizations t, ZikrSet s) => switch (s) {
      ZikrSet.morning => t.azkarMorning,
      ZikrSet.evening => t.azkarEvening,
      ZikrSet.afterPrayer => t.azkarTitleAfterPrayer,
      ZikrSet.sleep => t.azkarTitleSleep,
    };

/// `16 · Azkar counter` (spec §5.19).
class AzkarScreen extends ConsumerStatefulWidget {
  const AzkarScreen({super.key, this.initial});
  final ZikrSet? initial;

  @override
  ConsumerState<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends ConsumerState<AzkarScreen> {
  late ZikrSet _set = widget.initial ?? _bySunTime();
  String? _currentId;
  Timer? _advance;

  /// Morning until 15:00 local, evening after — a sensible default when opened without a set.
  static ZikrSet _bySunTime() => DateTime.now().hour < 15 ? ZikrSet.morning : ZikrSet.evening;

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  void _settings() {
    final t = AppLocalizations.of(context);
    showYqSheet<void>(
      context,
      builder: (c) => Consumer(
        builder: (c, ref, _) {
          final haptics = ref.watch(settingsProvider.select((s) => s.haptics));
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.azkarSettings, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: YqSpace.l),
              Row(
                children: [
                  Expanded(child: Text(t.azkarHaptics)),
                  YqSwitch(
                    label: t.azkarHaptics,
                    value: haptics,
                    onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(haptics: v), sync: false),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final content = ref.watch(contentProvider);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.xxl,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(
                back: true,
                title: zikrSetTitle(t, _set),
                actions: [
                  GlassIconButton(tooltip: t.azkarSettings, onPressed: _settings, icon: const YqIcon(YqIcons.settings, size: 20)),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              Semantics(
                label: t.azkarKinds,
                child: YqSegmented<ZikrSet>(
                  segments: [for (final s in ZikrSet.values) (s, zikrSetTab(t, s))],
                  selected: _set,
                  onChanged: (s) => setState(() {
                    _set = s;
                    _currentId = null;
                  }),
                ),
              ),
            ],
          ),
        ),
        children: content.when(
          loading: () => [
            const YqSkeleton(
              child: Column(
                children: [
                  YqSkeletonBox(width: 90, height: 12, radius: YqRadii.pill),
                  SizedBox(height: YqSpace.m),
                  YqSkeletonText(lines: 3, lineHeight: 20),
                  SizedBox(height: YqSpace.xl),
                  YqSkeletonBox.circle(220),
                ],
              ),
            ),
          ],
          error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(contentProvider))],
          data: (lib) => _body(context, t, lib.azkar(_set)),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppLocalizations t, List<ContentItem> items) {
    if (items.isEmpty) {
      return [
        LiquidGlass(
          child: YqEmptyState(
            icon: YqIcons.azkar,
            title: t.azkarEmpty,
            hint: t.contentOfflineHint,
            actionLabel: t.retry,
            onAction: () => ref.read(contentProvider.notifier).refresh(),
          ),
        ),
      ];
    }
    final day = ref.watch(azkarControllerProvider);
    final ctl = ref.read(azkarControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final setDone = day.doneSet(items);
    final current =
        items.where((i) => i.id == _currentId).firstOrNull ?? items.firstWhere((i) => !day.doneItem(i), orElse: () => items.last);
    final index = items.indexOf(current);
    final count = day.countOf(current);
    final done = day.doneItem(current);
    // The loop holds up to 33 beads; longer counts go round it again.
    final beads = current.repeatCount.clamp(1, 33);
    final inLoop = done ? beads : count % beads;

    void onTap() {
      if (done) return;
      // Pin the card so a finished zikr stays on screen for the «تقبّل الله» beat before advancing.
      _currentId ??= current.id;
      final finished = ctl.tap(current, set: items, kind: _set);
      if (finished) {
        _advance?.cancel();
        _advance = Timer(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          final next = items.skip(index + 1).where((i) => !ref.read(azkarControllerProvider).doneItem(i)).firstOrNull;
          if (next != null) setState(() => _currentId = next.id);
        });
      }
    }

    return [
      Semantics(
        button: true,
        label: t.azkarCounterA11y(count, current.repeatCount),
        onTap: onTap,
        excludeSemantics: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onTapDown, not onTap: no gesture-arena delay, so rapid counting never drops a tap.
          onTapDown: (_) => onTap(),
          child: Column(
            children: [
              Text(
                t.azkarPosition(index + 1, items.length),
                style: text.labelMedium?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: YqSpace.m),
              LiquidGlass(
                radius: YqRadii.hero,
                padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl, vertical: YqSpace.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(current.textAr, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: YqText.dua),
                    const SizedBox(height: YqSpace.m),
                    Text(
                      [if (current.virtue != null && current.virtue!.isNotEmpty) current.virtue!, current.source].join(' · '),
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: YqColors.goldText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.xl),
              // The misbaha: a bead turns gold with each tap; the count sits in its heart.
              SizedBox.square(
                dimension: 220,
                child: OuterShadow(
                  circle: true,
                  shadows: [
                    BoxShadow(
                      color: done ? const Color(0x59C6A867) : const Color(0x260F1A36),
                      blurRadius: 34,
                      spreadRadius: -8,
                      offset: const Offset(0, 14),
                    ),
                  ],
                  child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: done ? const [YqColors.cream, YqColors.sand] : const [Color(0xE6FFFFFF), Color(0x99FFFFFF)],
                    ),
                    border: Border.all(color: const Color(0xF2FFFFFF), width: 1.4),
                  ),
                  child: RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: KeyedSubtree(
                        key: ValueKey(current.id),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: inLoop.toDouble()),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          builder: (context, v, child) => CustomPaint(painter: MisbahaPainter(counted: v, beads: beads), child: child),
                          child: Center(
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                t.azkarCount(count, current.repeatCount),
                                style: YqMoment.numeral(size: 34, color: done ? YqColors.goldDeep : YqColors.ink),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                ),
              const SizedBox(height: YqSpace.m),
              AnimatedSwitcher(
                duration: YqMotion.fast,
                child: Text(
                  setDone ? t.azkarSetDone : (done ? t.azkarNext : t.azkarTapHint),
                  key: ValueKey('$setDone$done'),
                  style: text.bodySmall?.copyWith(color: done ? YqColors.goldText : YqColors.muted, fontWeight: done ? FontWeight.w700 : null),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: YqSpace.xxl),
      YqHeading(t.azkarRest),
      YqTimeline(
        timeWidth: 0,
        pastIndex: 0,
        stops: [
          for (final i in items)
            YqStop(
              title: i.title,
              done: day.doneItem(i),
              highlight: i.id == current.id && !day.doneItem(i),
              trailing: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(t.azkarCount(day.countOf(i), i.repeatCount), style: YqText.numberSmall),
              ),
              onTap: () => setState(() => _currentId = i.id),
            ),
        ],
      ),
    ];
  }
}
