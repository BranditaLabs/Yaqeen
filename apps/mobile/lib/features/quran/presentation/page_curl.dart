import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/settings/app_settings.dart';

/// How a page turn is drawn: a real page curl, a slide, or (reduce motion) a quick cross-fade.
enum TurnStyle { curl, slide, fade }

/// Which way a turn goes in mushaf order.
enum TurnDirection { forward, backward }

/// The finger → turn mapping of one drag, pure and unit-tested.
///
/// A turn is the leaf of index i (its front page) folding over the spine to reveal index i + 1.
/// [progress] is how far the leaf has turned: 0 flat, 1 gone. Forward drags start at 0 and grow;
/// backward drags start at 1 (the previous leaf, turned) and shrink.
///
/// RTL (the Arabic mushaf): the spine is on the right, the next page lies to the *left* under the
/// leaf, so a forward turn drags left → right, exactly like turning a printed mushaf.
@immutable
class TurnDrag {
  const TurnDrag({
    required this.direction,
    required this.leafWidth,
    required this.start,
    required this.position,
    this.span = curlSpan,
  });

  /// Drag distance (in leaf widths) for a whole turn — the flap edge then stays near the finger.
  static const curlSpan = 1.6;
  static const slideSpan = 1.0;

  /// Past this share of the turn a release completes it (the flap edge is past the page middle).
  static const completeAt = 0.25;

  /// A fling faster than this (px/s) completes or cancels whatever the progress.
  static const flingVelocity = 450.0;

  final TurnDirection direction;
  final double leafWidth;
  final Offset start;
  final Offset position;
  final double span;

  /// Signed drag along the turn: positive when moving the way the turn goes.
  double get along => direction == TurnDirection.forward ? position.dx - start.dx : start.dx - position.dx;

  double get progress {
    final moved = (along / (leafWidth * span)).clamp(0.0, 1.0);
    return direction == TurnDirection.forward ? moved : 1 - moved;
  }

  TurnDrag moveTo(Offset p) => TurnDrag(direction: direction, leafWidth: leafWidth, start: start, position: p, span: span);

  /// Does a release with horizontal velocity [vx] (px/s, screen x) finish the turn?
  bool completes(double vx) {
    final towards = direction == TurnDirection.forward ? vx : -vx;
    if (towards > flingVelocity) return true;
    if (towards < -flingVelocity) return false;
    final turned = direction == TurnDirection.forward ? progress : 1 - progress;
    return turned > completeAt;
  }

  /// The progress a release settles at.
  double target(double vx) {
    final done = completes(vx);
    return direction == TurnDirection.forward ? (done ? 1 : 0) : (done ? 0 : 1);
  }

  /// [vx] in progress units per second (for the settling spring).
  double progressVelocity(double vx) => vx / (leafWidth * span);

  /// Which way a horizontal drag starting with [dx] goes (RTL mushaf: rightwards = forward).
  static TurnDirection directionOf(double dx) => dx >= 0 ? TurnDirection.forward : TurnDirection.backward;
}

/// The geometry of the fold for a turn [progress] of a leaf (pure; the painter draws from it).
///
/// Planar fold: the leaf's outer corner `c` is carried to `f`; the fold is the perpendicular bisector
/// of c→f. The part of the leaf on c's side is reflected across it (the flap, its back showing); the
/// rest stays flat; what was under the reflected part is revealed.
@immutable
class FoldGeometry {
  const FoldGeometry({required this.leaf, required this.c, required this.f});

  /// [grabY] is where the finger took the page (a corner grab peels from the corner); [lift] is the
  /// finger's vertical travel (tilts the fold). Both fade out at the ends so the leaf lies flat at 0
  /// and leaves the page completely at 1.
  factory FoldGeometry.of({required Rect leaf, required double progress, double grabY = double.nan, double lift = 0}) {
    final h = leaf.height;
    final gy = grabY.isNaN ? leaf.bottom : grabY;
    final cy = gy < leaf.top + h * 0.3
        ? leaf.top
        : gy > leaf.bottom - h * 0.3
            ? leaf.bottom
            : gy;
    final c = Offset(leaf.left, cy);
    final t = progress.clamp(0.0, 1.0);
    // A corner grab lifts the corner a little even without vertical travel: the page peels.
    final cornerLift = cy == leaf.bottom ? -h * 0.08 : (cy == leaf.top ? h * 0.08 : 0.0);
    final tilt = (lift * 0.6 + cornerLift) * math.sin(math.pi * t);
    final f = Offset(leaf.left + 2 * leaf.width * t, cy + tilt);
    return FoldGeometry(leaf: leaf, c: c, f: f);
  }

