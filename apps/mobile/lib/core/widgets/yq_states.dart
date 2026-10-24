import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
import 'yq_button.dart';
import 'yq_icon.dart';

/// Empty state: idle icon + one-line title + one-line hint + optional action (spec §2.5).
class YqEmptyState extends StatelessWidget {
  const YqEmptyState({super.key, required this.icon, required this.title, this.hint, this.actionLabel, this.onAction});

  final YqIcons icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YqSpace.xxl, horizontal: YqSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(YqRadii.tile)),
            child: YqIcon(icon, size: 28, tone: YqIconTone.idle),
          ),
          const SizedBox(height: YqSpace.l),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (hint != null) ...[const SizedBox(height: YqSpace.xs), Text(hint!, style: text.bodySmall, textAlign: TextAlign.center)],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: YqSpace.l),
            YqButton.secondary(label: actionLabel!, onPressed: onAction, expand: false),
          ],
        ],
      ),
    );
  }
}

/// «تعذّر التحميل. تحقق من الاتصال.» + «إعادة المحاولة» (spec §2.5).
class YqErrorState extends StatelessWidget {
  const YqErrorState({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return YqEmptyState(icon: YqIcons.download, title: message ?? t.errorGeneric, actionLabel: t.retry, onAction: onRetry);
  }
}

/// Thin banner on screens that need the network: «أنت غير متصل · نعمل بما على جهازك».
class YqOfflineBanner extends StatelessWidget {
  const YqOfflineBanner({super.key, required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AnimatedSize(
      duration: YqMotion.base,
      curve: YqMotion.ease,
      child: offline
          ? Padding(
              padding: const EdgeInsets.only(bottom: YqSpace.m),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
                  decoration: BoxDecoration(
                    color: const Color(0xCCFFFFFF),
                    borderRadius: BorderRadius.circular(YqRadii.pill),
                    border: Border.all(color: YqColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: YqColors.gold, shape: BoxShape.circle)),
                      const SizedBox(width: YqSpace.s),
                      Flexible(child: Text(t.offlineBanner, style: const TextStyle(fontSize: 12, color: YqColors.muted))),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Skeleton of the real layout: glass blocks with a 1.2 s shimmer (never a bare spinner on first paint).
class YqSkeleton extends StatefulWidget {
  const YqSkeleton({super.key, required this.child});

  /// Layout made of [YqSkeletonBox]es.
  final Widget child;

  @override
  State<YqSkeleton> createState() => _YqSkeletonState();
}

class _YqSkeletonState extends State<YqSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-1 + 3 * _c.value - 1, 0),
              end: Alignment(-1 + 3 * _c.value, 0),
              colors: const [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
            ).createShader(rect),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class YqSkeletonBox extends StatelessWidget {
  const YqSkeletonBox({super.key, this.width, required this.height, this.radius = YqRadii.chip});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: const Color(0xFFE6ECF6), borderRadius: BorderRadius.circular(radius)),
      );
}

/// Short-lived glass pill message at the bottom (spec §2.5 «حُفظ وسيُزامَن عند الاتصال»).
abstract final class YqToast {
  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(BuildContext context, String message, {Duration duration = const Duration(milliseconds: 2600)}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _remove();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: YqSpace.gutter,
        right: YqSpace.gutter,
        bottom: MediaQuery.paddingOf(context).bottom + 104,
        child: IgnorePointer(
          child: Semantics(
            liveRegion: true,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: YqMotion.base,
              curve: YqMotion.ease,
              builder: (context, v, child) =>
                  Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child)),
              child: Center(
                // 90% opaque: a backdrop blur behind it would be invisible but cost a full blur pass.
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl, vertical: YqSpace.m),
                  decoration: BoxDecoration(color: const Color(0xE60A1530), borderRadius: BorderRadius.circular(YqRadii.pill)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: YqColors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, _remove);
  }

  static void _remove() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

/// Glass bottom sheet with a grabber and 28-pt top radius (spec §2.4 `YqSheet`).
Future<T?> showYqSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x590A1530),
    builder: (context) {
      final sheet = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        // 96% opaque fill: no backdrop blur needed (it would be invisible and cost a full-screen pass).
        child: Container(
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF5FFFFFF), Color(0xEDF3F6FB)]),
            border: Border(top: BorderSide(color: Color(0xE6FFFFFF))),
          ),
          padding: EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, YqSpace.xl + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(color: YqColors.mist, borderRadius: BorderRadius.circular(YqRadii.pill)),
                ),
              ),
              const SizedBox(height: YqSpace.l),
              Flexible(child: scrollable ? SingleChildScrollView(child: builder(context)) : builder(context)),
            ],
          ),
        ),
      );
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: sheet);
    },
  );
}
