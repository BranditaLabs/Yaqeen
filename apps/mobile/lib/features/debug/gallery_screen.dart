import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/yq_avatar.dart';
import '../../core/widgets/yq_button.dart';
import '../../core/widgets/yq_countdown.dart';
import '../../core/widgets/yq_icon.dart';
import '../../core/widgets/yq_layout.dart';
import '../../core/widgets/yq_skeleton_mushaf.dart';
import '../../core/widgets/yq_states.dart';
import '../profile/domain/avatar.dart';
import '../profile/domain/level.dart';

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
              const SizedBox(height: YqSpace.m),
              // Working: the label stays (same size) and shimmers — never a spinner.
              YqButton.secondary(label: s('جارٍ الحفظ', 'Saving'), onPressed: () {}, loading: true),
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
                    YqSkeletonOrbs(),
                    SizedBox(height: YqSpace.l),
                    YqSkeletonRows(rows: 2),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              // Avatars: the initial, two presets; then the level ring — lapis, achieved gold, guest.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  YqAvatar(avatar: const InitialAvatar(), size: 48, name: s('أحمد', 'Ahmed')),
                  const YqAvatar(avatar: PresetAvatar('m03'), size: 48),
                  const YqAvatar(avatar: PresetAvatar('f02'), size: 48),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  YqLevelAvatar(
                    avatar: const PresetAvatar('m03'),
                    level: 3,
                    progress: 0.62,
                    size: 64,
                    showLevel: true,
                    levelName: ar ? cardLevels[2].$2 : cardLevels[2].$3,
                  ),
                  YqLevelAvatar(
                    avatar: const PresetAvatar('f02'),
                    level: 6,
                    progress: 1,
                    size: 64,
                    achieved: true,
                    showLevel: true,
                    levelName: ar ? cardLevels[5].$2 : cardLevels[5].$3,
                  ),
                  YqLevelAvatar(
                    avatar: const InitialAvatar(),
                    level: 1,
                    progress: 0,
                    size: 64,
                    ring: false,
                    name: s('ضيف', 'Guest'),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              const YqSkeleton(child: YqSkeletonAvatarRows(rows: 3)),
              const SizedBox(height: YqSpace.l),
              const SizedBox(height: 300, child: YqSkeletonMushafPage(header: true)),
            ],
          ),
        ),
      ),
    );
  }
}
