import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/floating_tab_bar.dart';
import '../core/widgets/yq_icon.dart';
import '../features/onboarding/presentation/session_controller.dart';
import '../l10n/gen/app_localizations.dart';

/// Hosts the five tab branches and floats the dock ([FloatingTabBar]) above them.
///
/// The branches see the dock as part of the bottom safe area: `MediaQuery.padding.bottom` under
/// the shell is the dock's clearance, so every scrolling screen inside a tab clears it through
/// [YqInsets.bottom] (or a `SafeArea`) with no per-screen numbers. Full-screen routes on the root
/// navigator (reader, player, recitation, Qibla, sheets) keep the plain system inset.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final name = session.canEarnPoints && (session.displayName?.trim().isNotEmpty ?? false) ? session.displayName!.trim() : t.guestName;
    final media = MediaQuery.of(context);
    final platform = Theme.of(context).platform;
    // The dock steps aside while the keyboard is up (search, notes), like the system tab bars.
    final keyboard = media.viewInsets.bottom > 0;
    final clearance = keyboard ? media.padding.bottom : FloatingTabBar.clearanceFor(platform, media.padding.bottom);
    final reduceMotion = media.disableAnimations;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(bottom: clearance)),
              child: navigationShell,
            ),
          ),
          // Content dissolves softly under the floating dock.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: clearance + YqSpace.xl,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00F3F6FB), Color(0xD9F3F6FB)],
                    stops: [0, 0.75],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: YqSpace.gutter,
            end: YqSpace.gutter,
            bottom: FloatingTabBar.gapFor(platform, media.padding.bottom),
            child: IgnorePointer(
              ignoring: keyboard,
              child: AnimatedSlide(
                offset: keyboard ? const Offset(0, 1.6) : Offset.zero,
                duration: reduceMotion ? Duration.zero : YqMotion.base,
                curve: YqMotion.ease,
                child: AnimatedOpacity(
                  opacity: keyboard ? 0 : 1,
                  duration: reduceMotion ? Duration.zero : YqMotion.fast,
                  child: FloatingTabBar(
                    currentIndex: navigationShell.currentIndex,
                    // Tapping the open tab again returns it to its first screen.
                    onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
                    tabs: [
                      YqTab(icon: YqIcons.home, label: t.tabHome),
                      YqTab(icon: YqIcons.quran, label: t.tabQuran),
                      YqTab(icon: YqIcons.prayer, label: t.tabPrayer),
                      YqTab(icon: YqIcons.challenge, label: t.tabChallenge),
                      YqTab.avatar(initial: String.fromCharCode(name.runes.first), label: t.tabProfile),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab branches kept alive like an IndexedStack, with a short fade-in of the tab being opened.
/// Hidden tabs are offstage with tickers off, so they cost nothing (no layout, paint or timers).
class TabBranches extends StatefulWidget {
  const TabBranches({super.key, required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  State<TabBranches> createState() => _TabBranchesState();
}

class _TabBranchesState extends State<TabBranches> with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);
  late final List<AnimationController> _fades = [
    for (var i = 0; i < widget.children.length; i++)
      AnimationController(vsync: this, duration: _duration, value: i == widget.currentIndex ? 1 : 0),
  ];
  late final List<Animation<double>> _opacity = [for (final c in _fades) CurvedAnimation(parent: c, curve: Curves.easeOut)];
  int? _leaving;

  @override
  void didUpdateWidget(TabBranches old) {
    super.didUpdateWidget(old);
    if (old.currentIndex == widget.currentIndex) return;
    // A switch during a fade: the tab that was leaving goes away now.
    final previous = _leaving;
    if (previous != null && previous != widget.currentIndex) _fades[previous].value = 0;
    // The old tab stays fully painted underneath until the new one has faded in over it.
    _leaving = old.currentIndex;
    _fades[old.currentIndex].value = 1;
    final target = widget.currentIndex;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final incoming = _fades[target];
    if (reduceMotion) {
      incoming.value = 1;
      _finish();
    } else {
      incoming.forward(from: 0).whenComplete(() {
        if (widget.currentIndex == target) _finish(); // only the latest switch finishes
      });
    }
  }

  void _finish() {
    final leaving = _leaving;
    if (leaving == null || leaving == widget.currentIndex || !mounted) return;
    setState(() {
      _fades[leaving].value = 0;
      _leaving = null;
    });
  }

  @override
  void dispose() {
    for (final c in _fades) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = [
      for (var i = 0; i < widget.children.length; i++)
        if (i != widget.currentIndex) i,
      widget.currentIndex, // on top
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in order)
          Offstage(
            key: ValueKey(i),
            offstage: i != widget.currentIndex && i != _leaving,
            child: TickerMode(
              enabled: i == widget.currentIndex,
              child: FadeTransition(opacity: _opacity[i], child: widget.children[i]),
            ),
          ),
      ],
    );
  }
}
