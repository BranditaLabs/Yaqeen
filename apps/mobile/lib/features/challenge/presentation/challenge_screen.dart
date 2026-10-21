import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/challenge_models.dart';
import 'challenge_controller.dart';

/// "365 يوماً من اليقين" — today's tasks, balance, streak. Design: canvas › Challenge.
class ChallengeScreen extends ConsumerWidget {
  const ChallengeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(challengeControllerProvider);

    return AmbientBackground(
      lights: AmbientBackground.goldLights,
      child: SafeArea(
        bottom: false,
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          error: (_, __) => _ErrorView(onRetry: () => ref.invalidate(challengeControllerProvider)),
          data: (s) =>
              s.enrolled ? _Enrolled(summary: s) : _JoinView(onJoin: () => ref.read(challengeControllerProvider.notifier).enroll()),
        ),
      ),
    );
  }
}

class _Enrolled extends ConsumerWidget {
  const _Enrolled({required this.summary});
  final ChallengeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final done = summary.today?.completed ?? const <TaskKey>{};

    return RefreshIndicator.adaptive(
      onRefresh: () => ref.refresh(challengeControllerProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.l, YqSpace.gutter, 140),
        children: [
          Text(t.challengeTitle, style: YqText.display.copyWith(fontSize: 30)),
          const SizedBox(height: YqSpace.xs),
          Text(t.dayOfTotal(summary.dayNumber, summary.challengeLengthDays),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: YqColors.muted),),
          const SizedBox(height: YqSpace.m),
          YqProgressLine(value: summary.progress, color: YqColors.gold),
          const SizedBox(height: YqSpace.xl),
          Row(
            children: [
              Expanded(child: _Stat(label: t.balance, value: YqFormat.number(summary.balance), icon: YqIcons.store)),
              const SizedBox(width: YqSpace.m),
              Expanded(child: _Stat(label: t.streak, value: YqFormat.number(summary.streak), icon: YqIcons.streak)),
            ],
          ),
          if (summary.nextMilestone case final m?) ...[
            const SizedBox(height: YqSpace.m),
            Text(
              t.nextMilestone(m.days, YqFormat.number(m.points)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: YqColors.goldText),
            ),
          ],
          const SizedBox(height: YqSpace.xl),
          Text(t.todayTasks, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: YqSpace.m),
          for (final task in summary.tasks) ...[
            _TaskTile(
              task: task,
              done: done.contains(task.key),
              onTap: () => ref.read(challengeControllerProvider.notifier).complete(task.key),
            ),
            const SizedBox(height: YqSpace.s),
          ],
          const SizedBox(height: YqSpace.l),
          GlassTap(
            onTap: () => context.go('/challenge/redeem'),
            child: LiquidGlass(
              tone: GlassTone.gold,
              child: Row(
                children: [
                  const YqIcon(YqIcons.store, tone: YqIconTone.gold),
                  const SizedBox(width: YqSpace.m),
                  Expanded(child: Text(t.redeemTitle, style: Theme.of(context).textTheme.titleSmall)),
                  const Icon(Icons.chevron_left, color: YqColors.goldText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final YqIcons icon;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      child: Row(
        children: [
          YqIcon(icon, tone: YqIconTone.gold, size: 22),
          const SizedBox(width: YqSpace.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: YqColors.muted)),
              Text(value, style: YqText.numeral.copyWith(fontSize: 24)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.done, required this.onTap});
  final ChallengeTask task;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Semantics(
      button: !done,
      checked: done,
      child: GlassTap(
        onTap: done ? () {} : onTap,
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
                child: Text(
                  isAr ? task.labelAr : task.labelEn,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: done ? YqColors.muted : YqColors.ink),
                ),
              ),
              Text(t.pointsShort(YqFormat.number(task.points)), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinView extends StatelessWidget {
  const _JoinView({required this.onJoin});
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(YqSpace.xxl),
        child: LiquidGlass(
          padding: const EdgeInsets.all(YqSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.challengeTitle, style: YqText.display.copyWith(fontSize: 30), textAlign: TextAlign.center),
              const SizedBox(height: YqSpace.m),
              Text(t.joinChallengeHint, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: YqSpace.xl),
              FilledButton(onPressed: onJoin, child: Text(t.joinChallenge)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.errorGeneric),
          const SizedBox(height: YqSpace.m),
          OutlinedButton(onPressed: onRetry, child: Text(t.retry)),
        ],
      ),
    );
  }
}
