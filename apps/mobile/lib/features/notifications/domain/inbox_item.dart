enum InboxCategory { worship, challenge, offers }

/// One entry of the notification centre (spec §5.18). Stored on the device only.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.at,
    this.link,
    this.campaignId,
    this.read = false,
  });

  final String id;
  final InboxCategory category;
  final String title;
  final String body;
  final DateTime at;
  final String? link;
  final String? campaignId;
  final bool read;

  InboxItem markRead() =>
      InboxItem(id: id, category: category, title: title, body: body, at: at, link: link, campaignId: campaignId, read: true);

  Map<String, dynamic> toJson() => {
        'id': id,
        'c': category.name,
        't': title,
        'b': body,
        'at': at.toIso8601String(),
        'l': link,
        'cid': campaignId,
        'r': read,
      };

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: j['id'] as String,
        category: InboxCategory.values.firstWhere((c) => c.name == j['c'], orElse: () => InboxCategory.worship),
        title: j['t'] as String,
        body: j['b'] as String,
        at: DateTime.parse(j['at'] as String),
        link: j['l'] as String?,
        campaignId: j['cid'] as String?,
        read: (j['r'] as bool?) ?? false,
      );
}

/// Keeps the inbox bounded: last 30 days, at most 200 items, newest first (spec §5.18).
List<InboxItem> pruneInbox(Iterable<InboxItem> items, DateTime now, {int max = 200, Duration keep = const Duration(days: 30)}) {
  final byId = <String, InboxItem>{};
  for (final i in items) {
    if (now.difference(i.at) <= keep) byId[i.id] = byId[i.id]?.read == true ? i.markRead() : i;
  }
  final list = byId.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  return list.take(max).toList();
}
