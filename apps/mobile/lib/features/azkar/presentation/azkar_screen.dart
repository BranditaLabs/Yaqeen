import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
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
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(
              title: zikrSetTitle(t, _set),
              actions: [
                GlassIconButton(tooltip: t.azkarSettings, onPressed: _settings, icon: const YqIcon(YqIcons.settings, size: 20)),
              ],
            ),
            children: [
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
              const SizedBox(height: YqSpace.l),
              ...content.when(
                loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 320, radius: YqRadii.hero))],
                error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(contentProvider))],
                data: (lib) => _body(context, t, lib.azkar(_set)),
              ),
            ],
          ),
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
      Text(t.azkarPosition(index + 1, items.length), style: text.labelMedium?.copyWith(color: YqColors.muted)),
      const SizedBox(height: YqSpace.s),
      Semantics(
        button: true,
        label: t.azkarCounterA11y(count, current.repeatCount),
        onTap: onTap,
        excludeSemantics: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onTapDown, not onTap: no gesture-arena delay, so rapid counting never drops a tap.
          onTapDown: (_) => onTap(),
          child: LiquidGlass(
            radius: YqRadii.hero,
            padding: const EdgeInsets.all(YqSpace.xl),
            child: Column(
              children: [
                Text(current.textAr, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: YqText.dua),
                const SizedBox(height: YqSpace.m),
                Text(
                  [if (current.virtue != null && current.virtue!.isNotEmpty) current.virtue!, current.source].join(' · '),
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: YqColors.goldText),
                ),
                const SizedBox(height: YqSpace.xl),
                _Ring(count: count, total: current.repeatCount, label: t.azkarCount(count, current.repeatCount)),
                const SizedBox(height: YqSpace.m),
                AnimatedSwitcher(
                  duration: YqMotion.fast,
                  child: Text(
                    setDone ? t.azkarSetDone : (done ? t.azkarNext : t.azkarTapHint),
                    key: ValueKey('$setDone$done'),
                    style: text.bodySmall?.copyWith(color: done ? YqColors.success : YqColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: YqSpace.xl),
      YqSection(
        title: t.azkarRest,
        child: Column(
          children: [
            for (final i in items)
              YqListRow(
                dense: true,
                title: i.title,
                titleColor: i.id == current.id ? YqColors.lapis : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (day.doneItem(i))
                      const Padding(
                        padding: EdgeInsets.only(left: 4, right: 4),
                        child: Icon(Icons.check_rounded, size: 16, color: YqColors.success),
                      ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(t.azkarCount(day.countOf(i), i.repeatCount), style: YqText.numberSmall),
                    ),
                  ],
                ),
                onTap: () => setState(() => _currentId = i.id),
              ),
          ],
        ),
      ),
    ];
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.count, required this.total, required this.label});
  final int count;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 120,
        child: CustomPaint(
          painter: _RingPainter(total == 0 ? 0 : count / total),
          child: Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(label, style: YqText.numeral.copyWith(fontSize: 22)),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = YqColors.sky100;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = value >= 1 ? YqColors.gold : YqColors.lapis;
    canvas.drawArc(rect.deflate(4), 0, math.pi * 2, false, track);
    canvas.drawArc(rect.deflate(4), -math.pi / 2, math.pi * 2 * value.clamp(0, 1), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
