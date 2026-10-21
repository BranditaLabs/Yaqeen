import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';

/// Light, premium splash — matches canvas › 01 · Splash. Logo mark only (no wordmark, no typed name).
///
/// The mark is split by colour into its navy wings and gold diamond on identical canvases
/// (packages/brand/scripts/generate.py), so the two parts animate separately and recombine exactly.
/// The native splash shows the same navy mark on #F7F9FC, so the hand-off is seamless.
///
/// Timeline (ms): dawn 0–1800 · wings spread 300–1600 · diamond settles 1250–2250 ·
/// glow 1850–3250 then breathes · glint 2300–3800 · verse 2600–4000 · progress 2800–5200 → [next].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.next = '/home', this.hold = const Duration(milliseconds: 3800)});

  final String next;
  final Duration hold;

  /// Mark width: 35% of a 390-pt screen. Aspect ratio from the master artwork.
  static const markWidth = 136.0;
  static const markAspect = 1.599;

  /// Diamond centre inside the mark canvas (fractions), used to anchor the glow.
  static const diamondCenter = Offset(0.493, 0.287);

  static const background = Color(0xFFF7F9FC);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _total = 5200.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500));
  Timer? _timer;
  Timer? _breathStart;

  Animation<double> _seg(double startMs, double endMs, [Curve curve = YqMotion.ease]) =>
      CurvedAnimation(parent: _c, curve: Interval(startMs / _total, endMs / _total, curve: curve));

  late final _dawn = _seg(0, 1800, Curves.easeOut);
  late final _wings = _seg(300, 1600);
  late final _diamond = _seg(1250, 2250);
  late final _glow = _seg(1850, 3250);
  late final _glint = _seg(2300, 3800, Curves.easeInOutCubic);
  late final _verse = _seg(2600, 4000, Curves.easeOut);
  late final _progress = _seg(2800, 5200, Curves.easeInOutCubic);

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward();
      _breathStart = Timer(const Duration(milliseconds: 3300), () {
        if (mounted) _breath.repeat(reverse: true);
      });
    }
    _timer = Timer(widget.hold, () {
      if (mounted) context.go(widget.next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breathStart?.cancel();
    _c.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = SplashScreen.markWidth;
    const h = w / SplashScreen.markAspect;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: SplashScreen.background,
        body: LayoutBuilder(
          builder: (context, box) {
            // Optical centre of the mark at 45% of the screen height.
            final top = box.maxHeight * 0.45 - h / 2;
            return Stack(
              children: [
                Positioned.fill(child: FadeTransition(opacity: _dawn, child: const _Dawn())),
                Positioned(
                  top: top,
                  left: (box.maxWidth - w) / 2,
                  width: w,
                  height: h,
                  child: Semantics(
                    label: 'شعار يقين',
                    image: true,
                    child: ExcludeSemantics(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _Glow(intro: _glow, breath: _breath, width: w, height: h),
                          _Wings(animation: _wings),
                          _Diamond(animation: _diamond),
                          _Glint(animation: _glint),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(left: 32, right: 32, bottom: 112, child: _Verse(animation: _verse)),
                Positioned(left: 0, right: 0, bottom: 64, child: Center(child: _Progress(animation: _progress))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dawn extends StatelessWidget {
  const _Dawn();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.1),
              radius: 0.95,
              colors: [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x5CFFFFFF), Color(0x00FFFFFF)],
              stops: [0, 0.3, 0.62, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x2E8FB0E0), Color(0x00F7F9FC), Color(0x00F7F9FC), Color(0x24C6A867)],
              stops: [0, 0.22, 0.78, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Navy wings spread open from a soft blur.
class _Wings extends StatelessWidget {
  const _Wings({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, child) {
          final t = animation.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - t)),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(0.84 + 0.16 * t, 0.96 + 0.04 * t, 1),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 4 * (1 - t), sigmaY: 4 * (1 - t)),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: Image.asset('assets/brand/splash-wings-navy.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Gold diamond descends into the notch with a gentle overshoot.
class _Diamond extends StatelessWidget {
  const _Diamond({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, child) {
          final t = animation.value;
          final settle = Curves.easeOutBack.transform(t);
          return Opacity(
            opacity: (t * 1.4).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -22 * (1 - settle)),
              child: Transform.scale(
                // Diamond centre (0.493, 0.287) of the canvas in -1..1 alignment space.
                alignment: const Alignment(-0.014, -0.426),
                scale: 0.55 + 0.45 * settle,
                child: child,
              ),
            ),
          );
        },
        child: Image.asset('assets/brand/splash-diamond-gold.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Warm glow that blooms from the diamond, then breathes slowly.
class _Glow extends StatelessWidget {
  const _Glow({required this.intro, required this.breath, required this.width, required this.height});
  final Animation<double> intro;
  final Animation<double> breath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    final cx = width * SplashScreen.diamondCenter.dx;
    final cy = height * SplashScreen.diamondCenter.dy;
    return Positioned(
      left: cx - size / 2,
      top: cy - size / 2,
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: Listenable.merge([intro, breath]),
        builder: (_, child) {
          final t = intro.value;
          final b = Curves.easeInOut.transform(breath.value);
          final introScale = t < 0.45 ? 0.3 + 0.85 * (t / 0.45) : 1.15 - 0.15 * ((t - 0.45) / 0.55);
          final introOpacity = t < 0.45 ? t / 0.45 : 1 - 0.45 * ((t - 0.45) / 0.55);
          final scale = introScale * (1 + 0.08 * b);
          final opacity = (introOpacity + (t >= 1 ? 0.25 * b : 0.0)).clamp(0.0, 1.0);
          return Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: child));
        },
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0x8CE9D49E), Color(0x38E9D49E), Color(0x24E3EBF7), Color(0x00F7F9FC)],
              stops: [0, 0.38, 0.64, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// One light sweep across the whole mark, clipped to its shape.
class _Glint extends StatelessWidget {
  const _Glint({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) {
          final v = animation.value;
          if (v == 0 || v == 1) return const SizedBox.shrink();
          final x = -1.6 + 3.2 * v;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(x - 0.5, -0.4),
              end: Alignment(x + 0.5, 0.4),
              colors: const [Color(0x00FFFFFF), Color(0xF2FFFFFF), Color(0x00FFFFFF)],
              stops: const [0.42, 0.5, 0.58],
            ).createShader(rect),
            child: Image.asset('assets/brand/splash-mark-full.png', fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}

class _Verse extends StatelessWidget {
  const _Verse({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                text: 'وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ',
                children: [TextSpan(text: 'ٱلْيَقِينُ', style: TextStyle(color: YqColors.goldText))],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: YqFonts.quran, fontSize: 18, height: 2, color: Color(0xC70A1530)),
            ),
            SizedBox(height: 4),
            Text('الحِجر · 99', style: TextStyle(fontSize: 11, color: YqColors.slate400)),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: 96,
        height: 2,
        child: ColoredBox(
          color: const Color(0x0F0A1530),
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, __) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: animation.value,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [YqColors.gold, YqColors.gold200])),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
