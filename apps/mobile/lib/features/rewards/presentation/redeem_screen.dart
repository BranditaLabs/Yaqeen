import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/product_analytics.dart';
import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../domain/reward.dart';

final rewardsProvider = FutureProvider.autoDispose((ref) => ref.watch(rewardsRepositoryProvider).list());
final codesProvider = FutureProvider.autoDispose((ref) => ref.watch(rewardsRepositoryProvider).codes());

String redeemErrorCopy(AppLocalizations t, RedeemError e) => switch (e) {
      RedeemError.insufficientPoints => t.redeemErrInsufficient,
      RedeemError.outOfStock => t.redeemErrOutOfStock,
      RedeemError.monthlyLimit => t.redeemErrMonthly,
      RedeemError.storeUnavailable => t.redeemErrStore,
      RedeemError.accountRequired => t.redeemErrAccount,
      RedeemError.offline => t.redeemErrOffline,
      RedeemError.unknown => t.errorGeneric,
    };

/// `20 · Redeem reward` (spec §5.23): choose → confirm → loading → success. Online only.
class RedeemScreen extends ConsumerWidget {
  const RedeemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rewards = ref.watch(rewardsProvider);
    final balance = ref.watch(challengeControllerProvider).valueOrNull?.balance;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        lights: AmbientBackground.goldLights,
        stage: YqStage(
          compact: true,
          gold: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(
                back: true,
                title: t.redeemTitle,
                actions: [TextButton(onPressed: () => context.push('/challenge/redeem/codes'), child: Text(t.myCodes))],
              ),
              if (balance != null) ...[
                const SizedBox(height: YqSpace.l),
                YqMoment(
                  value: Text(
                    YqFormat.number(balance),
                    textDirection: TextDirection.ltr,
                    style: YqMoment.numeral(size: 56, color: YqColors.goldDeep),
                  ),
                  caption: Text(t.redeemBalance(YqFormat.number(balance))),
                ),
              ],
            ],
          ),
        ),
        children: [
          YqHeading(t.redeemChoose),
          ...rewards.when(
            loading: () => [const YqSkeleton(child: YqSkeletonRows(rows: 3, leading: 60, trailing: true))],
            error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(rewardsProvider))],
            data: (list) => [
              for (final r in list) ...[
                _RewardRow(reward: r, balance: balance, locale: locale, onRedeem: () => _confirm(context, ref, r, balance)),
                const SizedBox(height: YqSpace.m),
              ],
            ],
          ),
          const SizedBox(height: YqSpace.s),
          Text(t.redeemNote, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, Reward r, int? balance) async {
    final result = await showYqSheet<Redemption>(context, builder: (_) => _ConfirmSheet(reward: r, balance: balance));
    if (result == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SuccessScreen(reward: r, redemption: result)));
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.reward, required this.balance, required this.locale, required this.onRedeem});
  final Reward reward;
  final int? balance;
  final String locale;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final short = balance == null ? 0 : reward.costPoints - balance!;
    final can = reward.available && short <= 0;
    // The ring fills toward the cost: how close the balance is to this reward.
    final progress = balance == null || reward.costPoints == 0 ? 0.0 : balance! / reward.costPoints;
    return LiquidGlass(
      tone: can ? GlassTone.gold : GlassTone.clear,
      child: Row(
        children: [
          YqRing(
            value: progress,
            gold: true,
            size: 60,
            stroke: 4,
            child: YqIcon(YqIcons.store, size: 24, tone: can ? YqIconTone.gold : YqIconTone.idle),
          ),
          const SizedBox(width: YqSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title(locale), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(t.pointsShort(YqFormat.number(reward.costPoints)), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
                Text(
                  can ? t.redeemAvailable : t.redeemShort(YqFormat.number(short)),
                  style: text.bodySmall?.copyWith(color: can ? YqColors.success : YqColors.muted),
                ),
              ],
            ),
          ),
          YqButton(label: t.redeemCta, expand: false, onPressed: can ? onRedeem : null),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends ConsumerStatefulWidget {
  const _ConfirmSheet({required this.reward, required this.balance});
  final Reward reward;
  final int? balance;

  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  // One key per confirm sheet: retries after a timeout reuse it, so points are never spent twice.
  final _key = Outbox.newEventId();
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(rewardsRepositoryProvider).redeem(widget.reward.id, idempotencyKey: _key);
      // Marketing milestone only; the analytics gate drops it without `ads_measurement` consent.
      await ref.read(analyticsProvider).log(AdEvent.rewardRedeem, {'reward_id': widget.reward.id});
      unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.rewardRedeem));
      ref.invalidate(challengeControllerProvider);
      ref.invalidate(rewardsProvider);
      ref.invalidate(codesProvider);
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'redemption_in_progress' ? t.redeemErrInProgress : redeemErrorCopy(t, redeemErrorFor(e.code)));
    } on OfflineException {
      setState(() => _error = redeemErrorCopy(t, RedeemError.offline));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final r = widget.reward;
    Widget line(String a, String b, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: YqSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(a, style: text.bodyMedium?.copyWith(color: YqColors.muted))),
              Text(b, style: YqText.numberSmall.copyWith(fontSize: 15, color: color ?? YqColors.ink)),
            ],
          ),
        );
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: YqColors.gold),
            const SizedBox(height: YqSpace.l),
            Text(t.redeemLoading, style: text.bodyMedium),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.redeemConfirmTitle, style: text.titleLarge),
        const SizedBox(height: YqSpace.m),
        line(t.redeemReward, r.title(locale)),
        line(t.redeemDeducted, '− ${YqFormat.number(r.costPoints)}', color: YqColors.goldText),
        if (widget.balance != null) line(t.redeemAfter, YqFormat.number(widget.balance! - r.costPoints)),
        if (_error != null) ...[
          const SizedBox(height: YqSpace.m),
          Text(_error!, style: text.bodyMedium?.copyWith(color: YqColors.goldText), textAlign: TextAlign.center),
        ],
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.confirm, onPressed: _go),
        const SizedBox(height: YqSpace.s),
        YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _SuccessScreen extends ConsumerStatefulWidget {
  const _SuccessScreen({required this.reward, required this.redemption});
  final Reward reward;
  final Redemption redemption;

  @override
  ConsumerState<_SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends ConsumerState<_SuccessScreen> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final code = widget.redemption.code;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        lights: AmbientBackground.goldLights,
        bottom: YqSpace.l,
        stage: YqStage(
          gold: true,
          child: Column(
            children: [
              const SizedBox(height: YqSpace.xl),
              const YqRing(value: 1, gold: true, size: 112, stroke: 6, child: Icon(Icons.check_rounded, size: 52, color: YqColors.goldDeep)),
              const SizedBox(height: YqSpace.l),
              YqMoment(
                value: Text(t.redeemSuccess, style: YqMoment.display(context, size: 36)),
                caption: Text(t.redeemSuccessBody(widget.reward.title(locale)), style: text.bodyLarge),
              ),
            ],
          ),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqButton(
              label: t.redeemShop,
              onPressed: () async {
                await ref.read(analyticsProvider).log(AdEvent.storeClick);
                unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.storeClick, {'from': 'redeem'}));
                await ref.read(deviceServicesProvider).openUrl(storeLinkFor(Env.storeUrl, code));
              },
            ),
            const SizedBox(height: YqSpace.s),
            YqButton.secondary(label: t.redeemBack, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        children: [
          LiquidGlass(
            tone: GlassTone.gold,
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.l),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: YqText.numeral.copyWith(fontSize: 26, letterSpacing: 2.5),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    setState(() => _copied = true);
                  },
                  child: Text(_copied ? t.copied : t.copy),
                ),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.s),
          Text(
            t.redeemEmailed(YqFormat.fullDate(widget.redemption.expiresAt.toLocal(), locale)),
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// «أكوادي» — past codes (cached for offline viewing).
class CodesScreen extends ConsumerWidget {
  const CodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final codes = ref.watch(codesProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final now = ref.watch(clockProvider)();
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
            stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.myCodes)),
            children: codes.when(
              loading: () => [const YqSkeleton(child: YqSkeletonRows(rows: 3, leading: 0))],
              error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(codesProvider))],
              data: (list) => list.isEmpty
                  ? [LiquidGlass(child: YqEmptyState(icon: YqIcons.store, title: t.codesEmpty))]
                  : [
                      YqGroup(
                          children: [
                            for (final c in list)
                              YqListRow(
                                title: c.code,
                                subtitle: switch (c.status) {
                                  RedemptionStatus.used => t.codeUsed,
                                  RedemptionStatus.voided => t.codeVoid,
                                  _ when !c.isActive(now) => t.codeExpired,
                                  _ => t.codeActive(YqFormat.fullDate(c.expiresAt.toLocal(), locale)),
                                },
                                trailing: c.isActive(now)
                                    ? IconButton(
                                        tooltip: t.copy,
                                        icon: const Icon(Icons.copy_rounded, size: 18, color: YqColors.lapis),
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: c.code));
                                          if (context.mounted) YqToast.show(context, t.copied);
                                        },
                                      )
                                    : null,
                              ),
                          ],
                      ),
                    ],
            ),
      ),
    );
  }
}
