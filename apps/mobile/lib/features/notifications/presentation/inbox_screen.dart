import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/notifications/push_service.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
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

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: YqPage(
            header: YqTopBar(
              title: t.inboxTitle,
              actions: [
                GlassIconButton(
                  tooltip: t.notifSettingsTitle,
                  onPressed: () => context.push('/prayer/notifications'),
                  icon: const YqIcon(YqIcons.settings, size: 20, tone: YqIconTone.idle),
                ),
              ],
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref.read(inboxRepositoryProvider).markAllRead();
                      ref.invalidate(inboxProvider);
                    },
                    child: Text(t.inboxReadAll),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.m),
              items.when(
                loading: () => const YqSkeleton(
                  child: Column(
                    children: [
                      YqSkeletonBox(height: 72, radius: YqRadii.tile),
                      SizedBox(height: 8),
                      YqSkeletonBox(height: 72, radius: YqRadii.tile),
                    ],
                  ),
                ),
                error: (_, __) => YqErrorState(onRetry: () => ref.invalidate(inboxProvider)),
                data: (all) {
                  final list = all.where((i) => _filter == null || i.category == _filter).toList();
                  if (list.isEmpty) {
                    return LiquidGlass(child: YqEmptyState(icon: YqIcons.adhan, title: t.inboxEmpty, hint: t.inboxEmptyHint));
                  }
                  final children = <Widget>[];
                  String? current;
                  for (final i in list) {
                    final g = group(i.at.toLocal());
                    if (g != current) {
                      current = g;
                      children.add(
                        Padding(
                          padding: const EdgeInsets.only(top: YqSpace.m, bottom: YqSpace.s),
                          child: Text(g, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.muted)),
                        ),
                      );
                    }
                    children.add(
                      Padding(
                        padding: const EdgeInsets.only(bottom: YqSpace.s),
                        child: _InboxRow(item: i, time: YqFormat.time(i.at.toLocal(), locale), onTap: () => openInboxItem(ref, context, i)),
                      ),
                    );
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.time, required this.onTap});
  final InboxItem item;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final icon = switch (item.category) {
      InboxCategory.worship => YqIcons.adhan,
      InboxCategory.challenge => YqIcons.challenge,
      InboxCategory.offers => YqIcons.store,
    };
    return GlassTap(
      onTap: onTap,
      semanticLabel: '${item.title}. ${item.body}. $time',
      child: LiquidGlass(
        padding: const EdgeInsets.all(YqSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YqIconTile(icon, gold: item.category != InboxCategory.worship),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: text.titleSmall?.copyWith(fontWeight: item.read ? FontWeight.w500 : FontWeight.w700)),
                  Text(item.body, style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: YqSpace.s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: text.labelSmall),
                const SizedBox(height: 6),
                if (!item.read)
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: YqColors.lapis, shape: BoxShape.circle)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
