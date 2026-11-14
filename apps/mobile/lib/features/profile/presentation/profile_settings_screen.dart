import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../../core/config/config_controller.dart';
import '../../../core/config/env.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/presentation/pack_row.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../../recite/presentation/asr_model_row.dart';
import '../../recite/presentation/recite_available.dart';
import '../domain/avatar.dart';
import '../domain/avatar_presets.dart';
import 'avatar_sheet.dart';
import 'edit_name_sheet.dart';
import 'me_avatar.dart';
import 'me_profile_controller.dart';
import 'profile_providers.dart';

/// Whether any competition is offered (the «المنافسة» group and «الظهور في المنافسات»).
bool anyCompetitionOn(RemoteConfig c) => c.isOn(Flags.leagues) || c.isOn(Flags.tournaments) || c.isOn(Flags.leaderboard);

/// `/profile/settings` (APP_SPEC §5.24·ب): account, app, about, export, delete, sign out — everything
/// that used to sit under the Profile tab. Behaviours are unchanged; delete stays a two-step confirm
/// and sign-out keeps the on-device Quran data.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final s = ref.watch(settingsProvider);
    final config = ref.watch(remoteConfigProvider);
    final profile = ref.watch(meProfileProvider).valueOrNull;
    final bytes = ref.watch(downloadsBytesProvider).valueOrNull;
    final name = profile?.displayName ?? session.displayName;

    Widget row(String title, {String? subtitle, YqIcons? icon, Widget? leading, VoidCallback? onTap}) => YqListRow(
          title: title,
          subtitle: subtitle,
          leading: leading ?? (icon == null ? null : YqIconTile(icon, size: 36)),
          onTap: onTap,
        );

    final photoLabel = switch (profile?.avatar) {
      PhotoAvatar() => t.pfYourPhoto,
      PresetAvatar(:final id) => presetById(id)?.label(s.locale) ?? t.pfYourPhoto,
      _ => t.pfUseInitial,
    };

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.pfSettings)),
        children: [
          YqHeading(t.pfAccount),
          YqGroup(
            children: [
              row(
                t.pfYourName,
                subtitle: (profile?.nameHidden ?? false) ? t.avHiddenName : ((name?.trim().isNotEmpty ?? false) ? name : t.guestName),
                icon: YqIcons.edit,
                onTap: () => showEditNameSheet(context),
              ),
              row(
                t.pfYourPhoto,
                subtitle: photoLabel,
                leading: const MeAvatar(size: 36),
                onTap: () => showAvatarSheet(context, ref),
              ),
              if (anyCompetitionOn(config) && session.canEarnPoints)
                row(t.pfVisibility, icon: YqIcons.league, onTap: () => context.push('/profile/community')),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          YqHeading(t.pfApp),
          YqGroup(
            children: [
              row(
                t.profileLanguage,
                subtitle:
                    '${s.locale == 'ar' ? t.langArabic : t.langEnglish} · ${s.script == QuranScript.uthmani ? t.scriptUthmani : t.scriptIndopak}',
                icon: YqIcons.quran,
                onTap: () => showLanguageSheet(context),
              ),
              row(t.profilePrayer, subtitle: methodLabel(t, s.method), icon: YqIcons.adhan, onTap: () => context.push('/prayer/settings')),
              row(t.profilePrivacy, icon: YqIcons.settings, onTap: () => context.push('/profile/privacy')),
              row(
                t.profileDownloads,
                subtitle: bytes == null ? null : megabytes(t, bytes),
                icon: YqIcons.download,
                onTap: () => context.push('/profile/downloads'),
              ),
              // «تسميع» on the phone: shown only where it is offered (flag + supported device).
              if (ref.watch(reciteEntryProvider)) const AsrModelRow(),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          YqGroup(
            children: [
              row(t.profileAbout, onTap: () => ref.read(deviceServicesProvider).openUrl(Env.site('', s.locale))),
              row(t.terms, onTap: () => ref.read(deviceServicesProvider).openUrl(Env.site('terms', s.locale))),
              row(t.privacyPolicy, onTap: () => ref.read(deviceServicesProvider).openUrl(Env.site('privacy', s.locale))),
              row(t.profileContact, onTap: () => ref.read(deviceServicesProvider).openUrl(Env.site('support', s.locale))),
            ],
          ),
          if (session.signedIn && session.userId != null) ...[
            const SizedBox(height: YqSpace.l),
            YqGroup(
              children: [
                row(t.profileExport, onTap: () => _export(context, ref)),
                // An ink row; the error colour is kept for the final, destructive confirm.
                row(t.profileDelete, onTap: () => _delete(context, ref)),
                row(t.profileSignOut, onTap: () => _signOut(context, ref)),
              ],
            ),
          ],
        ],
      ),
    );
  }

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
    if (!context.mounted || !await _confirm(context, t.deleteStep2Title, t.deleteStep2Body, t.deleteConfirm, destructive: true)) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      YqToast.show(context, t.deleteDone);
      context.go('/onboarding/welcome');
    } on Exception {
      if (context.mounted) YqToast.show(context, t.errorGeneric);
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String? body, String cta, {bool destructive = false}) async =>
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
              if (destructive)
                _DestructiveButton(label: cta, onPressed: () => Navigator.of(c).pop(true))
              else
                YqButton(label: cta, onPressed: () => Navigator.of(c).pop(true)),
              const SizedBox(height: YqSpace.s),
              YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
            ],
          );
        },
      ) ??
      false;
}

/// «اللغة والمصحف»: the app language (the mushaf script follows the licensed sources).
void showLanguageSheet(BuildContext context) => showYqSheet<void>(
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
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).update((x) => x.copyWith(locale: v));
                  unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.settingsChange, {'setting': 'language'}));
                },
              ),
            ],
          );
        },
      ),
    );

/// The one place the error colour appears: the final step of deleting the account.
class _DestructiveButton extends StatelessWidget {
  const _DestructiveButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GlassTap(
        onTap: onPressed,
        semanticLabel: label,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl),
          decoration: BoxDecoration(color: YqColors.error, borderRadius: BorderRadius.circular(YqRadii.pill)),
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: YqColors.white)),
        ),
      );
}
