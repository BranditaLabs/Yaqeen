import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../quran/domain/page_geometry.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/mushaf_page.dart' show MushafColors;
import '../domain/recitation.dart';
import '../domain/recite_progress.dart';

/// What the printed page needs from a «تسميع» attempt.
@immutable
class ReciteView {
  const ReciteView({required this.progress, required this.version, this.showText = false, this.live = true});
  final ReciteProgress progress;

  /// Moves with every change of [progress] (it is mutable).
  final int version;

  /// «إظهار النص»: hidden words show faintly.
  final bool showText;

  /// Live follow; false («سمّع ثم تحقّق»): the marks arrive together and are revealed in a stagger.
  final bool live;

  int? indexAt(AyahRef ref, int position) => progress.indexAt(ref, position);

  @override
  bool operator ==(Object other) =>
      other is ReciteView && identical(other.progress, progress) && other.version == version && other.showText == showText && other.live == live;
  @override
  int get hashCode => Object.hash(identityHashCode(progress), version, showText, live);
}

/// «تسميع» over the printed page (spec §5.12 «النص يظهر بصوتك»): every word of the passage sits in
/// its exact printed place as a soft rounded ink-10 % pill; a recognised word fades and rises into
/// place in lapis that settles to ink; a soft glow waits on the next expected word. Help shows the
/// first letter, then the whole word muted; a different word gets a muted dotted «تنبيه» underline
/// (never «خطأ»), a word the voice passed without it a fainter one.
///
/// Painted on its own layer above the page's glyphs (which skip the passage), so the page itself
/// never repaints while the voice moves. Reduce motion: words simply appear, the glow jumps.
class ReciteLayer extends StatefulWidget {
  const ReciteLayer({super.key, required this.geometry, required this.family, required this.colors, required this.night, required this.view});

  final PageGeometry geometry;

  /// The page's QCF font family.
  final String family;
  final MushafColors colors;
  final bool night;
  final ReciteView view;

  static const reveal = Duration(milliseconds: 420);
  static const glide = Duration(milliseconds: 260);

  /// «سمّع ثم تحقّق»: words revealed one after another, never longer than [staggerMax] in all.
  static const stagger = Duration(milliseconds: 35);
  static const staggerMax = Duration(milliseconds: 1400);

  @override
  State<ReciteLayer> createState() => ReciteLayerState();
}

class ReciteLayerState extends State<ReciteLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _now = Duration.zero;
  final Map<int, Duration> _shownAt = {};
  Rect? _glowFrom;
  Rect? _glowTo;
  Duration _glowAt = Duration.zero;
  bool _reduce = false;

  /// Words revealed so far (tests).
  @visibleForTesting
  Set<int> get shown => _shownAt.keys.toSet();

  /// Whether a reveal or the glow is still moving (tests: settles under reduce motion at once).
  @visibleForTesting
  bool get animating => _ticker.isActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void initState() {
    super.initState();
    _sync(initial: true);
  }

  @override
  void didUpdateWidget(ReciteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view.progress, widget.view.progress)) _shownAt.clear();
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    setState(() => _now = elapsed);
    if (!_pending) _ticker.stop();
  }

  bool get _pending {
    if (_glowTo != null && _glowFrom != null && _now - _glowAt < ReciteLayer.glide) return true;
    return _shownAt.values.any((at) => _now - at < ReciteLayer.reveal);
  }

  Rect? _rectOf(int index) {
    final w = widget.view.progress.words[index];
    for (final l in widget.geometry.lines) {
      for (final b in l.words) {
        if (b.word.ref == w.ayah && b.word.position == w.position && !b.word.isEnd) return b.rect;
      }
    }
    return null;
  }

  void _sync({bool initial = false}) {
    final p = widget.view.progress;
    final settled = initial || _reduce;
    final fresh = <int>[];
    for (var i = 0; i < p.words.length; i++) {
      if (p.revealed(i) && !_shownAt.containsKey(i)) fresh.add(i);
    }
    // A stopped ticker restarts its clock at zero: everything shown before has finished moving.
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _glowAt = const Duration(days: -1);
      for (final k in _shownAt.keys) {
        _shownAt[k] = const Duration(days: -1);
      }
    }
    final staggered = !widget.view.live && fresh.length > 1;
    final step = staggered
        ? Duration(microseconds: math.min(ReciteLayer.stagger.inMicroseconds, ReciteLayer.staggerMax.inMicroseconds ~/ fresh.length))
        : Duration.zero;
    for (final (k, i) in fresh.indexed) {
      _shownAt[i] = settled ? const Duration(days: -1) : _now + step * k;
    }
    final cur = p.current;
    final target = cur == null ? null : _rectOf(cur);
    if (target != _glowTo) {
      _glowFrom = settled || _glowTo == null ? target : _glowRect();
      _glowTo = target;
      _glowAt = _now;
    }
    if (!settled && _pending && !_ticker.isActive) _ticker.start();
  }

  Rect? _glowRect() {
    final from = _glowFrom, to = _glowTo;
    if (to == null) return null;
    if (from == null || _reduce) return to;
    final t = ((_now - _glowAt).inMicroseconds / ReciteLayer.glide.inMicroseconds).clamp(0.0, 1.0);
    return Rect.lerp(from, to, Curves.easeOutCubic.transform(t));
  }

  double _revealT(int i) {
    final at = _shownAt[i];
    if (at == null) return 0;
    if (_reduce) return 1;
    return ((_now - at).inMicroseconds / ReciteLayer.reveal.inMicroseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _RecitePainter(
          geometry: widget.geometry,
          family: widget.family,
          colors: widget.colors,
          night: widget.night,
          view: widget.view,
          revealT: _revealT,
          glow: _glowRect(),
          frame: _now,
        ),
      );
}

