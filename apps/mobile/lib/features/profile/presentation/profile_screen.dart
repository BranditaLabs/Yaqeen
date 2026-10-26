import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/env.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../content/presentation/pack_row.dart';
import '../../onboarding/data/auth_repository.dart';
import '../../onboarding/data/consent_repository.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../../rewards/domain/reward.dart';

final pendingSyncProvider = FutureProvider.autoDispose((ref) => ref.watch(outboxProvider).length);
final downloadsBytesProvider = FutureProvider.autoDispose(
  (ref) async => await ref.watch(audioDownloadsProvider).bytesOnDisk() + await ref.watch(packRepositoryProvider).bytesOnDisk(),
);
final ledgerProvider = FutureProvider.autoDispose((ref) => ref.watch(rewardsRepositoryProvider).ledger());

/// `21 · Profile & settings` (spec §5.24).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final s = ref.watch(settingsProvider);
    final config = ref.watch(remoteConfigProvider);
    final summary = session.canEarnPoints ? ref.watch(challengeControllerProvider).valueOrNull : null;
    final pending = ref.watch(pendingSyncProvider).valueOrNull ?? 0;
    final bytes = ref.watch(downloadsBytesProvider).valueOrNull ?? 0;
    final name = session.canEarnPoints && (session.displayName?.isNotEmpty ?? false) ? session.displayName! : t.guestName;
    final provider = switch (session.provider) {
      SignInProvider.google => t.accountGoogle,
      SignInProvider.apple => t.accountApple,
      _ => null,
    };
    final cheapest = config.cheapestRewardPoints;
    final toNext = summary == null || cheapest == null ? null : (cheapest - summary.balance);

    Widget row(String title, {String? subtitle, YqIcons? icon, VoidCallback? onTap, Color? color}) => YqListRow(
          title: title,
          subtitle: subtitle,
          titleColor: color,
          leading: icon == null ? null : YqIconTile(icon, size: 36),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: YqColors.muted,
          ),
          onTap: onTap,
        );

    final rewards = summary != null && config.isOn(Flags.rewards);
    final initial = name.isEmpty ? '' : String.fromCharCode(name.runes.first);
    final mb = megabytes(t, bytes);

    return YqCanvas(
      stage: YqStage(
        child: Column(
          children: [
            const SizedBox(height: YqSpace.s),
            // Identity: the initial in a lapis medallion with a soft halo, then the name.
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [YqColors.lapis500, YqColors.lapis]),
                border: Border.all(color: const Color(0xF2FFFFFF), width: 3),
                boxShadow: const [BoxShadow(color: Color(0x401F3F94), blurRadius: 24, spreadRadius: -10, offset: Offset(0, 10))],
              ),
              child: Text(
                initial,
                style: const TextStyle(fontFamily: YqFonts.naskh, fontSize: 40, fontWeight: FontWeight.w700, color: YqColors.white),
              ),
            ),
            const SizedBox(height: YqSpace.m),
            Semantics(header: true, child: Text(name, textAlign: TextAlign.center, style: YqMoment.display(context, size: 30))),
            if (provider != null && session.canEarnPoints)
              Text(t.profileLinked(provider), style: text.bodySmall)
            else ...[
              const SizedBox(height: YqSpace.s),
              GlassTap(
                onTap: () => showSignInSheet(context),
                semanticLabel: t.profileGuestCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
                  decoration: BoxDecoration(color: YqColors.navy, borderRadius: BorderRadius.circular(YqRadii.pill)),
                  child: Text(t.profileGuestCta, style: const TextStyle(color: YqColors.goldLight, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
            if (pending > 0) ...[
              const SizedBox(height: YqSpace.s),
              Text(t.profilePending(pending), style: text.bodySmall?.copyWith(color: YqColors.goldText)),
            ],
          ],
        ),
      ),
      children: [
        YqOrbRow(
          orbs: [
            if (rewards) ...[
              YqOrb(
                title: t.profileBalance,
                status: t.challengePointsLabel(YqFormat.number(summary.balance)),
                glow: true,
                statusColor: YqColors.goldText,
                onTap: () => context.push('/profile/ledger'),
                semanticLabel: '${t.profileBalance}، ${t.challengePointsLabel(YqFormat.number(summary.balance))}',
                disc: YqOrb.number(YqFormat.number(summary.balance), size: 21, color: YqColors.goldDeep),
              ),
              YqOrb(
                title: t.profileRewards,
                status: toNext != null && toNext > 0 ? t.profileToNext(YqFormat.number(toNext)) : t.redeemAvailable,
                onTap: () => context.push('/challenge/redeem'),
                disc: YqRing(
                  value: cheapest == null || cheapest == 0 ? 0 : summary.balance / cheapest,
                  gold: true,
                  size: YqOrb.defaultSize - 12,
                  stroke: 5,
                  child: const YqIcon(YqIcons.store, size: 26, tone: YqIconTone.gold),
                ),
              ),
            ] else
              YqOrb(
                title: t.langApp,
                status: s.locale == 'ar' ? t.langArabic : t.langEnglish,
                onTap: () => _languageSheet(context),
                semanticLabel: '${t.langApp}، ${s.locale == 'ar' ? t.langArabic : t.langEnglish}',
                disc: YqOrb.number(s.locale == 'ar' ? 'ع' : 'En', size: 28),
              ),
            YqOrb(
              title: t.profileDownloads,
              status: mb,
              onTap: () => context.push('/profile/downloads'),
              semanticLabel: '${t.profileDownloads}، $mb',
              disc: const Center(child: YqIcon(YqIcons.download, size: 30)),
            ),
          ],
        ),
        const SizedBox(height: YqSpace.xxl),
        if (rewards) ...[
          YqGroup(
            gold: true,
            children: [
              row(t.profileLedger, icon: YqIcons.streak, onTap: () => context.push('/profile/ledger')),
              row(t.myCodes, icon: YqIcons.bookmark, onTap: () => context.push('/challenge/redeem/codes')),
              row(t.profileVisitStore, icon: YqIcons.share, onTap: () => ref.read(deviceServicesProvider).openUrl(Uri.parse(Env.storeUrl))),
            ],
          ),
          const SizedBox(height: YqSpace.xl),
        ],
        YqHeading(t.profileSettings),
        YqGroup(
          children: [
            row(
              t.profileLanguage,
              subtitle: '${s.locale == 'ar' ? t.langArabic : t.langEnglish} · ${s.script == QuranScript.uthmani ? t.scriptUthmani : t.scriptIndopak}',
              icon: YqIcons.quran,
              onTap: () => _languageSheet(context),
            ),
            row(t.profilePrayer, subtitle: methodLabel(t, s.method), icon: YqIcons.adhan, onTap: () => context.push('/prayer/notifications')),
            row(t.profilePrivacy, icon: YqIcons.settings, onTap: () => context.push('/profile/privacy')),
            row(t.profileDownloads, subtitle: mb, icon: YqIcons.download, onTap: () => context.push('/profile/downloads')),
          ],
        ),
        const SizedBox(height: YqSpace.l),
        YqGroup(
          children: [
            row(t.profileAbout, onTap: () => ref.read(deviceServicesProvider).openUrl(Uri.parse('${Env.storeUrl}/pages/about'))),
            row(t.terms, onTap: () => ref.read(deviceServicesProvider).openUrl(Uri.parse('${Env.storeUrl}/policies/terms-of-service'))),
            row(t.privacyPolicy, onTap: () => ref.read(deviceServicesProvider).openUrl(Uri.parse('${Env.storeUrl}/policies/privacy-policy'))),
            row(t.profileContact, onTap: () => ref.read(deviceServicesProvider).openUrl(Uri.parse('${Env.storeUrl}/pages/contact'))),
          ],
        ),
        if (session.signedIn && session.userId != null) ...[
          const SizedBox(height: YqSpace.l),
          YqGroup(
            children: [
              row(t.profileExport, onTap: () => _export(context, ref)),
              row(t.profileDelete, color: YqColors.goldText, onTap: () => _delete(context, ref)),
              row(t.profileSignOut, onTap: () => _signOut(context, ref)),
            ],
          ),
        ],
      ],
    );
  }

  void _languageSheet(BuildContext context) => showYqSheet<void>(
        context,
        builder: (c) => Consumer(
          builder: (c, ref, _) {
            final t = AppLocalizations.of(c);
            final s = ref.watch(settingsProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.profileLanguage, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: YqSpace.l),
                Text(t.langApp, style: Theme.of(c).textTheme.titleSmall),
                const SizedBox(height: YqSpace.s),
                YqSegmented<String>(
                  segments: [('ar', t.langArabic), ('en', t.langEnglish)],
                  selected: s.locale,
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(locale: v)),
                ),
                const SizedBox(height: YqSpace.l),
                Text(t.langFontSize, style: Theme.of(c).textTheme.titleSmall),
                YqSegmented<double>(
                  segments: [
                    for (final (i, v) in AppSettings.fontSizes.indexed) (v, const ['S', 'M', 'L', 'XL'][i]),
                  ],
                  selected: AppSettings.fontSizes.reduce((a, b) => (a - s.quranFontSize).abs() <= (b - s.quranFontSize).abs() ? a : b),
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(quranFontSize: v), sync: false),
                ),
              ],
            );
          },
        ),
      );

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    try {
      final data = await ref.read(authRepositoryProvider).exportData();
      await ref.read(deviceServicesProvider).shareText(const JsonEncoder.withIndent('  ').convert(data));
      if (context.mounted) YqToast.show(context, t.exportReady);
    } on Exception {
      if (context.mounted) YqToast.show(context, t.errorGeneric);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final ok = await _confirm(context, t.signOutConfirm, null, t.profileSignOut);
    if (!ok) return;
    await ref.read(sessionProvider.notifier).signOut();
    if (context.mounted) context.go('/onboarding/welcome');
  }

  /// Two-step confirm (spec §5.24).
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    if (!await _confirm(context, t.deleteStep1Title, t.deleteStep1Body, t.continueCta)) return;
    if (!context.mounted || !await _confirm(context, t.deleteStep2Title, t.deleteStep2Body, t.deleteConfirm)) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      YqToast.show(context, t.deleteDone);
      context.go('/onboarding/welcome');
    } on Exception {
      if (context.mounted) YqToast.show(context, t.errorGeneric);
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String? body, String cta) async =>
      await showYqSheet<bool>(
        context,
        builder: (c) {
          final t = AppLocalizations.of(c);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              if (body != null) ...[const SizedBox(height: YqSpace.s), Text(body, style: Theme.of(c).textTheme.bodyMedium)],
              const SizedBox(height: YqSpace.l),
              YqButton(label: cta, onPressed: () => Navigator.of(c).pop(true)),
              const SizedBox(height: YqSpace.s),
              YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
            ],
          );
        },
      ) ??
      false;
}

