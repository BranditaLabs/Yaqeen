import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../domain/challenge_models.dart';
import 'challenge_controller.dart';

/// Today's «مهمة اليوم» text (published only), cached for offline.
final dailyTaskProvider = FutureProvider.autoDispose.family<({String ar, String en})?, String>(
  (ref, date) => ref.read(contentRepositoryProvider).dailyTask(date),
);

/// Auto tasks tick themselves from the feature (spec §5.22); tapping one opens where it happens.
bool isAutoTask(TaskKey k) => k == TaskKey.wird || k == TaskKey.morningAzkar || k == TaskKey.eveningAzkar || k == TaskKey.listen;

String? rejectionCopy(AppLocalizations t, String code) => switch (code) {
      'day_closed' || 'not_today' => t.tickDayClosed,
      'outside_qada_window' || 'qada_window_passed' => t.tickQadaPassed,
      'already_completed' => null,
      _ => t.tickFailed,
    };

/// `19 · 365 challenge` (spec §5.22).
class ChallengeScreen extends ConsumerWidget {
  const ChallengeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(challengeControllerProvider);
    final session = ref.watch(sessionProvider);
    final t = AppLocalizations.of(context);

    // Streak milestone reached → celebration (gold shimmer, no confetti).
    ref.listen(challengeControllerProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      final m = before?.nextMilestone;
      if (before != null && after != null && m != null && before.streak < m.days && after.streak >= m.days) {
        showMilestoneSheet(context, m);
      }
    });

    return AmbientBackground(
      lights: AmbientBackground.goldLights,
      child: SafeArea(
        bottom: false,
        child: !session.canEarnPoints
            ? _JoinView(guest: true, onJoin: () => context.push('/onboarding/welcome'))
            : state.when(
                loading: () => const _Skeleton(),
                error: (_, __) => YqErrorState(message: t.errorGeneric, onRetry: () => ref.invalidate(challengeControllerProvider)),
                data: (s) => s.enrolled
                    ? _Enrolled(summary: s)
                    : _JoinView(guest: false, onJoin: () => ref.read(challengeControllerProvider.notifier).enroll()),
              ),
      ),
    );
  }
}

Future<void> showMilestoneSheet(BuildContext context, Milestone m) {
  final t = AppLocalizations.of(context);
  return showYqSheet<void>(
    context,
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _GoldDiamond()),
        const SizedBox(height: YqSpace.l),
        Text(t.milestoneTitle, textAlign: TextAlign.center, style: YqText.display.copyWith(fontSize: 30)),
        const SizedBox(height: YqSpace.s),
        Text(
          t.milestoneBody(m.days, YqFormat.number(m.points)),
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.titleMedium?.copyWith(color: YqColors.goldText),
        ),
        const SizedBox(height: YqSpace.xl),
        YqButton(label: t.milestoneOk, onPressed: () => Navigator.of(c).pop()),
      ],
    ),
  );
}

/// A plain rotated square with a slow shimmer — the brand's only celebration mark.
class _GoldDiamond extends StatefulWidget {
  const _GoldDiamond();
  @override
  State<_GoldDiamond> createState() => _GoldDiamondState();
}

class _GoldDiamondState extends State<_GoldDiamond> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * _c.value, -1),
                end: Alignment(1 + 2 * _c.value, 1),
                colors: const [YqColors.gold, YqColors.goldLight, YqColors.gold],
              ),
            ),
          ),
        ),
      );
}

class _Enrolled extends ConsumerWidget {
  const _Enrolled({required this.summary});
  final ChallengeSummary summary;

