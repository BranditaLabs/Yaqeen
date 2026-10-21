import 'dart:ui' show Color;

import 'package:flutter/animation.dart';

/// Brand colours — Yaqeen Brand Identity 2026 (packages/design-tokens/tokens.json is the source).
/// Content screens stay porcelain; the brand gradient is for the splash, app icon and a few premium surfaces.
abstract final class YqColors {
  static const lapis = Color(0xFF1F3F94);
  static const royal = Color(0xFF2A52B8);
  static const midnight = Color(0xFF0A1530);
  static const ink = Color(0xFF0A1530); // = midnight, the logo navy
  static const navy = Color(0xFF10214D);
  static const muted = Color(0xFF56637F);
  static const porcelain = Color(0xFFF3F6FB);
  static const ice = Color(0xFFE9EFF9);
  static const mist = Color(0xFFC8D5EC);
  static const sky = Color(0xFF8FB0E0);
  static const line = Color(0xFFDCE4F2);
  static const gold = Color(0xFFC6A867);
  static const goldText = Color(0xFF7C6127);
  static const goldDeep = Color(0xFF4A3C17);
  static const goldLight = Color(0xFFE9D49E);
  static const cream = Color(0xFFFFFBF1);
  static const sand = Color(0xFFF4E8C8);
  static const success = Color(0xFF2E7A55);
  static const error = Color(0xFFB23A48);
  static const white = Color(0xFFFFFFFF);

  // Brand tints (guide p.10)
  static const slate700 = Color(0xFF475064);
  static const slate400 = Color(0xFF858A98);
  static const slate200 = Color(0xFFC2C5CB);
  static const navy600 = Color(0xFF4C597A);
  static const navy400 = Color(0xFF8890A6);
  static const navy200 = Color(0xFFC3C8D3);
  static const lapis500 = Color(0xFF576FAF);
  static const lapis300 = Color(0xFF8F9FCA);
  static const lapis100 = Color(0xFFC7CFE4);
  static const sky400 = Color(0xFFABC4E8);
  static const sky200 = Color(0xFFC7D8F0);
  static const sky100 = Color(0xFFE3EBF7);
  static const gold300 = Color(0xFFD4BE8D);
  static const gold200 = Color(0xFFE3D4B3);
  static const gold100 = Color(0xFFF1E9D9);

  // Mushaf page themes
  static const paperPage = Color(0xFFFFFDF7);
  static const paperInk = Color(0xFF1A1712);
  static const nightPage = Color(0xFF15161A);
  static const nightBg = Color(0xFF0B0C0E);
  static const nightInk = Color(0xFFE9E2D0);
}

abstract final class YqRadii {
  static const pill = 999.0;
  static const card = 24.0;
  static const hero = 30.0;
  static const tile = 20.0;
  static const chip = 14.0;
}

abstract final class YqSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  /// Horizontal page gutter.
  static const gutter = 20.0;

  /// Minimum touch target.
  static const touch = 44.0;
}

abstract final class YqMotion {
  static const ease = Cubic(0.2, 0.7, 0.2, 1);
  static const fast = Duration(milliseconds: 200);
  static const base = Duration(milliseconds: 350);
  static const slow = Duration(milliseconds: 600);
}