/// «الخصوصية والموافقات» — the same four switches as onboarding, recorded with source `settings`.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  Future<void> _set(ConsentKind k, bool v) async {
    await ref.read(consentRepositoryProvider).set(k, v, ConsentSource.settings);
    if (k == ConsentKind.adsMeasurement) {
      await ref.read(analyticsProvider).onConsentChanged(v);
      if (v) await ref.read(deviceServicesProvider).requestTracking();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final consents = ref.watch(consentRepositoryProvider);
    final rows = [
      (ConsentKind.worshipReminders, t.consentWorship, t.consentWorshipDetail),
      (ConsentKind.challengeRewards, t.consentChallenge, t.consentChallengeDetail),
      (ConsentKind.storeOffers, t.consentOffers, t.consentOffersDetail),
      (ConsentKind.adsMeasurement, t.consentAds, t.consentAdsDetail),
    ];
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: t.profilePrivacy),
            children: [
              LiquidGlass(
                padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
                child: Column(
                  children: [
                    for (final (i, (k, title, detail)) in rows.indexed) ...[
                      if (i > 0) const YqDivider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                  Text(detail, style: text.bodySmall),
                                ],
                              ),
                            ),
                            YqSwitch(label: title, value: consents.granted(k), onChanged: (v) => _set(k, v)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.m),
              Text(t.consentPrivacyNote, style: text.bodySmall?.copyWith(color: YqColors.success)),
            ],
          ),
        ),
      ),
    );
  }
}

