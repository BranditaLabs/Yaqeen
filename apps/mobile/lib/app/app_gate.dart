import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/config_controller.dart';
import '../core/di/providers.dart';
import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import '../core/widgets/ambient_background.dart';
import '../core/widgets/yq_button.dart';
import '../core/widgets/yq_logo.dart';
import '../l10n/gen/app_localizations.dart';

/// Wraps every route: maintenance screen and the blocking "update available" sheet
/// (spec §6.15), plus outbox flushes on resume / reconnect (spec §6.16).
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  bool _offlineBypass = false;
  String? _appVersion;
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(deviceServicesProvider).appVersion().then((v) {
      if (mounted) setState(() => _appVersion = v);
    });
    // Every 15 minutes while in the foreground.
    _flushTimer = Timer.periodic(const Duration(minutes: 15), (_) => ref.read(outboxSyncProvider).flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(outboxSyncProvider).flush().ignore();
      ref.read(remoteConfigProvider.notifier).refresh().ignore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onlineProvider, (prev, next) {
      if (next.valueOrNull == true && prev?.valueOrNull == false) ref.read(outboxSyncProvider).flush().ignore();
    });
    final config = ref.watch(remoteConfigProvider);
    final device = ref.watch(deviceServicesProvider);
    final version = _appVersion;
    final mustUpdate = version != null && config.needsUpdate(ios: device.isIOS, appVersion: version);

    if (config.maintenance && !_offlineBypass) {
      return _Maintenance(onContinue: () => setState(() => _offlineBypass = true));
    }
    return Stack(
      children: [
        widget.child,
        if (mustUpdate) const _UpdateRequired(),
      ],
    );
  }
}

class _Maintenance extends ConsumerWidget {
  const _Maintenance({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final config = ref.watch(remoteConfigProvider);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final message = isAr ? config.maintenanceAr : config.maintenanceEn;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(YqSpace.xxl),
            child: Column(
              children: [
                const Spacer(),
                const YqLogo(variant: YqLogoVariant.mark, width: 72),
                const SizedBox(height: YqSpace.xxl),
                Text(t.maintenanceTitle, style: YqText.display.copyWith(fontSize: 26), textAlign: TextAlign.center),
                const SizedBox(height: YqSpace.m),
                Text(
                  message.isEmpty ? t.maintenanceDefault : message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const Spacer(),
                YqButton(label: t.maintenanceContinue, onPressed: onContinue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blocking: there is no way past it except updating (min-version guard).
class _UpdateRequired extends ConsumerWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final device = ref.watch(deviceServicesProvider);
    final store = device.isIOS
        ? Uri.parse('https://apps.apple.com/app/id${const String.fromEnvironment('APP_STORE_ID', defaultValue: '0')}')
        : Uri.parse('https://play.google.com/store/apps/details?id=com.yaqinbrand.yaqeen');
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x8C0A1530),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(YqSpace.xl, YqSpace.xxl, YqSpace.xl, YqSpace.xl + MediaQuery.paddingOf(context).bottom),
              decoration: const BoxDecoration(
                color: YqColors.porcelain,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const YqLogo(variant: YqLogoVariant.mark, width: 56),
                  const SizedBox(height: YqSpace.l),
                  Text(t.updateTitle, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: YqSpace.s),
                  Text(t.updateBody, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                  const SizedBox(height: YqSpace.xl),
                  YqButton(label: t.updateCta, onPressed: () => device.openUrl(store)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
