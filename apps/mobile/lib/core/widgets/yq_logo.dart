import 'package:flutter/material.dart';

/// The Yaqeen logo — always the designer's artwork (assets/brand), never typeset.
/// Regenerate the files with `python3 packages/brand/scripts/generate.py`.
enum YqLogoVariant {
  /// Symbol only: the abstracted «ن» with the gold diamond.
  mark,

  /// Mark above «يقين» + «Yaqeen». Primary lockup — splash, onboarding, about.
  stacked,

  /// Mark beside the bilingual wordmark — headers.
  horizontal,

  /// Arabic-only horizontal lockup.
  arabic,
}

enum YqLogoTone {
  /// Navy logo for light backgrounds.
  onLight,

  /// White logo for the brand gradient / navy.
  onDark,
}

class YqLogo extends StatelessWidget {
  const YqLogo({
    super.key,
    this.variant = YqLogoVariant.stacked,
    this.tone = YqLogoTone.onLight,
    this.width,
    this.height,
  });

  final YqLogoVariant variant;
  final YqLogoTone tone;
  final double? width;
  final double? height;

  /// Minimum widths from the brand guide.
  static const minMarkWidth = 24.0;
  static const minLockupWidth = 96.0;

  String get asset {
    final dark = tone == YqLogoTone.onDark;
    return switch (variant) {
      YqLogoVariant.mark => dark ? 'assets/brand/mark-white.png' : 'assets/brand/mark-navy.png',
      YqLogoVariant.stacked => dark ? 'assets/brand/lockup-stacked-white.png' : 'assets/brand/lockup-stacked-navy.png',
      // Only the navy horizontal lockup is bundled; on dark use the Arabic white lockup.
      YqLogoVariant.horizontal => dark ? 'assets/brand/lockup-ar-horizontal-white.png' : 'assets/brand/lockup-horizontal-navy.png',
      YqLogoVariant.arabic => dark ? 'assets/brand/lockup-ar-horizontal-white.png' : 'assets/brand/lockup-ar-horizontal-navy.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    final min = variant == YqLogoVariant.mark ? minMarkWidth : minLockupWidth;
    final w = width == null ? null : (width! < min ? min : width);
    return Semantics(
      label: 'يقين Yaqeen',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          asset,
          width: w,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          // Decode at the drawn size (the masters are ~900 px wide) — less memory, faster first paint.
          cacheWidth: w == null ? null : (w * MediaQuery.devicePixelRatioOf(context)).ceil(),
        ),
      ),
    );
  }
}