/// «سجل النقاط» — the user's own ledger (amounts and reasons; never which worship act).
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final ledger = ref.watch(ledgerProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    String reason(LedgerReason r) => switch (r) {
          LedgerReason.task => t.ledgerTask,
          LedgerReason.bonus => t.ledgerBonus,
          LedgerReason.milestone => t.ledgerMilestone,
          LedgerReason.grant => t.ledgerGrant,
          LedgerReason.qada => t.ledgerQada,
          LedgerReason.redemption => t.ledgerRedemption,
          LedgerReason.adminAdjustment => t.ledgerAdjust,
          LedgerReason.reversal => t.ledgerReversal,
        };
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: t.profileLedger),
            children: ledger.when(
              loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 200))],
              error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(ledgerProvider))],
              data: (list) => list.isEmpty
                  ? [LiquidGlass(child: YqEmptyState(icon: YqIcons.challenge, title: t.ledgerEmpty))]
                  : [
                      LiquidGlass(
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                        child: Column(
                          children: [
                            for (final e in list)
                              YqListRow(
                                dense: true,
                                title: reason(e.reason),
                                subtitle: YqFormat.fullDate(e.createdAt.toLocal(), locale),
                                trailing: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    '${e.delta > 0 ? '+' : '−'}${YqFormat.number(e.delta.abs())}',
                                    style: YqText.numberSmall.copyWith(color: e.delta > 0 ? YqColors.success : YqColors.goldText),
                                  ),
                                ),
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

/// «التنزيلات دون اتصال» — storage per reciter; deleting reclaims it (spec §5.14 acceptance).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Map<String, int>? _sizes;
  int _packBytes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = ref.read(audioDownloadsProvider);
    final reciters = await ref.read(reciterRepositoryProvider).cached();
    final sizes = <String, int>{};
    for (final r in reciters) {
      final b = await d.bytesOnDisk(r.id);
      if (b > 0) sizes[r.id] = b;
    }
    final packBytes = await ref.read(packRepositoryProvider).bytesOnDisk();
    if (mounted) {
      setState(() {
        _sizes = sizes;
        _packBytes = packBytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final total = _sizes?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(title: t.profileDownloads, subtitle: t.downloadsUsed(megabytes(t, total + _packBytes))),
            children: [
              ...switch (ref.watch(packsCatalogueProvider).valueOrNull) {
                final packs? when packs.isNotEmpty => [
                    Text(t.packsTitle, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: YqSpace.s),
                    LiquidGlass(
                      padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                      child: Column(
                        children: [
                          for (final p in packs)
                            PackRow(
                              pack: p,
                              onRemove: () async {
                                await ref.read(packRepositoryProvider).remove(p.id);
                                ref.invalidate(installedPacksProvider);
                                ref.invalidate(tafsirRepositoryProvider);
                                ref.invalidate(downloadsBytesProvider);
                                await _load();
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: YqSpace.l),
                    Text(t.downloadsAudio, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: YqSpace.s),
                  ],
                _ => const <Widget>[],
              },
              if (_sizes == null)
                const YqSkeleton(child: YqSkeletonBox(height: 120))
              else if (_sizes!.isEmpty)
                LiquidGlass(child: YqEmptyState(icon: YqIcons.download, title: t.downloadsNone))
              else
                FutureBuilder(
                  future: ref.read(reciterRepositoryProvider).cached(),
                  builder: (context, snap) => LiquidGlass(
                    padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                    child: Column(
                      children: [
                        for (final r in snap.data ?? const [])
                          if (_sizes!.containsKey(r.id))
                            YqListRow(
                              title: r.name(locale),
                              subtitle: megabytes(t, _sizes![r.id]!),
                              trailing: TextButton(
                                onPressed: () async {
                                  await ref.read(audioDownloadsProvider).delete(r.id);
                                  ref.invalidate(downloadsBytesProvider);
                                  await _load();
                                },
                                child: Text(t.delete),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
