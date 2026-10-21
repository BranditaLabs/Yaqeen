import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
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
      body: AmbientBackground(
        lights: AmbientBackground.goldLights,
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(
              title: t.redeemTitle,
              actions: [
                TextButton(onPressed: () => context.push('/challenge/redeem/codes'), child: Text(t.myCodes)),
              ],
            ),
            children: [
              if (balance != null) ...[
                LiquidGlass(
                  tone: GlassTone.gold,
                  child: Text(t.redeemBalance(YqFormat.number(balance)), style: text.titleMedium),
                ),
                const SizedBox(height: YqSpace.l),
              ],
              Text(t.redeemChoose, style: text.titleMedium),
              const SizedBox(height: YqSpace.m),
              ...rewards.when(
                loading: () => [
                  for (var i = 0; i < 3; i++)
                    const Padding(padding: EdgeInsets.only(bottom: 12), child: YqSkeleton(child: YqSkeletonBox(height: 76))),
                ],
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
        ),
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
    return LiquidGlass(
      child: Row(
        children: [
          const YqIconTile(YqIcons.store, gold: true, size: 44),
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
      body: AmbientBackground(
        lights: AmbientBackground.goldLights,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(YqSpace.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(t.redeemSuccess, textAlign: TextAlign.center, style: YqText.display.copyWith(fontSize: 34)),
                const SizedBox(height: YqSpace.m),
                Text(t.redeemSuccessBody(widget.reward.title(locale)), textAlign: TextAlign.center, style: text.bodyLarge),
                const SizedBox(height: YqSpace.xl),
                LiquidGlass(
                  tone: GlassTone.gold,
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          code,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: YqText.numeral.copyWith(fontSize: 24, letterSpacing: 2),
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
                const Spacer(),
                YqButton(
                  label: t.redeemShop,
                  onPressed: () async {
                    await ref.read(analyticsProvider).log(AdEvent.storeClick);
                    await ref.read(deviceServicesProvider).openUrl(storeLinkFor(Env.storeUrl, code));
                  },
                ),
                const SizedBox(height: YqSpace.s),
                YqButton.secondary(label: t.redeemBack, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
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
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: t.myCodes),
            children: codes.when(
              loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 72))],
              error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(codesProvider))],
              data: (list) => list.isEmpty
                  ? [LiquidGlass(child: YqEmptyState(icon: YqIcons.store, title: t.codesEmpty))]
                  : [
                      LiquidGlass(
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                        child: Column(
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
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