  final Rect leaf;
  final Offset c;
  final Offset f;

  Offset get mid => Offset((c.dx + f.dx) / 2, (c.dy + f.dy) / 2);

  /// Unit normal of the fold, pointing from c's side (folded) to the flat side.
  Offset get normal {
    final d = f - c;
    final len = d.distance;
    return len < 1e-6 ? const Offset(1, 0) : d / len;
  }

  bool get flat => (f - c).distance < 0.5;

  double side(Offset p) => (p - mid).dx * normal.dx + (p - mid).dy * normal.dy;

  Offset reflect(Offset p) {
    final s = side(p);
    return p - normal * (2 * s);
  }

  List<Offset> get _corners => [leaf.topLeft, leaf.topRight, leaf.bottomRight, leaf.bottomLeft];

  /// The part of the leaf still lying flat (front page visible).
  List<Offset> get front => clipHalfPlane(_corners, (p) => side(p));

  /// The part that has been lifted off, before reflection (what it uncovers).
  List<Offset> get revealed => clipHalfPlane(_corners, (p) => -side(p));

  /// The flap: the lifted part folded over (its back faces up).
  List<Offset> get flap => [for (final p in revealed) reflect(p)];

  /// Canvas transform of the reflection (column-major 4×4).
  Float64List get reflection {
    final n = normal;
    final m = mid;
    final a = 1 - 2 * n.dx * n.dx;
    final b = -2 * n.dx * n.dy;
    final d = 1 - 2 * n.dy * n.dy;
    final k = 2 * (m.dx * n.dx + m.dy * n.dy);
    return Float64List.fromList([a, b, 0, 0, b, d, 0, 0, 0, 0, 1, 0, k * n.dx, k * n.dy, 0, 1]);
  }

  /// Sutherland–Hodgman against one half-plane: keeps points where [f] ≥ 0.
  static List<Offset> clipHalfPlane(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final fa = f(a);
      final fb = f(b);
      if (fa >= 0) out.add(a);
      if ((fa >= 0) != (fb >= 0)) {
        final t = fa / (fa - fb);
        out.add(Offset.lerp(a, b, t)!);
      }
    }
    return out;
  }
}

/// Pages of one turn, as pictures, captured from the live pages when the turn starts.
class TurnImages {
  TurnImages({required this.leafFront, this.leafBack, required this.beneath, required this.leafRect, required this.size});

  /// The turning page and (two-page spread) the page on its back.
  final ui.Image leafFront;
  final ui.Image? leafBack;

  /// What lies flat under / beside the leaf: image → where it is drawn.
  final List<(ui.Image, Rect)> beneath;
  final Rect leafRect;
  final Size size;

  void dispose() {
    leafFront.dispose();
    leafBack?.dispose();
    for (final (img, _) in beneath) {
      img.dispose();
    }
  }
}

/// Draws a turn from [TurnImages]: page curl with a shaded back and soft shadows, a slide, or a fade.
class TurnPainter extends CustomPainter {
  TurnPainter({
    required this.images,
    required this.progress,
    required this.style,
    required this.paper,
    required this.shade,
    this.grabY = double.nan,
    this.lift = 0,
    this.direction = TurnDirection.forward,
  }) : super(repaint: progress);

  final TurnImages images;
  final ValueListenable<double> progress;
  final TurnStyle style;

  /// The page colour (the back of the leaf is paper with the print faintly showing through).
  final Color paper;

  /// Shadow ink (token colour; alpha applied here).
  final Color shade;
  final double grabY;
  final double lift;
  final TurnDirection direction;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.medium;

