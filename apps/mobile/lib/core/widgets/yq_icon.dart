import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme/tokens.dart';

/// The 20 custom Yaqeen icons, drawn on a 24×24 grid.
enum YqIcons {
  home, quran, listen, prayer, qibla, azkar, dua, challenge, store, profile,
  bookmark, search, adhan, settings, download, location, calendar, streak, play, share,
}

enum YqIconTone { active, idle, gold, light }

/// s = stroke only, f = stroke + soft tint, a = accent stroke, g = accent fill.
enum _K { s, f, a, g }

String _c(double x, double y, double r) => 'M${x - r} ${y}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0z';

final Map<YqIcons, List<(_K, String)>> _paths = {
  YqIcons.home: [(_K.f, 'M5 21V11.5a7 7 0 0 1 14 0V21z'), (_K.s, 'M3 21h18'), (_K.s, 'M10 21v-4.2a2 2 0 0 1 4 0V21'), (_K.a, 'M12 2.5v2')],
  YqIcons.quran: [(_K.f, 'M12 6.5C10 5 7 4.5 4 5v13c3-.5 6 0 8 1.5 2-1.5 5-2 8-1.5V5c-3-.5-6 0-8 1.5z'), (_K.s, 'M12 6.5v13'), (_K.a, 'M7 9.5h2.5M7 12.5h2.5')],
  YqIcons.listen: [(_K.s, 'M4 15.5V12a8 8 0 0 1 16 0v3.5'), (_K.f, 'M4 13.5h3v6H5.5A1.5 1.5 0 0 1 4 18z'), (_K.f, 'M20 13.5h-3v6h1.5a1.5 1.5 0 0 0 1.5-1.5z'), (_K.a, 'M11 14.5v2.5M13 13v5.5')],
  YqIcons.prayer: [(_K.f, 'M19.5 14.5A8 8 0 1 1 9.5 4.5a6.5 6.5 0 0 0 10 10z'), (_K.g, 'M17.5 3.2l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6z')],
  YqIcons.qibla: [(_K.s, _c(12, 13, 8)), (_K.f, 'M12 7.5l2.1 5.5L12 18.5 9.9 13z'), (_K.g, 'M10.8 1.8h2.4v2.4h-2.4z')],
  YqIcons.azkar: [
    (_K.f, _c(6.5, 8, 1.4) + _c(6, 12, 1.4) + _c(7.6, 15.6, 1.4) + _c(10.4, 18, 1.4) + _c(13.6, 18, 1.4) + _c(16.4, 15.6, 1.4) + _c(18, 12, 1.4) + _c(17.5, 8, 1.4)),
    (_K.s, 'M8 6.4Q12 3.4 16 6.4'),
    (_K.a, 'M12 19.6v2.6M10.9 22.2h2.2'),
  ],
  YqIcons.dua: [(_K.f, 'M5 21c0-3.5.2-6.5 1.6-9.4L8.8 7a1.3 1.3 0 0 1 2.3 1.1l-1.2 3.6'), (_K.f, 'M19 21c0-3.5-.2-6.5-1.6-9.4L15.2 7a1.3 1.3 0 0 0-2.3 1.1l1.2 3.6'), (_K.a, 'M12 2.5v2.4M10.8 3.7h2.4')],
  YqIcons.challenge: [(_K.f, 'M12 2.6l9.4 9.4-9.4 9.4L2.6 12z'), (_K.f, 'M5.4 5.4h13.2v13.2H5.4z'), (_K.g, _c(12, 12, 1.9))],
  YqIcons.store: [(_K.f, 'M5 8h14l-1.1 12.5H6.1z'), (_K.s, 'M9 8V6.5a3 3 0 0 1 6 0V8'), (_K.a, 'M9.5 12a2.5 2.5 0 0 0 5 0')],
  YqIcons.profile: [(_K.f, _c(12, 8, 3.6)), (_K.f, 'M4.5 20.5a7.5 7.5 0 0 1 15 0z')],
  YqIcons.bookmark: [(_K.f, 'M6.5 3.5h11v17l-5.5-4-5.5 4z'), (_K.a, 'M9.5 8h5')],
  YqIcons.search: [(_K.f, _c(11, 11, 6.5)), (_K.s, 'M16 16l4.5 4.5'), (_K.a, 'M8.4 9.6a3 3 0 0 1 2.6-1.6')],
  YqIcons.adhan: [(_K.f, 'M6 10a6 6 0 0 1 12 0c0 5.5 2 7 2 7H4s2-1.5 2-7z'), (_K.s, 'M10 20a2 2 0 0 0 4 0'), (_K.a, 'M12 2.5V4')],
  YqIcons.settings: [(_K.s, 'M4 7h9M17 7h3M4 17h3M11 17h9'), (_K.g, _c(15, 7, 2)), (_K.f, _c(9, 17, 2))],
  YqIcons.download: [(_K.s, 'M12 3.5v11'), (_K.s, 'M7.5 10.5L12 15l4.5-4.5'), (_K.f, 'M4.5 15.5v3a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-3'), (_K.a, 'M9.5 18h5')],
  YqIcons.location: [(_K.f, 'M12 21s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12z'), (_K.g, _c(12, 9, 2.3))],
  YqIcons.calendar: [(_K.f, 'M6 5h12a2 2 0 0 1 2 2v11.5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z'), (_K.s, 'M4 10h16M8 3v4M16 3v4'), (_K.g, 'M13.6 12.8a2.7 2.7 0 1 0 0 4.9 2.3 2.3 0 0 1 0-4.9z')],
  YqIcons.streak: [
    (_K.f, 'M12 21.5c-3.9 0-6.5-2.6-6.5-6.2 0-4.3 4-6.3 4.6-10.8 2.7 1.6 4.2 4 4.2 6.2.9-.5 1.6-1.6 1.9-2.7 1.5 1.5 2.3 3.6 2.3 6 0 4-2.7 7.5-6.5 7.5z'),
    (_K.g, 'M12 21.5c-1.6 0-2.8-1.1-2.8-2.7 0-1.8 1.6-2.6 2.2-4.3 1.6 1 2.9 2.5 2.9 4.2 0 1.6-1 2.8-2.3 2.8z'),
  ],
  YqIcons.play: [(_K.f, 'M8 5.5v13l10.5-6.5z')],
  YqIcons.share: [(_K.s, 'M12 15V3.5'), (_K.s, 'M8 7.5l4-4 4 4'), (_K.f, 'M5 11.5v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7'), (_K.a, 'M9.5 17.5h5')],
};

