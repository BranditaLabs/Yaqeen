import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../domain/reward.dart';

final rewardsProvider = FutureProvider.autoDispose((ref) => ref.watch(rewardsRepositoryProvider).list());

/// Rewards catalogue → one-time Shopify discount code. Design: canvas › Redeem.
class RedeemScreen extends ConsumerWidget {
  const RedeemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rewards = ref.watch(rewardsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        lights: AmbientBackground.goldLights,
        child: SafeArea(
          child: rewards.when(
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            error: (_, __) => Center(
              child: OutlinedButton(onPressed: () => ref.invalidate(rewardsProvider), child: Text(t.retry)),
            ),
            data: (list) => ListView(
              padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.l, YqSpace.gutter, 140),
              children: [
                Row(
                  children: [
                    const BackButton(),
                    Text(t.redeemTitle, style: YqText.display.copyWith(fontSize: 28)),
                  ],
                ),
                const SizedBox(height: YqSpace.l),
                for (final r in list) ...[
                  _RewardCard(reward: r),
                  const SizedBox(height: YqSpace.m),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardCard extends ConsumerStatefulWidget {
  const _RewardCard({required this.reward});
  final Reward reward;

  @override
  ConsumerState<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends ConsumerState<_RewardCard> {
  bool _busy = false;
  Redemption? _result;

  Future<void> _redeem() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    try {
      final r = await ref.read(rewardsRepositoryProvider).redeem(widget.reward.id);
      await ref.read(analyticsProvider).log(AdEvent.rewardRedeem, {'reward_id': widget.reward.id});
      ref.invalidate(challengeControllerProvider);
      ref.invalidate(rewardsProvider);
      setState(() => _result = r);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? t.errorGeneric)));
    } on OfflineException {
      messenger.showSnackBar(SnackBar(content: Text(t.errorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.reward;
    final result = _result;
    return LiquidGlass(
      tone: GlassTone.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.titleAr, style: Theme.of(context).textTheme.titleMedium)),
              Text(t.pointsShort(YqFormat.number(r.costPoints)), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          if (result != null) ...[
            SelectableText(result.code, textAlign: TextAlign.center, style: YqText.numeral.copyWith(fontSize: 26, letterSpacing: 2)),
            const SizedBox(height: YqSpace.xs),
            Text(
              t.redeemCodeReady(DateFormat('d/M/yyyy').format(result.expiresAt)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: result.code)),
              child: const Icon(Icons.copy_rounded, size: 18),
            ),
          ] else
            FilledButton(
              onPressed: r.available && !_busy ? _redeem : null,
              child: Text(r.available ? t.redeemCta : t.notEnoughPoints(YqFormat.number(r.costPoints))),
            ),
        ],
      ),
    );
  }
}
