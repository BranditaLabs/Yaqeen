import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Brand gradient `#0A1530 → #10214D → #1F3F94`, dark at the start.
/// For the splash, app icon and a few premium surfaces only — reading and
/// worship screens stay on porcelain.
abstract final class YqBrand {
  static const gradient = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: [YqColors.midnight, YqColors.navy, YqColors.lapis],
    stops: [0, 0.45, 1],
  );

  /// Same gradient fixed to physical left→right, matching the app icon artwork.
  static const gradientLtr = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [YqColors.midnight, YqColors.navy, YqColors.lapis],
    stops: [0, 0.45, 1],
  );

  /// Brand lines (guide p.4).
  static const taglineAr = 'حيث تبدأ السكينة';
  static const taglineEn = 'Where Peace Begins';
  static const promiseEn = 'Certain in Faith. At Peace in Heart.';
  static const lineAr = 'باليقين تطمئن القلوب';
}