class _RecitePainter extends CustomPainter {
  _RecitePainter({
    required this.geometry,
    required this.family,
    required this.colors,
    required this.night,
    required this.view,
    required this.revealT,
    required this.glow,
    required this.frame,
  });

  final PageGeometry geometry;
  final String family;
  final MushafColors colors;
  final bool night;
  final ReciteView view;
  final double Function(int) revealT;
  final Rect? glow;
  final Duration frame;

  static final Map<String, TextPainter> _glyphs = {};

  TextPainter _glyph(String code, Color color, double size) {
    final key = '$family|$code|${color.toARGB32()}|${size.toStringAsFixed(2)}';
    final cached = _glyphs[key];
    if (cached != null) return cached;
    if (_glyphs.length > 1200) {
      for (final p in _glyphs.values) {
        p.dispose();
      }
      _glyphs.clear();
    }
    return _glyphs[key] = TextPainter(
      text: TextSpan(text: code, style: TextStyle(fontFamily: family, fontSize: size, height: 1, color: color)),
      textDirection: TextDirection.rtl,
    )..layout();
  }

  void _paintGlyph(Canvas canvas, String code, Color color, Rect rect, double dy, double opacity) {
    final g = geometry;
    final opaque = color.withValues(alpha: 1);
    final tp = _glyph(code, opaque, g.fontSize);
    final at = Offset(rect.right - tp.width, rect.top + (g.pitch - tp.height) / 2 + g.pitch * 0.08 + dy);
    final alpha = color.a * opacity;
    if (alpha >= 0.999) {
      tp.paint(canvas, at);
    } else {
      canvas.saveLayer(rect.inflate(g.pitch * 0.4), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      tp.paint(canvas, at);
      canvas.restore();
    }
  }

  void _dotted(Canvas canvas, Rect r, Color color, double step) {
    final g = geometry;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final y = r.top + g.pitch * 0.84;
    for (var x = r.left + 1; x < r.right - 1; x += step) {
      canvas.drawLine(Offset(x, y), Offset(x + 1.2, y), paint);
    }
  }

  RRect _pill(Rect r) {
    final g = geometry;
    final box = Rect.fromLTRB(r.left + 1, r.top + g.pitch * 0.22, r.right - 1, r.bottom - g.pitch * 0.16);
    return RRect.fromRectAndRadius(box, Radius.circular(box.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final p = view.progress;
    final ink = colors.ink;
    final pillPaint = Paint()..color = ink.withValues(alpha: 0.10);
    final glowRect = glow;
    if (glowRect != null) {
      final r = _pill(glowRect).inflate(g.pitch * 0.06);
      canvas.drawRRect(
        r,
        Paint()
          ..color = (night ? YqColors.sky : YqColors.lapis).withValues(alpha: night ? 0.22 : 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.pitch * 0.12),
      );
    }
    for (final l in g.lines) {
      for (final b in l.words) {
        if (b.word.isEnd) continue;
        final i = p.indexAt(b.word.ref, b.word.position);
        if (i == null) continue;
        final rect = b.rect;
        final mark = p.markOf(i);
        final hint = p.hintOf(i);
        final t = revealT(i);
        if (!p.revealed(i) || t <= 0) {
          canvas.drawRRect(_pill(rect), pillPaint);
          if (view.showText) _paintGlyph(canvas, b.word.code, ink.withValues(alpha: 0.28), rect, 0, 1);
          if (hint == HintLevel.letter) _letter(canvas, p.words[i].text, rect);
          continue;
        }
        final eased = Curves.easeOutCubic.transform(t);
        if (t < 1) canvas.drawRRect(_pill(rect), Paint()..color = ink.withValues(alpha: 0.10 * (1 - eased)));
        final Color settled = switch (mark) {
          WordMark.ok => ink,
          WordMark.warn => colors.muted,
          WordMark.skipped => colors.muted.withValues(alpha: 0.6),
          null => hint == HintLevel.word ? colors.muted.withValues(alpha: 0.75) : ink,
        };
        final color = mark == WordMark.ok || (mark == null && hint != HintLevel.word)
            ? Color.lerp(night ? YqColors.sky : YqColors.lapis, settled, eased)!
            : settled;
        _paintGlyph(canvas, b.word.code, color, rect, (1 - eased) * g.pitch * 0.12, eased);
        if (mark == WordMark.warn) _dotted(canvas, rect, colors.noteUnderline, 4.5);
        if (mark == WordMark.skipped) _dotted(canvas, rect, colors.muted.withValues(alpha: 0.6), 7);
      }
    }
  }

  /// The first letter (with its marks) at the word's start — help after a pause.
  void _letter(Canvas canvas, String word, Rect rect) {
    final g = geometry;
    final runes = word.runes.toList();
    if (runes.isEmpty) return;
    var end = 1;
    while (end < runes.length && _isMark(runes[end])) {
      end++;
    }
    final letter = String.fromCharCodes(runes.sublist(0, end));
    final tp = TextPainter(
      text: TextSpan(text: letter, style: YqText.quran(size: g.fontSize * 0.92, height: 1, color: colors.muted)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset(rect.right - tp.width - 2, rect.top + (g.pitch - tp.height) / 2));
    tp.dispose();
  }

  static bool _isMark(int c) => (c >= 0x064B && c <= 0x065F) || c == 0x0670 || (c >= 0x06D6 && c <= 0x06ED);

  @override
  bool shouldRepaint(_RecitePainter old) =>
      old.view != view || old.frame != frame || old.glow != glow || old.geometry != geometry || old.colors != colors;
}