  Future<void> _onTask(BuildContext context, WidgetRef ref, ChallengeTask task, bool done) async {
    if (done) return;
    if (isAutoTask(task.key)) {
      final last = await ref.read(readingRepositoryProvider).lastRead();
      if (!context.mounted) return;
      switch (task.key) {
        case TaskKey.wird:
          context.push('/quran/read/${last?.page ?? 1}');
        case TaskKey.morningAzkar:
          context.push('/home/azkar?set=morning');
        case TaskKey.eveningAzkar:
          context.push('/home/azkar?set=evening');
        case TaskKey.listen:
          context.push('/quran/listen/${last?.surah ?? 1}');
        default:
      }
      return;
    }
    final t = AppLocalizations.of(context);
    final code = await ref.read(challengeControllerProvider.notifier).complete(task.key);
    if (code != null && context.mounted) {
      final msg = rejectionCopy(t, code);
      if (msg != null) YqToast.show(context, msg);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(remoteConfigProvider);
    final done = summary.today?.completed ?? const <TaskKey>{};
    final total = summary.tasks.fold<int>(0, (n, x) => n + x.points);
    final earned = summary.today?.points ?? 0;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final dailyTask = summary.today == null ? null : ref.watch(dailyTaskProvider(summary.today!.date)).valueOrNull;

    return RefreshIndicator.adaptive(
      onRefresh: () => ref.refresh(challengeControllerProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.l, YqSpace.gutter, 140),
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text(t.challengeTitle, style: YqText.display.copyWith(fontSize: 30)))),
              GlassIconButton(
                tooltip: t.challengeCalendar,
                onPressed: () => context.push('/challenge/calendar'),
                icon: const YqIcon(YqIcons.calendar, size: 20),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          LiquidGlass(
            tone: GlassTone.gold,
            radius: YqRadii.hero,
            padding: const EdgeInsets.all(YqSpace.xl),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 96,
                  child: CustomPaint(
                    painter: _DayRing(summary.progress),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(YqFormat.number(summary.dayNumber), style: YqText.numeral.copyWith(fontSize: 26)),
                          Text(YqFormat.number(summary.challengeLengthDays), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: YqSpace.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.dayOfTotal(summary.dayNumber, summary.challengeLengthDays),
                        style: text.bodySmall?.copyWith(color: YqColors.goldDeep),
                      ),
                      Text(t.challengePointsLabel(YqFormat.number(summary.balance)), style: YqText.numeral.copyWith(fontSize: 24)),
                      const SizedBox(height: YqSpace.xs),
                      Text(t.streakDays(summary.streak), style: text.bodySmall),
                      Text(t.challengeQadaDays(summary.qadaDays), style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.xl),
          Row(
            children: [
              Expanded(child: Text(t.todayTasks, style: text.titleMedium)),
              Text(t.challengeTodayProgress(earned, total), style: YqText.numberSmall.copyWith(color: YqColors.lapis)),
            ],
          ),
          const SizedBox(height: YqSpace.s),
          YqProgressLine(value: total == 0 ? 0 : (earned / total).clamp(0, 1), height: 5),
          const SizedBox(height: YqSpace.m),
          for (final task in summary.tasks) ...[
            _TaskTile(
              task: task,
              label: isAr ? task.labelAr : task.labelEn,
              subtitle: switch (task.key) {
                TaskKey.fivePrayers => t.taskPrivate,
                TaskKey.dailyTask => dailyTask == null ? null : (isAr ? dailyTask.ar : dailyTask.en),
                _ when isAutoTask(task.key) => t.taskAuto,
                _ => null,
              },
              done: done.contains(task.key),
              onTap: () => _onTask(context, ref, task, done.contains(task.key)),
            ),
            const SizedBox(height: YqSpace.s),
          ],
          if (summary.nextMilestone case final m?) ...[
            const SizedBox(height: YqSpace.s),
            Text(t.nextMilestone(m.days, YqFormat.number(m.points)), style: text.bodySmall?.copyWith(color: YqColors.goldText)),
          ],
          const SizedBox(height: YqSpace.xl),
          LiquidGlass(
            tone: GlassTone.gold,
            child: Row(
              children: [
                const YqIcon(YqIcons.store, tone: YqIconTone.gold),
                const SizedBox(width: YqSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.redeemCardTitle, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (config.cheapestRewardPoints case final p?)
                        Text(t.redeemCardHint(YqFormat.number(p)), style: text.bodySmall?.copyWith(color: YqColors.goldDeep)),
                    ],
                  ),
                ),
                YqButton(label: t.redeemCta, expand: false, onPressed: () => context.push('/challenge/redeem')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRing extends CustomPainter {
  _DayRing(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(5);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0x297C6127),
    );
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = YqColors.gold,
    );
  }

  @override
  bool shouldRepaint(_DayRing old) => old.value != value;
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.label, required this.done, required this.onTap, this.subtitle});
  final ChallengeTask task;
  final String label;
  final String? subtitle;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auto = isAutoTask(task.key);
    return Semantics(
      button: !done,
      checked: done,
      label: [label, if (subtitle != null) subtitle!, t.pointsPlus(YqFormat.number(task.points))].join('، '),
      excludeSemantics: true,
      child: GlassTap(
        onTap: done ? null : onTap,
        child: LiquidGlass(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
          child: Row(
            children: [
              AnimatedContainer(
                duration: YqMotion.base,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? YqColors.lapis : Colors.transparent,
                  border: Border.all(color: done ? YqColors.lapis : YqColors.mist, width: 1.6),
                ),
                child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: done ? YqColors.muted : YqColors.ink)),
                    if (subtitle != null)
                      Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Text(t.pointsPlus(YqFormat.number(task.points)), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
              if (auto && !done) ...[
                const SizedBox(width: YqSpace.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: YqColors.muted,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinView extends StatelessWidget {
  const _JoinView({required this.onJoin, required this.guest});
  final VoidCallback onJoin;
  final bool guest;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(YqSpace.xxl),
        child: LiquidGlass(
          tone: GlassTone.gold,
          padding: const EdgeInsets.all(YqSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.challengeTitle, style: YqText.display.copyWith(fontSize: 30), textAlign: TextAlign.center),
              const SizedBox(height: YqSpace.m),
              Text(
                guest ? t.challengeSignIn : t.joinChallengeHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: YqSpace.xl),
              YqButton(label: guest ? t.signIn : t.joinChallenge, onPressed: onJoin),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.l, YqSpace.gutter, 140),
        children: const [
          YqSkeleton(child: YqSkeletonBox(width: 200, height: 30)),
          SizedBox(height: YqSpace.l),
          YqSkeleton(child: YqSkeletonBox(height: 140, radius: YqRadii.hero)),
          SizedBox(height: YqSpace.l),
          YqSkeleton(child: YqSkeletonBox(height: 56)),
          SizedBox(height: YqSpace.s),
          YqSkeleton(child: YqSkeletonBox(height: 56)),
        ],
      );
}
