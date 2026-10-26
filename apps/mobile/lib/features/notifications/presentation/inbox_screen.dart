import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/inbox_item.dart';

final inboxProvider = FutureProvider.autoDispose((ref) => ref.watch(inboxRepositoryProvider).all());
final unreadCountProvider = FutureProvider.autoDispose((ref) async => (await ref.watch(inboxProvider.future)).where((i) => !i.read).length);

/// Opens an inbox item: deep link + mark read; campaign pushes report the open (spec §5.18).
Future<void> openInboxItem(WidgetRef ref, BuildContext context, InboxItem item) async {
  await ref.read(inboxRepositoryProvider).markRead(item.id);
  final cid = item.campaignId;
  if (cid != null) {
    await ref.read(outboxProvider).add(OutboxItem(id: Outbox.newEventId(), method: 'POST', path: '/v1/me/campaigns/$cid/opened'));
    ref.read(outboxSyncProvider).flush().ignore();
  }
  ref.invalidate(inboxProvider);
  if (item.link != null && context.mounted) context.go(routeForDeepLink(Uri.parse(item.link!)));
}

/// `15·ب · Notification centre`.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  InboxCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final items = ref.watch(inboxProvider);
    final now = ref.watch(clockProvider)();

    String group(DateTime at) {
      final d = DateTime(at.year, at.month, at.day);
      final today = DateTime(now.year, now.month, now.day);
      if (d == today) return t.inboxToday;
      if (d == today.subtract(const Duration(days: 1))) return t.inboxYesterday;
      return t.inboxEarlier;
    }

    YqIcons icon(InboxCategory c) => switch (c) {
          InboxCategory.worship => YqIcons.adhan,
          InboxCategory.challenge => YqIcons.challenge,
          InboxCategory.offers => YqIcons.store,
        };

    return Scaffold(
      body: YqCanvas(
        bottom: YqSpace.xxl,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(
                back: true,
                title: t.inboxTitle,
                actions: [
                  GlassIconButton(
                    tooltip: t.notifSettingsTitle,
                    onPressed: () => context.push('/prayer/notifications'),
                    icon: const YqIcon(YqIcons.settings, size: 20, tone: YqIconTone.idle),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    for (final (c, label) in [
                      (null, t.inboxAll),
                      (InboxCategory.worship, t.inboxWorship),
                      (InboxCategory.challenge, t.inboxChallenge),
                      (InboxCategory.offers, t.inboxOffers),
                    ]) ...[
                      YqChip(label: label, selected: _filter == c, onTap: () => setState(() => _filter = c)),
                      const SizedBox(width: YqSpace.s),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () async {
                await ref.read(inboxRepositoryProvider).markAllRead();
                ref.invalidate(inboxProvider);
              },
              child: Text(t.inboxReadAll),
            ),
          ),
          items.when(
            loading: () => const YqSkeleton(child: YqSkeletonRows(rows: 4, leading: 40)),
            error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(inboxProvider)),
            data: (all) {
              final list = all.where((i) => _filter == null || i.category == _filter).toList();
              if (list.isEmpty) {
                return LiquidGlass(child: YqEmptyState(icon: YqIcons.adhan, title: t.inboxEmpty, hint: t.inboxEmptyHint));
              }
              // Grouped by day; each day is a short journey, unread messages glow gold.
              final groups = <String, List<InboxItem>>{};
              for (final i in list) {
                groups.putIfAbsent(group(i.at.toLocal()), () => []).add(i);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final MapEntry(key: g, value: items) in groups.entries) ...[
                    YqHeading(g),
                    YqTimeline(
                      stops: [
                        for (final i in items)
                          YqStop(
                            time: YqFormat.time(i.at.toLocal(), locale),
                            title: i.title,
                            subtitle: i.body,
                            icon: icon(i.category),
                            style: StopStyle.pill,
                            highlight: !i.read,
                            semanticLabel: '${i.title}. ${i.body}. ${YqFormat.time(i.at.toLocal(), locale)}',
                            onTap: () => openInboxItem(ref, context, i),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