  void _image(Canvas canvas, ui.Image img, Rect dst, {Paint? paint}) => canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        paint ?? _imagePaint,
      );

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value.clamp(0.0, 1.0);
    final leaf = images.leafRect;
    switch (style) {
      case TurnStyle.fade:
        for (final (img, r) in images.beneath) {
          _image(canvas, img, r);
        }
        _image(canvas, images.leafFront, leaf, paint: Paint()..color = Color.fromRGBO(0, 0, 0, 1 - t));
        if (images.leafBack case final back?) {
          // The back page appears where the leaf lands (the spread's other half).
          final dst = leaf.shift(Offset(leaf.width, 0));
          _image(canvas, back, dst, paint: Paint()..color = Color.fromRGBO(0, 0, 0, t));
        }
      case TurnStyle.slide:
        // The leaf slides off over the spine; the page under it is already there (single page), or
        // the next spread slides in with it.
        final dx = size.width * t;
        canvas.save();
        canvas.clipRect(Offset.zero & size);
        for (final (img, r) in images.beneath) {
          _image(canvas, img, r.shift(Offset(dx - size.width, 0)));
        }
        _image(canvas, images.leafFront, leaf.shift(Offset(dx, 0)));
        canvas.restore();
      case TurnStyle.curl:
        _curl(canvas, size, t, leaf);
    }
  }

  void _curl(Canvas canvas, Size size, double t, Rect leaf) {
    for (final (img, r) in images.beneath) {
      _image(canvas, img, r);
    }
    final g = FoldGeometry.of(leaf: leaf, progress: t, grabY: grabY, lift: lift);
    if (g.flat) {
      _image(canvas, images.leafFront, leaf);
      return;
    }
    final n = g.normal;
    final front = g.front;
    final revealed = g.revealed;
    final flap = g.flap;
    final strength = math.sin(math.pi * t).clamp(0.0, 1.0); // shadows peak mid-turn

    // Shadow the flap casts on the page it uncovered, along the fold.
    if (revealed.length >= 3) {
      final w = 14 + 34 * strength;
      canvas.save();
      canvas.clipPath(_poly(revealed));
      final from = g.mid;
      final to = g.mid - n * w;
      canvas.drawRect(
        leaf,
        Paint()..shader = ui.Gradient.linear(from, to, [shade.withAlpha((70 * strength + 20).round()), shade.withAlpha(0)]),
      );
      canvas.restore();
    }

    // The leaf's flat part.
    if (front.length >= 3) {
      canvas.save();
      canvas.clipPath(_poly(front));
      _image(canvas, images.leafFront, leaf);
      canvas.restore();
    }

    if (flap.length < 3) return;
    final flapPath = _poly(flap);

    // Soft drop shadow of the flap on what lies under it.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      flapPath.shift(n * (3 + 5 * strength)),
      Paint()
        ..color = shade.withAlpha((60 * strength + 10).round())
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * strength),
    );
    canvas.restore();

    // The flap: the back of the leaf.
    canvas.save();
    canvas.clipPath(flapPath);
    canvas.save();
    canvas.transform(g.reflection);
    if (images.leafBack case final back?) {
      // Two-page spread: the back is the next page, drawn the right way round once landed.
      canvas.transform(Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, leaf.left + leaf.right, 0, 0, 1]));
      _image(canvas, back, leaf);
    } else {
      // One page: paper, with the print showing through faintly (mirrored).
      _image(canvas, images.leafFront, leaf);
      canvas.drawRect(leaf, Paint()..color = paper.withAlpha(222));
    }
    canvas.restore();
    // Curvature: darker in the crease, a soft highlight a little way out, the edge settling.
    final edge = g.reflect(g.c);
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          g.mid,
          Offset(g.mid.dx + (edge.dx - g.mid.dx) * 1.0, g.mid.dy + (edge.dy - g.mid.dy) * 1.0),
          [
            shade.withAlpha(46),
            const Color(0x00FFFFFF),
            const Color(0x1FFFFFFF),
            shade.withAlpha(18),
          ],
          [0, 0.18, 0.55, 1],
        ),
    );
    canvas.restore();

    // A hairline where the paper bends.
    final crease = FoldGeometry.clipHalfPlane(flap, (p) => 1 - g.side(p).abs()).toList();
    if (crease.length >= 2) {
      canvas.drawPath(_poly(crease), Paint()..color = shade.withAlpha(30));
    }
  }

  @override
  bool shouldRepaint(TurnPainter old) =>
      old.images != images || old.style != style || old.paper != paper || old.grabY != grabY || old.lift != lift;
}

