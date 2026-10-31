import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/product_analytics.dart';
import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/config/env.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/design/living_sky.dart';
import '../../../core/widgets/liquid_orb.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_logo.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../routine/domain/routine.dart';
import '../../routine/presentation/habit_picker.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../prayer/domain/prayer_calculator.dart';
import '../../prayer/domain/prayer_clock.dart';
import '../../prayer/presentation/city_picker_sheet.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../../quran/domain/quran_data.dart';
import '../../content/domain/content_pack.dart';
import '../../content/presentation/pack_row.dart';
import '../data/auth_repository.dart';
import '../data/consent_repository.dart';
import 'session_controller.dart';
import 'sign_in_sheet.dart';

/// Each step saves as it goes (kill-safe, spec §6.2); `onboardingStep` lets a restart resume.
void _saveStep(WidgetRef ref, int step) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingStep: step), sync: false);

/* ------------------------------------------------------------------- 02 */

/// `02 · Sign in` (spec §5.3).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  SignInProvider? _busy;

  Future<void> _signIn(SignInProvider p) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = p);
    final session = ref.read(sessionProvider.notifier);
    if (p == SignInProvider.guest) {
      await session.continueAsGuest();
      if (mounted) _next();
      return;
    }
    final outcome = await session.signInWith(p);
    if (!mounted) return;
    setState(() => _busy = null);
    switch (outcome) {
      case SignInOutcome.signedIn:
        _next();
      case SignInOutcome.cancelled:
        break; // stay, no error (spec §5.3)
      case SignInOutcome.offline:
        YqToast.show(context, t.welcomeOffline);
      case SignInOutcome.failed:
        YqToast.show(context, t.welcomeError);
    }
  }

  void _next() {
    _saveStep(ref, 1);
    // From inside the app (challenge, profile) the flow returns; first launch continues the steps.
    if (ref.read(settingsProvider).onboarded && context.canPop()) {
      context.pop();
    } else {
      context.go('/onboarding/language');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final busy = _busy != null;
    final benefits = [
      (YqIcons.quran, t.welcomeBenefitQuran, false),
      (YqIcons.prayer, t.welcomeBenefitPrayer, false),
      (YqIcons.store, t.welcomeBenefitPoints, true),
    ];

    final settings = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final arc = dayArcAt(settings, repo, ref.watch(clockProvider)());

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.l,
        stage: YqStage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const YqLogo(variant: YqLogoVariant.horizontal, height: 34),
                    const Spacer(),
                    GlassTap(
                      semanticLabel: t.languageOther,
                      onTap: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(locale: locale == 'ar' ? 'en' : 'ar')),
                      child: LiquidGlass(
                        radius: YqRadii.pill,
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.language_rounded, size: 16, color: YqColors.lapis),
                            const SizedBox(width: 6),
                            Text(t.languageOther, style: text.labelMedium),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.xl),
              // The first thing Yaqeen shows is the user's own sky: the day's arc with the sun
              // where it is right now.
              ExcludeSemantics(
                child: DayArc(
                  position: arc.position,
                  nextIndex: arc.nextIndex,
                  night: arc.night,
                  height: 84,
                  labels: [for (final p in obligatory) prayerLabel(t, p)],
                  current: arc.nextIndex.clamp(0, 4),
                ),
              ),
              const SizedBox(height: YqSpace.l),
              YqMoment(
                eyebrow: t.welcomeSalam,
                value: Text(t.welcomeTitle, style: YqMoment.display(context, size: 32).copyWith(height: 1.35)),
                caption: Text(t.welcomeBody, style: text.bodyLarge?.copyWith(color: YqColors.muted)),
              ),
            ],
          ),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!online)
              Padding(
                padding: const EdgeInsets.only(bottom: YqSpace.s),
                child: Text(t.welcomeOffline, textAlign: TextAlign.center, style: text.bodySmall),
              ),
            YqButton.secondary(
              label: t.welcomeGoogle,
              loading: _busy == SignInProvider.google,
              onPressed: busy || !online ? null : () => _signIn(SignInProvider.google),
            ),
            const SizedBox(height: YqSpace.s),
            YqButton(
              label: t.welcomeApple,
              loading: _busy == SignInProvider.apple,
              onPressed: busy || !online ? null : () => _signIn(SignInProvider.apple),
            ),
            const SizedBox(height: YqSpace.xs),
            Center(child: YqButton.text(label: t.welcomeGuest, onPressed: busy ? null : () => _signIn(SignInProvider.guest))),
            Text(t.welcomeLegal, textAlign: TextAlign.center, style: text.bodySmall?.copyWith(fontSize: 11)),
          ],
        ),
        children: [
          YqGroup(
            children: [
              for (final (icon, label, gold) in benefits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
                  child: Row(
                    children: [
                      YqIconTile(icon, gold: gold, size: 40),
                      const SizedBox(width: YqSpace.m),
                      Expanded(child: Text(label, style: text.bodyLarge)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------- step scaffold */

class _Step extends ConsumerWidget {
  const _Step({
    required this.step,
    required this.title,
    required this.sub,
    required this.children,
    required this.cta,
    required this.onCta,
    this.onSkip,
    this.footer,
    this.ctaLoading = false,
    this.visual,
  });

  final int step;
  final String title;
  final String sub;
  final List<Widget> children;
  final String cta;
  final VoidCallback onCta;
  final VoidCallback? onSkip;
  final Widget? footer;
  final bool ctaLoading;

  /// A live picture of the step in the stage (the day arc, the user's day).
  final Widget? visual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.l,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  YqBackButton(label: t.back),
                  const Spacer(),
                  YqStepper(step: step, semanticLabel: t.stepOf(step)),
                  const Spacer(),
                  SizedBox(width: 64, child: onSkip == null ? null : TextButton(onPressed: onSkip, child: Text(t.skip))),
                ],
              ),
              const SizedBox(height: YqSpace.xl),
              Text(t.stepEyebrow(step), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
              const SizedBox(height: YqSpace.xs),
              Semantics(
                header: true,
                child: Text(title, style: YqMoment.display(context, size: 30).copyWith(height: 1.35)),
              ),
              const SizedBox(height: YqSpace.s),
              Text(sub, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
              if (visual != null) ...[const SizedBox(height: YqSpace.l), visual!],
            ],
          ),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqButton(label: cta, loading: ctaLoading, onPressed: onCta),
            if (footer != null) ...[const SizedBox(height: YqSpace.s), footer!],
          ],
        ),
        children: children,
      ),
    );
  }
}

