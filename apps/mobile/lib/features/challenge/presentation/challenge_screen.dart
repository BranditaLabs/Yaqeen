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
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_timeline.dart';
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

    if (!session.canEarnPoints) return _JoinView(guest: true, onJoin: () => context.push('/onboarding/welcome'));
    return state.when(
      loading: () => const _Skeleton(),
      error: (_, __) => YqCanvas(
        lights: AmbientBackground.goldLights,
        stage: YqStage(gold: true, child: YqStageBar(title: t.challengeTitle, large: true)),
        children: [YqErrorState(message: t.errorGeneric, onRetry: () => ref.invalidate(challengeControllerProvider))],
      ),
      data: (s) => s.enrolled
          ? _Enrolled(summary: s)
          : _JoinView(guest: false, onJoin: () => ref.read(challengeControllerProvider.notifier).enroll()),
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

    final m = summary.nextMilestone;
    return YqCanvas(
      lights: AmbientBackground.goldLights,
      onRefresh: () => ref.refresh(challengeControllerProvider.future),
      stage: YqStage(
        gold: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqStageBar(
              title: t.challengeTitle,
              large: true,
              actions: [
                GlassIconButton(
                  tooltip: t.challengeCalendar,
                  onPressed: () => context.push('/challenge/calendar'),
                  icon: const YqIcon(YqIcons.calendar, size: 20),
                ),
              ],
            ),
            const SizedBox(height: YqSpace.xl),
            Semantics(
              container: true,
              excludeSemantics: true,
              label:
                  '${t.dayOfTotal(summary.dayNumber, summary.challengeLengthDays)}، ${t.challengePointsLabel(YqFormat.number(summary.balance))}',
              child: Column(
                children: [
                  YqRing(
                    value: summary.progress,
                    gold: true,
                    size: 176,
                    stroke: 9,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          YqFormat.number(summary.dayNumber),
                          textDirection: TextDirection.ltr,
                          style: YqMoment.numeral(size: 58),
                        ),
                        Text(
                          t.dayOfTotal(summary.dayNumber, summary.challengeLengthDays),
                          style: text.bodySmall?.copyWith(color: YqColors.goldDeep),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: YqSpace.m),
                  Text(
                    t.challengePointsLabel(YqFormat.number(summary.balance)),
                    style: YqMoment.numeral(size: 30, color: YqColors.goldDeep).copyWith(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      children: [
        YqOrbRow(
          orbs: [
            YqOrb(
              title: t.todayTasks,
              status: t.challengeTodayProgress(earned, total),
              glow: total > 0 && earned >= total,
              statusColor: total > 0 && earned >= total ? YqColors.goldText : null,
              disc: YqRing(
                value: total == 0 ? 0 : earned / total,
                size: YqOrb.defaultSize - 12,
                stroke: 5,
                child: Text(
                  '${YqFormat.number(total == 0 ? 0 : (earned * 100 / total).round())}%',
                  textDirection: TextDirection.ltr,
                  style: YqText.numberSmall.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: YqColors.ink),
                ),
              ),
            ),
            YqOrb(
              title: t.challengeStreak,
              status: t.streakDays(summary.streak),
              statusColor: YqColors.goldText,
              disc: YqRing(
                value: m == null || m.days == 0 ? 1 : summary.streak / m.days,
                gold: true,
                size: YqOrb.defaultSize - 12,
                stroke: 5,
                child: const YqIcon(YqIcons.streak, size: 26, tone: YqIconTone.gold),
              ),
            ),
            YqOrb(
              title: t.challengeQada,
              status: t.challengeQadaDays(summary.qadaDays),
              onTap: () => context.push('/challenge/calendar'),
              disc: YqOrb.number(YqFormat.number(summary.qadaDays), size: 30),
            ),
          ],
        ),
        // A broken streak is never shamed or shown as zero loudly (spec §6.9): a gentle way back.
        if (summary.streak == 0 && summary.dayNumber > 1) ...[
          const SizedBox(height: YqSpace.l),
          GlassTap(
            onTap: () => context.push('/challenge/calendar'),
            semanticLabel: t.challengeStreakRestart,
            child: LiquidGlass(
              tone: GlassTone.gold,
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
              child: Row(
                children: [
                  const YqIcon(YqIcons.calendar, size: 20, tone: YqIconTone.gold),
                  const SizedBox(width: YqSpace.m),
                  Expanded(child: Text(t.challengeStreakRestart, style: text.titleSmall?.copyWith(color: YqColors.goldDeep))),
                  const Icon(Icons.chevron_right_rounded, color: YqColors.goldText),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: YqSpace.xxl),
        YqHeading(t.todayTasks),
        YqTimeline(
          timeWidth: 0,
          stops: [
            for (final task in summary.tasks)
              YqStop(
                title: isAr ? task.labelAr : task.labelEn,
                style: StopStyle.pill,
                subtitle: switch (task.key) {
                  TaskKey.fivePrayers => t.taskPrivate,
                  TaskKey.dailyTask => dailyTask == null ? null : (isAr ? dailyTask.ar : dailyTask.en),
                  _ when isAutoTask(task.key) => t.taskAuto,
                  _ => null,
                },
                done: done.contains(task.key),
                highlight: !done.contains(task.key) && task == summary.tasks.firstWhere((x) => !done.contains(x.key), orElse: () => task),
                trailing: Text(
                  t.pointsPlus(YqFormat.number(task.points)),
                  style: YqText.numberSmall.copyWith(color: done.contains(task.key) ? YqColors.muted : YqColors.goldText),
                ),
                onTap: done.contains(task.key) ? null : () => _onTask(context, ref, task, false),
              ),
          ],
        ),
        if (m != null) ...[
          const SizedBox(height: YqSpace.s),
          Text(
            t.nextMilestone(m.days, YqFormat.number(m.points)),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: YqColors.goldText),
          ),
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
    return YqCanvas(
      lights: AmbientBackground.goldLights,
      stage: YqStage(
        gold: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqStageBar(title: t.challengeTitle, large: true),
            const SizedBox(height: YqSpace.xxl),
            const Center(
              child: YqRing(value: 0, gold: true, size: 150, stroke: 9, child: YqIcon(YqIcons.challenge, size: 44, tone: YqIconTone.gold)),
            ),
            const SizedBox(height: YqSpace.xl),
            Text(
              guest ? t.challengeSignIn : t.joinChallengeHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
      children: [YqButton(label: guest ? t.signIn : t.joinChallenge, onPressed: onJoin)],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => const YqCanvas(
        lights: AmbientBackground.goldLights,
        stage: YqStage(
          gold: true,
          child: YqSkeleton(
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: YqSkeletonBox(width: 180, height: 24)),
                ),
                SizedBox(height: YqSpace.xl),
                YqSkeletonBox.circle(176),
                SizedBox(height: YqSpace.m),
                YqSkeletonBox(width: 140, height: 26, radius: YqRadii.pill),
              ],
            ),
          ),
        ),
        children: [
          YqSkeleton(child: YqSkeletonOrbs()),
          SizedBox(height: YqSpace.xxl),
          YqSkeleton(child: YqSkeletonRows(rows: 4, leading: 0, trailing: true)),
        ],
      );
}