/// Turns pages under a controller: `next` / `previous` animate a turn, `jumpTo` moves instantly.
class MushafPagerController extends ChangeNotifier {
  _MushafPagerState? _state;
  void next() => _state?._turnBy(TurnDirection.forward);
  void previous() => _state?._turnBy(TurnDirection.backward);
}

/// The reader's pager: one page (or a two-page spread) at a time, turned with a real page curl.
///
/// Live pages of the current index and both neighbours stay built and painted (each in its own
/// RepaintBoundary, the current one on top). When a turn starts, the pages it involves are captured
/// as GPU images (`toImageSync`) and the turn animates those pictures — the page trees are never
/// rebuilt or re-laid out mid-turn. Releases settle with a spring (fling-aware); a completed turn
/// gives a light haptic. RTL: index + 1 lies to the left; dragging left → right turns forward.
class MushafPager extends StatefulWidget {
  const MushafPager({
    super.key,
    required this.count,
    required this.index,
    required this.pagesOf,
    required this.pageBuilder,
    required this.onIndexChanged,
    this.controller,
    this.spread = false,
    this.style = TurnStyle.curl,
    this.enabled = true,
    this.paper = const Color(0xFFFFFFFF),
    this.shade = const Color(0xFF000000),
    this.onTap,
    this.spineBuilder,
  });

  final int count;
  final int index;

  /// Page numbers shown at an index (one, or the spread's two: odd on the right).
  final List<int> Function(int index) pagesOf;
  final Widget Function(BuildContext context, int page) pageBuilder;
  final ValueChanged<int> onIndexChanged;
  final MushafPagerController? controller;
  final bool spread;
  final TurnStyle style;
  final bool enabled;
  final Color paper;
  final Color shade;

  /// A tap on the pager (global position), for chrome / turn zones.
  final ValueChanged<Offset>? onTap;

  /// Drawn over the middle of a spread (the spine's shade).
  final WidgetBuilder? spineBuilder;

  @override
  State<MushafPager> createState() => _MushafPagerState();
}

