import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/yq_button.dart';
import '../../core/widgets/yq_countdown.dart';
import '../../core/widgets/yq_icon.dart';
import '../../core/widgets/yq_layout.dart';
import '../../core/widgets/yq_states.dart';

/// Debug-only component gallery (spec YQ-01): every core widget in one scroll, for design QA
/// and the RTL/LTR golden tests. Strings here are sample copy for QA, not user-facing UI.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key, this.now});

  /// Pinned clock for goldens.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final ar = Directionality.of(context) == TextDirection.rtl;
    String s(String a, String e) => ar ? a : e;
    final clock = now ?? DateTime.now();
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: s('مكوّنات يقين', 'Yaqeen components'), subtitle: 'YQ-01'),
            children: [
              YqButton(label: s('ابدأ رحلتي', 'Start my journey'), onPressed: () {}),
              const SizedBox(height: YqSpace.m),
              YqButton.secondary(label: s('المتابعة باستخدام Google', 'Continue with Google'), onPressed: () {}),
              const SizedBox(height: YqSpace.m),
              Row(
                children: [
                  Expanded(child: YqButton(label: s('تأكيد', 'Confirm'), onPressed: () {}, loading: true)),
                  const SizedBox(width: YqSpace.m),
                  YqButton.text(label: s('المتابعة كضيف', 'Continue as guest'), onPressed: () {}),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: s('الإعدادات', 'Settings'),
                child: Column(
                  children: [
                    YqListRow(
                      leading: const YqIconTile(YqIcons.adhan),
                      title: s('تذكيرات العبادة', 'Worship reminders'),
                      subtitle: s('الأذان والأذكار والورد', 'Adhan, azkar and wird'),
                      trailing: YqSwitch(value: true, onChanged: (_) {}, label: 'switch'),
                    ),
                    const YqDivider(),
                    YqListRow(leading: const YqIconTile(YqIcons.store, gold: true), title: s('أكوادي', 'My codes'), onTap: () {}),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              Wrap(
                spacing: YqSpace.s,
                runSpacing: YqSpace.s,
                children: [
                  YqChip(label: s('صفحة', '1 page'), selected: false, onTap: () {}),
                  YqChip(label: s('صفحتان', '2 pages'), selected: true, onTap: () {}),
                  YqChip(label: s('جزء', '1 juz'), selected: false, onTap: () {}),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              Row(
                children: [
                  YqStepper(step: 2, semanticLabel: s('الخطوة 2 من 4', 'Step 2 of 4')),
                  const Spacer(),
                  YqCountdown(
                    target: clock.add(const Duration(hours: 1, minutes: 24, seconds: 10)),
                    now: () => clock,
                    style: const TextStyle(fontSize: 22),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              YqSegmented<int>(
                segments: [(0, s('السور', 'Surahs')), (1, s('الأجزاء', 'Juz')), (2, s('المحفوظات', 'Saved'))],
                selected: 0,
                onChanged: (_) {},
              ),
              const SizedBox(height: YqSpace.l),
              const YqOfflineBanner(offline: true),
              LiquidGlass(
                child: YqEmptyState(
                  icon: YqIcons.bookmark,
                  title: s('لا توجد علامات بعد', 'No bookmarks yet'),
                  hint: s('اضغط مطولاً على أي آية لحفظ علامة', 'Long-press any ayah to save one'),
                ),
              ),
              const SizedBox(height: YqSpace.l),
              LiquidGlass(child: YqErrorState(onRetry: () {})),
              const SizedBox(height: YqSpace.l),
              const YqSkeleton(
                child: Column(
                  children: [
                    YqSkeletonBox(height: 24, width: 160),
                    SizedBox(height: 8),
                    YqSkeletonBox(height: 90, radius: YqRadii.card),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