/* ------------------------------------------------------------------- 03 */

/// `03 · Language & mushaf` (spec §5.4).
class LanguageStep extends ConsumerWidget {
  const LanguageStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final quran = ref.watch(quranDataProvider).valueOrNull;
    void next() {
      _saveStep(ref, 2);
      context.go('/onboarding/prayer');
    }

    return _Step(
      step: 1,
      title: t.langTitle,
      sub: t.langSub,
      cta: t.continueCta,
      onCta: next,
      // «تخطي» keeps the defaults: ar · uthmani · M.
      onSkip: next,
      children: [
        YqSection(
          title: t.langApp,
          child: YqSegmented<String>(
            segments: [('ar', t.langArabic), ('en', t.langEnglish)],
            selected: s.locale,
            onChanged: (v) => ctl.update((x) => x.copyWith(locale: v)),
          ),
        ),
        const SizedBox(height: YqSpace.m),
        YqSection(
          title: t.langScript,
          child: Column(
            children: [
              _RadioCard(
                title: t.scriptUthmani,
                detail: t.scriptUthmaniDetail,
                selected: s.script == QuranScript.uthmani,
                onTap: () => ctl.update((x) => x.copyWith(script: QuranScript.uthmani), sync: false),
              ),
              const SizedBox(height: YqSpace.s),
              // The Indo-Pak text asset isn't licensed yet (spec §6.6) — shown, disabled.
              _RadioCard(title: t.scriptIndopak, detail: t.scriptIndopakDetail, selected: false, badge: t.soon),
              const SizedBox(height: YqSpace.m),
              if (quran != null)
                Text(
                  quran.basmala,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: YqText.quran(size: s.quranFontSize, height: 2, color: YqColors.ink),
                ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        YqSection(
          title: t.langFontSize,
          child: Column(
            children: [
              Slider(
                value: AppSettings.fontSizes.indexOf(_nearest(s.quranFontSize)).toDouble(),
                max: 3,
                divisions: 3,
                label: const ['S', 'M', 'L', 'XL'][AppSettings.fontSizes.indexOf(_nearest(s.quranFontSize))],
                activeColor: YqColors.lapis,
                onChanged: (v) => ctl.update((x) => x.copyWith(quranFontSize: AppSettings.fontSizes[v.round()]), sync: false),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final l in const ['S', 'M', 'L', 'XL']) Text(l, style: text.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static double _nearest(double v) => AppSettings.fontSizes.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.title, required this.detail, required this.selected, this.onTap, this.badge});
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YqRadii.tile),
        child: AnimatedContainer(
          duration: YqMotion.fast,
          padding: const EdgeInsets.all(YqSpace.m),
          decoration: BoxDecoration(
            color: selected ? const Color(0xE6FFFFFF) : const Color(0x80FFFFFF),
            borderRadius: BorderRadius.circular(YqRadii.tile),
            border: Border.all(color: selected ? YqColors.lapis : YqColors.line, width: selected ? 1.6 : 1),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? YqColors.lapis : YqColors.slate400,
                ),
                const SizedBox(width: YqSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(detail, style: text.bodySmall),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: 2),
                    decoration: BoxDecoration(color: YqColors.gold100, borderRadius: BorderRadius.circular(YqRadii.pill)),
                    child: Text(badge!, style: text.labelSmall?.copyWith(color: YqColors.goldText)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------- 04 */

/// `04 · Prayer setup` (spec §5.5). Location is asked here, never at app start; denied → city search.
class PrayerStep extends ConsumerStatefulWidget {
  const PrayerStep({super.key});

  @override
  ConsumerState<PrayerStep> createState() => _PrayerStepState();
}

class _PrayerStepState extends ConsumerState<PrayerStep> {
  bool _locating = false;

  Future<void> _locate() async {
    setState(() => _locating = true);
    final place = await detectPlace(ref);
    if (!mounted) return;
    setState(() => _locating = false);
    if (place != null) {
      await _setPlace(place);
    } else {
      await _pick();
    }
  }

  Future<void> _pick() async {
    final place = await showCityPicker(context);
    if (place != null) await _setPlace(place);
  }

  Future<void> _setPlace(Place p) =>
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(place: p, method: CalcMethod.recommendedFor(p.country)));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final recommended = CalcMethod.recommendedFor(s.place?.country ?? 'EG');
    final methods = {recommended, CalcMethod.egypt, CalcMethod.mwl, CalcMethod.ummAlQura}.toList();
    final adhanOn = s.alertModes.values.any((m) => m == AlertMode.adhan);

    final arc = dayArcAt(s, ref.watch(prayerRepositoryProvider), ref.watch(clockProvider)());
    final times = ref.watch(prayerRepositoryProvider).forDate(s, ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)()));
    return _Step(
      step: 2,
      title: t.prayerSetupTitle,
      sub: t.prayerSetupSub,
      // Today's real times at the chosen place, on the day's arc — it moves as the place changes.
      visual: ExcludeSemantics(
        child: Column(
          children: [
            DayArc(
              position: arc.position,
              nextIndex: arc.nextIndex,
              night: arc.night,
              height: 72,
              labels: [for (final p in obligatory) prayerLabel(t, p)],
              current: arc.nextIndex.clamp(0, 4),
            ),
            Row(
              children: [
                for (final p in obligatory)
                  Expanded(
                    child: Text(
                      YqFormat.time(ref.watch(prayerRepositoryProvider).local(s, times.of(p)), s.locale),
                      textAlign: TextAlign.center,
                      style: YqText.numberSmall.copyWith(fontSize: 11, color: YqColors.ink),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      cta: t.continueCta,
      onCta: () {
        if (s.place == null) ctl.update((x) => x.copyWith(place: Place.cairo));
        _saveStep(ref, 3);
        context.go('/onboarding/consent');
      },
      children: [
        LiquidGlass(
          child: Row(
            children: [
              const YqIconTile(YqIcons.location, size: 44),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.place?.name(s.locale) ?? t.prayerSetupManual, style: text.titleMedium),
                    if (s.place?.auto ?? false) Text(t.prayerSetupAuto, style: text.bodySmall?.copyWith(color: YqColors.success)),
                  ],
                ),
              ),
              if (s.place == null)
                YqButton.text(label: t.prayerSetupLocate, loading: _locating, onPressed: _locating ? null : _locate)
              else
                YqButton.text(label: t.change, onPressed: _pick),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        YqSection(
          title: t.prayerSetupMethod,
          child: Column(
            children: [
              for (final m in methods) ...[
                _RadioCard(
                  title: methodLabel(t, m),
                  detail: m == recommended
                      ? t.methodRecommended
                      : switch (m) {
                          CalcMethod.mwl => t.methodMwlDetail,
                          CalcMethod.ummAlQura => t.methodUmmAlQuraDetail,
                          _ => '',
                        },
                  selected: s.method == m,
                  onTap: () => ctl.update((x) => x.copyWith(method: m)),
                ),
                const SizedBox(height: YqSpace.s),
              ],
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        YqSection(
          title: t.prayerSetupAsr,
          child: YqSegmented<AsrSchool>(
            segments: [(AsrSchool.standard, t.asrStandard), (AsrSchool.hanafi, t.asrHanafi)],
            selected: s.asr,
            onChanged: (v) => ctl.update((x) => x.copyWith(asr: v)),
          ),
        ),
        const SizedBox(height: YqSpace.m),
        LiquidGlass(
          child: Row(
            children: [
              const YqIconTile(YqIcons.adhan, size: 40),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.prayerSetupAdhan, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(t.prayerSetupAdhanDetail(s.preReminderMinutes), style: text.bodySmall),
                  ],
                ),
              ),
              YqSwitch(
                label: t.prayerSetupAdhan,
                value: adhanOn,
                onChanged: (v) => ctl.update(
                  (x) => x.copyWith(
                    alertModes: v ? AppSettings.defaultAlertModes : {for (final k in x.alertModes.keys) k: AlertMode.notify},
                  ),
                  sync: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ----------------------------------------------------------------- 04·ب */

/// `04·ب · Notifications & privacy consent` (spec §5.6). Defaults exactly as the table.
class ConsentStep extends ConsumerStatefulWidget {
  const ConsentStep({super.key});

  @override
  ConsumerState<ConsentStep> createState() => _ConsentStepState();
}

class _ConsentStepState extends ConsumerState<ConsentStep> {
  late final Map<ConsentKind, bool> _values = {
    for (final k in onboardingConsents)
      k: ref.read(consentRepositoryProvider).decided ? ref.read(consentRepositoryProvider).granted(k) : consentDefaults[k]!,
  };
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    final consents = ref.read(consentRepositoryProvider);
    for (final e in _values.entries) {
      await consents.set(e.key, e.value, ConsentSource.onboarding);
    }
    await consents.markDecided();
    // OS prompts come after the choice: notifications first, then ATT (iOS) when ads are on.
    if (_values[ConsentKind.worshipReminders]! || _values[ConsentKind.challengeRewards]! || _values[ConsentKind.storeOffers]!) {
      await ref.read(localNotificationsProvider).requestPermission();
    }
    if (_values[ConsentKind.adsMeasurement]!) await ref.read(deviceServicesProvider).requestTracking();
    // Queued first_open / sign_up go out only if ads ended ON; otherwise they are dropped.
    await ref.read(analyticsProvider).onConsentChanged(_values[ConsentKind.adsMeasurement]!);
    await ref.read(productAnalyticsProvider).onConsentChanged(_values[ConsentKind.productAnalytics]!);
    ref.read(remindersControllerProvider.notifier).replan().ignore();
    if (!mounted) return;
    setState(() => _busy = false);
    _saveStep(ref, 4);
    context.go('/onboarding/goal');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ios = ref.read(deviceServicesProvider).isIOS;
    final rows = [
      (ConsentKind.worshipReminders, YqIcons.adhan, t.consentWorship, t.consentWorshipDetail),
      (ConsentKind.challengeRewards, YqIcons.challenge, t.consentChallenge, t.consentChallengeDetail),
      (ConsentKind.storeOffers, YqIcons.store, t.consentOffers, t.consentOffersDetail),
      (ConsentKind.adsMeasurement, YqIcons.share, t.consentAds, t.consentAdsDetail),
      (ConsentKind.productAnalytics, YqIcons.settings, t.consentAnalytics, t.consentAnalyticsDetail),
    ];
    return _Step(
      step: 3,
      title: t.consentTitle,
      sub: t.consentSub,
      cta: t.continueCta,
      ctaLoading: _busy,
      onCta: _continue,
      footer: Text(
        ios && _values[ConsentKind.adsMeasurement]! ? t.consentOsHintAtt : t.consentOsHint,
        textAlign: TextAlign.center,
        style: text.bodySmall,
      ),
      children: [
        LiquidGlass(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
          child: Column(
            children: [
              for (final (i, (kind, icon, title, detail)) in rows.indexed) ...[
                if (i > 0) const YqDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
                  child: Row(
                    children: [
                      YqIconTile(icon, size: 40, gold: kind == ConsentKind.storeOffers),
                      const SizedBox(width: YqSpace.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(detail, style: text.bodySmall?.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: YqSpace.s),
                      YqSwitch(label: title, value: _values[kind]!, onChanged: (v) => setState(() => _values[kind] = v)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        Container(
          padding: const EdgeInsets.all(YqSpace.m),
          decoration: BoxDecoration(color: const Color(0x142E7A55), borderRadius: BorderRadius.circular(YqRadii.tile)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, color: YqColors.success, size: 20),
              const SizedBox(width: YqSpace.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.consentPrivacyNote, style: text.bodySmall?.copyWith(color: YqColors.success)),
                    GestureDetector(
                      onTap: () => ref.read(deviceServicesProvider).openUrl(Env.site('privacy', ref.read(settingsProvider).locale)),
                      child: Text(
                        t.privacyPolicy,
                        style: text.bodySmall?.copyWith(color: YqColors.success, decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------- 05 */

/// `05 · Daily goal & challenge` (spec §5.7). Numbers come from remote config.
class GoalStep extends ConsumerStatefulWidget {
  const GoalStep({super.key});

  @override
  ConsumerState<GoalStep> createState() => _GoalStepState();
}

class _GoalStepState extends ConsumerState<GoalStep> {
  bool _join = true;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    if (_join) {
      var session = ref.read(sessionProvider);
      // A guest never calls enroll: offer to sign in first, or join later from the challenge tab.
      if (!session.canEarnPoints) {
        await showSignInSheet(context);
        session = ref.read(sessionProvider);
      }
      if (session.canEarnPoints) {
        try {
          await ref.read(challengeControllerProvider.notifier).enroll();
        } on Exception {
          // Offline: the challenge tab offers joining again.
        }
      }
    }
    ref.read(remindersControllerProvider.notifier).replan().ignore();
    if (!mounted) return;
    setState(() => _busy = false);
    _saveStep(ref, 5);
    context.go('/onboarding/routine');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final config = ref.watch(remoteConfigProvider);
    final goals = [(1, t.goalPage), (2, t.goalTwoPages), (4, t.goalFourPages), (20, t.goalJuz)];

    return _Step(
      step: 4,
      title: t.goalTitle,
      sub: t.goalSub,
      cta: t.goalStart,
      ctaLoading: _busy,
      onCta: _start,
      children: [
        Wrap(
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            for (final (pages, label) in goals)
              YqChip(
                label: label,
                selected: s.wirdGoalPages == pages,
                onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(wirdGoalPages: pages), sync: false),
              ),
          ],
        ),
        const SizedBox(height: YqSpace.m),
        LiquidGlass(
          tone: GlassTone.gold,
          padding: const EdgeInsets.all(YqSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.goalChallengeEyebrow, style: text.labelMedium?.copyWith(color: YqColors.goldText)),
              Text(t.challengeTitle, style: YqText.display.copyWith(fontSize: 26)),
              const SizedBox(height: YqSpace.s),
              Row(
                children: [
                  Expanded(child: Text(t.goalJoin, style: text.titleSmall)),
                  YqSwitch(label: t.goalJoin, value: _join, activeColor: YqColors.gold, onChanged: (v) => setState(() => _join = v)),
                ],
              ),
              const SizedBox(height: YqSpace.s),
              Text(t.goalChallengeBody, style: text.bodySmall),
              const SizedBox(height: YqSpace.m),
              Row(
                children: [
                  Expanded(child: _Stat(t.goalDailyPoints(YqFormat.number(config.dailyTotal)))),
                  if (config.cheapestRewardPoints case final p?) ...[
                    const SizedBox(width: YqSpace.s),
                    Expanded(child: _Stat(t.goalRewardPoints(YqFormat.number(p)))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step 5 — «متى يناسبك؟»: when the user reads Quran, reviews hifz and does a dhikr session.
/// Each habit anchors to a prayer (or a set time); Home's «Your day» timeline and the local
/// reminders follow it. Stays on the device.
class RoutineStep extends ConsumerWidget {
  const RoutineStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final hifz = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.hifz)));
    void set(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f, sync: false);

    return _Step(
      step: 5,
      title: t.routineTitle,
      sub: t.routineSub,
      cta: t.routineCta,
      onCta: () {
        ref.read(remindersControllerProvider.notifier).replan().ignore();
        _saveStep(ref, 6);
        context.go('/onboarding/download');
      },
      children: [
        HabitSlotCard(
          habit: Habit.quran,
          slot: s.quranSlot,
          allowOff: false,
          onChanged: (v) => set((x) => x.copyWith(quranSlot: v)),
        ),
        if (hifz) ...[
          const SizedBox(height: YqSpace.m),
          HabitSlotCard(habit: Habit.hifz, slot: s.hifzSlot, onChanged: (v) => set((x) => x.copyWith(hifzSlot: v))),
        ],
        const SizedBox(height: YqSpace.m),
        HabitSlotCard(habit: Habit.dhikr, slot: s.dhikrSlot, onChanged: (v) => set((x) => x.copyWith(dhikrSlot: v))),
        const SizedBox(height: YqSpace.xxl),
        YqHeading(t.homeDayTitle),
        _DayPreview(hifz: hifz),
      ],
    );
  }
}

/// The user's day as it will look with this routine: the five prayers and each habit at its
/// resolved time — it rearranges live as the choices change.
class _DayPreview extends ConsumerWidget {
  const _DayPreview({required this.hifz});
  final bool hifz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final times = repo.forDate(s, repo.today(s, ref.watch(clockProvider)()));
    String at(DateTime utc) => YqFormat.time(repo.local(s, utc), s.locale);
    final entries = <(YqStop, DateTime)>[
      for (final p in obligatory) (YqStop(time: at(times.of(p)), title: prayerLabel(t, p)), times.of(p)),
    ];
    for (final (h, slot) in [(Habit.quran, s.quranSlot), if (hifz) (Habit.hifz, s.hifzSlot), (Habit.dhikr, s.dhikrSlot)]) {
      final when = resolveSlot(slot, times, s.placeOrDefault.timezone);
      if (when == null) continue;
      entries.add((YqStop(time: at(when), title: habitLabel(t, h), icon: habitIcon(h), style: StopStyle.pill, highlight: true), when));
    }
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])]..sort((a, b) {
        final c = a.$2.$2.compareTo(b.$2.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return ExcludeSemantics(child: YqTimeline(stops: [for (final e in indexed) e.$2.$1]));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.s, horizontal: YqSpace.m),
        decoration: BoxDecoration(color: const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(YqRadii.chip)),
        child: Text(label, textAlign: TextAlign.center, style: YqText.numberSmall.copyWith(color: YqColors.goldDeep)),
      );
}

/* ------------------------------------------------------------------- 06 */

/// `06 · Offline mushaf` (spec §5.8). Text and font ship in the binary, so reading works in
/// airplane mode right after install; tafsir and audio come from licensed packs when approved.
class DownloadStep extends ConsumerWidget {
  const DownloadStep({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingCompletedAt: DateTime.now()), sync: false);
    await ref.read(analyticsProvider).logOrQueue(AdEvent.onboardingComplete);
    unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.onboardingComplete));
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final quranAsync = ref.watch(quranDataProvider);
    final quran = quranAsync.valueOrNull;
    // A failed load must never trap the user here: say so, offer a retry, and let them continue.
    final failed = quranAsync.hasError && quran == null;
    final items = [
      (t.downloadText, t.downloadBundled, true),
      (t.downloadFont, t.downloadBundled, true),
    ];
    // Tafsir appears only once a licensed pack is in the catalogue; until then it says so.
    final tafsir =
        (ref.watch(packsCatalogueProvider).valueOrNull ?? const <ContentPack>[]).where((p) => p.kind == PackKind.tafsir).toList();
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        bottom: YqSpace.l,
        stage: YqStage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: YqSpace.l),
              Text(t.downloadEyebrow, style: text.labelMedium?.copyWith(color: YqColors.goldText)),
              const SizedBox(height: YqSpace.xs),
              Text(t.downloadTitle, style: YqMoment.display(context, size: 30).copyWith(height: 1.35)),
              const SizedBox(height: YqSpace.s),
              Text(t.downloadSub, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
              const SizedBox(height: YqSpace.xl),
              // The mushaf filling the device: liquid that rises to full once the text is ready.
              Center(
                child: LiquidOrb(
                  level: quran != null ? 1 : (failed ? 0 : 0.35),
                  size: 132,
                  complete: quran != null,
                  child: failed
                      ? const Icon(Icons.error_outline_rounded, color: YqColors.slate400, size: 36)
                      : Text(
                          quran == null ? '…' : '100%',
                          textDirection: TextDirection.ltr,
                          style: YqText.numeral.copyWith(fontSize: 26, color: YqColors.ink),
                        ),
                ),
              ),
            ],
          ),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqButton(label: t.downloadStart, onPressed: quran == null && !failed ? null : () => _finish(context, ref)),
            const SizedBox(height: YqSpace.xs),
            Text(t.downloadBackground, textAlign: TextAlign.center, style: text.bodySmall),
          ],
        ),
        children: [
          YqGroup(
            children: [
              for (final (label, status, ready) in items)
                YqListRow(
                  dense: true,
                  title: label,
                  subtitle: status,
                  trailing: Icon(
                    ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    color: ready ? YqColors.success : YqColors.slate400,
                  ),
                ),
              if (tafsir.isEmpty)
                YqListRow(
                  dense: true,
                  title: t.downloadTafsir,
                  subtitle: t.downloadPending,
                  trailing: const Icon(Icons.schedule_rounded, color: YqColors.slate400),
                )
              else
                for (final p in tafsir) PackRow(pack: p),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: YqSpace.l),
            Text(t.errorGeneric, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
            TextButton(onPressed: () => ref.invalidate(quranDataProvider), child: Text(t.retry)),
          ],
          if (quran != null) ...[
            const SizedBox(height: YqSpace.xl),
            Text(
              quran.text(const AyahRef(73, 4)),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: YqText.quran(size: 18, height: 2, color: YqColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}
