import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../di/providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'yq_button.dart';
import 'yq_icon.dart';
import 'yq_logo.dart';

/// Image card for sharing an ayah or a dua (spec §5.11, §5.20): porcelain, the text, its source and
/// the brand mark (artwork only — never typeset).
Future<void> showTextShareCard(
  BuildContext context,
  WidgetRef ref, {
  required String text,
  required String reference,
  required String fileName,
  bool quranic = false,
}) async {
  final t = AppLocalizations.of(context);
  final key = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(YqSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: key,
            child: Container(
              padding: const EdgeInsets.fromLTRB(YqSpace.xxl, YqSpace.xxl, YqSpace.xxl, YqSpace.l),
              decoration: BoxDecoration(color: YqColors.porcelain, borderRadius: BorderRadius.circular(YqRadii.card)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: quranic ? YqText.quran(size: 24, color: YqColors.ink) : YqText.dua.copyWith(color: YqColors.ink),
                  ),
                  const SizedBox(height: YqSpace.m),
                  Text(reference, textAlign: TextAlign.center, style: const TextStyle(color: YqColors.goldText, fontSize: 13)),
                  const SizedBox(height: YqSpace.xl),
                  const YqLogo(variant: YqLogoVariant.mark, width: 32),
                ],
              ),
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqButton(
            label: t.share,
            icon: const YqIcon(YqIcons.share, size: 18, tone: YqIconTone.light),
            onPressed: () async {
              final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
              final image = await boundary?.toImage(pixelRatio: 3);
              final png = await image?.toByteData(format: ui.ImageByteFormat.png);
              if (png != null) {
                await ref.read(deviceServicesProvider).sharePng(png.buffer.asUint8List(), fileName: fileName, text: reference);
              }
              if (c.mounted) Navigator.of(c).pop();
            },
          ),
        ],
      ),
    ),
  );
}
