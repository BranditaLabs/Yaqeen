import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_controller.dart';
import '../../../../core/config/remote_config.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/yq_icon.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../recite/presentation/recite_available.dart';
import '../../domain/passage.dart';

/// The layers this build offers: reading and memorising always; listening with `listen`; reciting
/// only with the `recite` flag *and* a model on the device (spec §6.8 ship gate).
final quranModesProvider = Provider.autoDispose<List<QuranMode>>((ref) {
  final config = ref.watch(remoteConfigProvider);
  return [
    QuranMode.read,
    if (config.isOn(Flags.listen)) QuranMode.listen,
    QuranMode.memorise,
    if (ref.watch(reciteEntryProvider)) QuranMode.recite,
  ];
});

String quranModeLabel(AppLocalizations t, QuranMode m) => switch (m) {
      QuranMode.read => t.qsModeRead,
      QuranMode.listen => t.qsModeListen,
      QuranMode.memorise => t.qsModeMemorise,
      QuranMode.recite => t.qsModeRecite,
    };

YqIcons quranModeIcon(QuranMode m) => switch (m) {
      QuranMode.read => YqIcons.quran,
      QuranMode.listen => YqIcons.listen,
      QuranMode.memorise => YqIcons.memorise,
      QuranMode.recite => YqIcons.recite,
    };

/// `QuranModeDock` (spec §5.11): one glass pill (≤ 640 pt, no live blur) with the active layer's
/// strip above the four segments «قراءة · استماع · تحفيظ · تسميع». A lapis thumb glides between
/// segments on the tab dock's spring. When the labels would not fit (1.3× text on a 360-pt phone)
/// the segments become icons, each still named for screen readers. With only «قراءة» left there is
/// no segmented control at all.
class QuranModeDock extends ConsumerWidget {
  const QuranModeDock({super.key, required this.mode, required this.onChanged, required this.strip, this.night = false});

  final QuranMode mode;
  final ValueChanged<QuranMode> onChanged;

  /// The active layer's controls (read: wird + page slider; listen: player; memorise; recite).
  final Widget strip;

  /// Night page: the glass is filled more so labels keep their contrast over the dark page.
  final bool night;

  static const maxWidth = 640.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(quranModesProvider);
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: LiquidGlass(
          radius: YqRadii.card,
          opacity: night ? 0.86 : 0.58,
          padding: const EdgeInsets.fromLTRB(YqSpace.m, YqSpace.m, YqSpace.m, YqSpace.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              strip,
              if (modes.length > 1) ...[
                const SizedBox(height: YqSpace.s),
                ModeSwitch(modes: modes, selected: modes.contains(mode) ? mode : QuranMode.read, onChanged: onChanged),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The segmented switch with a spring thumb. Public for tests.
class ModeSwitch extends StatefulWidget {
  const ModeSwitch({super.key, required this.modes, required this.selected, required this.onChanged});
  final List<QuranMode> modes;
  final QuranMode selected;
  final ValueChanged<QuranMode> onChanged;

  /// Whether the labelled segments fit [width] at the current text size (else icons only).
  static bool labelsFit(BuildContext context, List<String> labels, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    var need = _inset * 2;
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: TextStyle(fontSize: scaler.scale(_labelSize), fontWeight: FontWeight.w700)),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      need += _iconSize + _gap + tp.width + _segmentPad * 2;
      tp.dispose();
    }
    return need <= width;
  }

  static const _inset = 4.0;
  static const _labelSize = 13.0;
  static const _iconSize = 18.0;
  static const _segmentPad = 6.0;
  static const _gap = 4.0;

  @override
  State<ModeSwitch> createState() => _ModeSwitchState();
}

class _ModeSwitchState extends State<ModeSwitch> with SingleTickerProviderStateMixin {
  // The tab dock's spring: a calm, barely-there overshoot.
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.86);
  late final AnimationController _thumb = AnimationController.unbounded(vsync: this, value: _index.toDouble());

  int get _index => widget.modes.indexOf(widget.selected).clamp(0, widget.modes.length - 1);

  @override
  void didUpdateWidget(ModeSwitch old) {
    super.didUpdateWidget(old);
    final target = _index.toDouble();
    if (_thumb.value == target && !_thumb.isAnimating) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _thumb.value = target;
    } else {
      _thumb.animateWith(SpringSimulation(_spring, _thumb.value, target, _thumb.velocity));
    }
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final n = widget.modes.length;
    final labels = [for (final m in widget.modes) quranModeLabel(t, m)];
    return LayoutBuilder(
      builder: (context, box) {
        final iconsOnly = !ModeSwitch.labelsFit(context, labels, box.maxWidth);
        return Container(
          height: YqSpace.touch + ModeSwitch._inset * 2,
          padding: const EdgeInsets.all(ModeSwitch._inset),
          decoration: BoxDecoration(
            color: YqColors.white.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(YqRadii.pill),
            border: Border.all(color: YqColors.white.withValues(alpha: 0.85)),
          ),
          child: LayoutBuilder(
            builder: (context, inner) {
              final slot = inner.maxWidth / n;
              return Stack(
                children: [
                  AnimatedBuilder(
                    animation: _thumb,
                    builder: (context, child) => PositionedDirectional(
                      start: _thumb.value.clamp(0.0, n - 1.0) * slot,
                      top: 0,
                      bottom: 0,
                      width: slot,
                      child: child!,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(YqRadii.pill),
                        color: YqColors.lapis,
                        boxShadow: [BoxShadow(color: YqColors.lapis.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final (i, m) in widget.modes.indexed)
                        SizedBox(
                          width: slot,
                          child: _Segment(
                            mode: m,
                            label: labels[i],
                            active: m == widget.selected,
                            iconsOnly: iconsOnly,
                            onTap: () {
                              if (m == widget.selected) return;
                              HapticFeedback.selectionClick();
                              widget.onChanged(m);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.mode, required this.label, required this.active, required this.iconsOnly, required this.onTap});
  final QuranMode mode;
  final String label;
  final bool active;
  final bool iconsOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? YqColors.white : YqColors.ink;
    final icon = YqIcon(quranModeIcon(mode), size: ModeSwitch._iconSize, tone: active ? YqIconTone.light : YqIconTone.idle);
    final content = iconsOnly
        ? Tooltip(message: label, child: Center(child: icon))
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: ModeSwitch._gap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: ModeSwitch._labelSize, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          );
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: content),
    );
  }
}