// Parsed once and cached.
final Map<YqIcons, List<(_K, Path)>> _parsed = {};
List<(_K, Path)> _pathsFor(YqIcons icon) =>
    _parsed.putIfAbsent(icon, () => [for (final (k, d) in _paths[icon]!) (k, parseSvgPathData(d))]);

class _Palette {
  const _Palette(this.main, this.tint, this.accent);
  final Color main;
  final Color? tint;
  final Color accent;
}

const _palettes = {
  YqIconTone.active: _Palette(YqColors.lapis, Color(0x241F3F94), YqColors.gold),
  YqIconTone.idle: _Palette(YqColors.muted, null, YqColors.muted),
  YqIconTone.gold: _Palette(YqColors.goldText, Color(0x3DC6A867), YqColors.gold),
  YqIconTone.light: _Palette(YqColors.white, Color(0x2EFFFFFF), YqColors.goldLight),
};

/// Duotone line icon: 1.5 stroke, round caps, soft tint when active and
/// one gold accent. Mirrors nothing in RTL (the glyphs are symmetric or
/// direction-neutral by design).
class YqIcon extends StatelessWidget {
  const YqIcon(this.icon, {super.key, this.size = 24, this.tone = YqIconTone.active, this.semanticLabel});

  final YqIcons icon;
  final double size;
  final YqIconTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painted = CustomPaint(
      size: Size.square(size),
      painter: _YqIconPainter(icon, _palettes[tone]!, size <= 18 ? 1.7 : 1.5),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

class _YqIconPainter extends CustomPainter {
  _YqIconPainter(this.icon, this.palette, this.strokeWidth);

  final YqIcons icon;
  final _Palette palette;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()..style = PaintingStyle.fill;

    for (final (kind, path) in _pathsFor(icon)) {
      switch (kind) {
        case _K.f:
          if (palette.tint != null) canvas.drawPath(path, fill..color = palette.tint!);
          canvas.drawPath(path, stroke..color = palette.main);
        case _K.s:
          canvas.drawPath(path, stroke..color = palette.main);
        case _K.a:
          canvas.drawPath(path, stroke..color = palette.accent);
        case _K.g:
          canvas.drawPath(path, fill..color = palette.accent);
          canvas.drawPath(path, stroke..color = palette.accent);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_YqIconPainter old) =>
      old.icon != icon || old.palette != palette || old.strokeWidth != strokeWidth;
}