class _MushafPagerState extends State<MushafPager> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController.unbounded(vsync: this);
  final Map<int, GlobalKey> _keys = {};
  TurnImages? _images;
  TurnDrag? _drag;
  TurnDirection? _turning;
  double _grabY = double.nan;
  double _lift = 0;
  bool _settling = false;

  GlobalKey _key(int page) => _keys.putIfAbsent(page, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(MushafPager old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.index != widget.index || old.spread != widget.spread) _endTurn();
    // Keys of pages far from the ring can go.
    final keep = {
      for (var i = widget.index - 1; i <= widget.index + 1; i++)
        if (i >= 0 && i < widget.count) ...widget.pagesOf(i),
    };
    _keys.removeWhere((p, _) => !keep.contains(p));
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _images?.dispose();
    _anim.dispose();
    super.dispose();
  }

  TurnStyle get _style => MediaQuery.disableAnimationsOf(context) ? TurnStyle.fade : widget.style;

  Rect _slot(int page, Size size) {
    if (!widget.spread) return Offset.zero & size;
    final half = size.width / 2;
    return page.isOdd ? Rect.fromLTWH(half, 0, half, size.height) : Rect.fromLTWH(0, 0, half, size.height);
  }

  ui.Image? _capture(int page) {
    final ro = _keys[page]?.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize) return null;
    try {
      return ro.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } on Object {
      return null;
    }
  }

  /// Captures the turn between [from] and [from] + 1 (the leaf is [from]'s outer page).
  bool _startTurn(int from, TurnDirection dir, Size size) {
    if (from < 0 || from + 1 >= widget.count) return false;
    final a = widget.pagesOf(from);
    final b = widget.pagesOf(from + 1);
    final style = _style;
    final shots = <ui.Image>[];
    ui.Image? grab(int p) {
      final img = _capture(p);
      if (img != null) shots.add(img);
      return img;
    }

    TurnImages? images;
    if (!widget.spread) {
      final front = grab(a.single);
      final under = grab(b.single);
      if (front != null && under != null) {
        images = TurnImages(leafFront: front, beneath: [(under, Offset.zero & size)], leafRect: Offset.zero & size, size: size);
      }
    } else if (style == TurnStyle.slide) {
      // The whole spread slides: the leaf is spread [from] (both pages), the next spread follows it.
      final leftA = a.length > 1 ? grab(a[1]) : null;
      final rightA = grab(a[0]);
      final leftB = b.length > 1 ? grab(b[1]) : null;
      final rightB = grab(b[0]);
      if (rightA != null && rightB != null) {
        final composite = _compose([(rightA, _slot(a[0], size)), if (leftA != null) (leftA, _slot(a[1], size))], size);
        images = TurnImages(
          leafFront: composite,
          beneath: [(rightB, _slot(b[0], size)), if (leftB != null) (leftB, _slot(b[1], size))],
          leafRect: Offset.zero & size,
          size: size,
        );
      }
    } else {
      // Spread: the leaf is [from]'s left page; its back is [from + 1]'s right page.
      final leafPage = a.length > 1 ? a[1] : null;
      final front = leafPage == null ? null : grab(leafPage);
      final back = grab(b[0]);
      final underLeft = b.length > 1 ? grab(b[1]) : null;
      final underRight = grab(a[0]);
      if (front != null && back != null && underRight != null) {
        images = TurnImages(
          leafFront: front,
          leafBack: back,
          beneath: [(underRight, _slot(a[0], size)), if (underLeft != null) (underLeft, _slot(b[1], size))],
          leafRect: _slot(leafPage!, size),
          size: size,
        );
      }
    }
    if (images == null) {
      for (final s in shots) {
        s.dispose();
      }
      return false;
    }
    _images?.dispose();
    setState(() {
      _images = images;
      _turning = dir;
    });
    return true;
  }

  /// Two page pictures into one (a spread sliding as a whole).
  ui.Image _compose(List<(ui.Image, Rect)> parts, Size size) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    for (final (img, r) in parts) {
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r, Paint());
    }
    final pic = rec.endRecording();
    final out = pic.toImageSync((size.width * dpr).round(), (size.height * dpr).round());
    pic.dispose();
    for (final (img, _) in parts) {
      img.dispose();
    }
    return out;
  }

  void _endTurn() {
    _anim.stop();
    _images?.dispose();
    _images = null;
    _drag = null;
    _turning = null;
    _settling = false;
  }

  Size get _size => (context.findRenderObject() as RenderBox?)?.size ?? Size.zero;

  double _leafWidth(Size size) => widget.spread ? size.width / 2 : size.width;

  void _onDragStart(DragStartDetails d) {
    if (!widget.enabled || _settling) return;
    _drag = null;
    _grabY = d.localPosition.dy;
    _lift = 0;
    _pendingStart = d.localPosition;
  }

  Offset? _pendingStart;

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _settling) return;
    final start = _pendingStart;
    if (_drag == null && start != null) {
      final dir = TurnDrag.directionOf(d.localPosition.dx - start.dx);
      final from = dir == TurnDirection.forward ? widget.index : widget.index - 1;
      if (!_startTurn(from, dir, _size)) {
        _pendingStart = null;
        return;
      }
      final style = _style;
      _drag = TurnDrag(
        direction: dir,
        leafWidth: _leafWidth(_size),
        start: start,
        position: d.localPosition,
        span: style == TurnStyle.curl ? TurnDrag.curlSpan : TurnDrag.slideSpan,
      );
    }
    final drag = _drag;
    if (drag == null) return;
    _drag = drag.moveTo(d.localPosition);
    _lift = d.localPosition.dy - _grabY;
    _anim.value = _drag!.progress;
  }

  void _onDragEnd(DragEndDetails d) {
    final drag = _drag;
    _pendingStart = null;
    if (drag == null) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    _settle(drag.direction, drag.target(vx), drag.progressVelocity(vx));
  }

  /// After a completed turn the parent rebuilds with the new index next frame (didUpdateWidget ends
  /// the turn then, with the new page already painted under it); if it doesn't, end it after that frame.
  void _endAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _images != null) setState(_endTurn);
    });
  }

  void _settle(TurnDirection dir, double target, double velocity) {
    _settling = true;
    final completes = dir == TurnDirection.forward ? target == 1 : target == 0;
    final style = _style;
    final Future<void> run;
    if (style == TurnStyle.fade) {
      run = _anim.animateTo(target, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
    } else {
      const spring = SpringDescription(mass: 1, stiffness: 320, damping: 34);
      run = _anim.animateWith(
        SpringSimulation(spring, _anim.value, target, velocity)..tolerance = const Tolerance(distance: 0.002, velocity: 0.05),
      );
    }
    run.whenComplete(() {
      if (!mounted) return;
      if (completes) {
        HapticFeedback.lightImpact();
        final next = dir == TurnDirection.forward ? widget.index + 1 : widget.index - 1;
        widget.onIndexChanged(next);
        _endAfterFrame();
      } else {
        setState(_endTurn);
      }
    });
  }

  /// A programmatic turn (tap zones, keyboard): a corner peel that plays through.
  void _turnBy(TurnDirection dir) {
    if (_settling || _drag != null || !widget.enabled) return;
    final size = _size;
    final from = dir == TurnDirection.forward ? widget.index : widget.index - 1;
    if (from < 0 || from + 1 >= widget.count) return;
    _grabY = size.height * 0.92;
    _lift = -size.height * 0.04;
    if (!_startTurn(from, dir, size)) {
      // No pictures (e.g. not painted yet): move without the animation.
      widget.onIndexChanged(dir == TurnDirection.forward ? widget.index + 1 : widget.index - 1);
      return;
    }
    _anim.value = dir == TurnDirection.forward ? 0 : 1;
    _settling = true;
    final style = _style;
    _anim
        .animateTo(
      dir == TurnDirection.forward ? 1 : 0,
      duration: style == TurnStyle.fade ? const Duration(milliseconds: 140) : const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    )
        .whenComplete(() {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onIndexChanged(dir == TurnDirection.forward ? widget.index + 1 : widget.index - 1);
      _endAfterFrame();
    });
  }

  Widget _entry(int index, {required bool current}) {
    final pages = widget.pagesOf(index);
    Widget page(int p) => RepaintBoundary(key: _key(p), child: widget.pageBuilder(context, p));
    Widget child;
    if (!widget.spread) {
      child = page(pages.single);
    } else {
      child = Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(child: page(pages[0])),
          Expanded(child: pages.length > 1 ? page(pages[1]) : ColoredBox(color: widget.paper)),
        ],
      );
    }
    // Same wrapper shape for every entry, so a neighbour becoming current keeps its elements.
    return IgnorePointer(
      ignoring: !current,
      child: ExcludeSemantics(excluding: !current, child: TickerMode(enabled: current, child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    final ring = [
      if (i - 1 >= 0) i - 1,
      if (i + 1 < widget.count) i + 1,
    ];
    final images = _images;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.enabled ? _onDragStart : null,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: () {
        if (_drag != null && !_settling) _settle(_drag!.direction, _drag!.direction == TurnDirection.forward ? 0 : 1, 0);
      },
      onTapUp: widget.onTap == null ? null : (d) => widget.onTap!(d.globalPosition),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Neighbours first (painted, hidden under the current page), so a turn can capture them.
          for (final j in ring) KeyedSubtree(key: ValueKey('ring-$j'), child: _entry(j, current: false)),
          KeyedSubtree(key: ValueKey('ring-$i'), child: _entry(i, current: true)),
          if (images != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: TurnPainter(
                    images: images,
                    progress: _anim,
                    style: _style,
                    paper: widget.paper,
                    shade: widget.shade,
                    grabY: _grabY,
                    lift: _lift,
                    direction: _turning ?? TurnDirection.forward,
                  ),
                ),
              ),
            ),
          // The spine's shade stays over the pages, also while a leaf turns across it.
          if (widget.spread && widget.spineBuilder != null) IgnorePointer(child: widget.spineBuilder!(context)),
        ],
      ),
    );
  }
}

/// Maps the saved page-turn setting (and reduce motion) to a turn style.
TurnStyle turnStyleOf(PageTurn setting, {required bool reduceMotion}) =>
    reduceMotion ? TurnStyle.fade : (setting == PageTurn.book ? TurnStyle.curl : TurnStyle.slide);
