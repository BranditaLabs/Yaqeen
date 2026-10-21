import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calendar/data/calendar_repository.dart';
import '../../features/challenge/data/challenge_repository.dart';
import '../../features/onboarding/data/auth_repository.dart';
import '../../features/onboarding/data/consent_repository.dart';
import '../../features/rewards/data/rewards_repository.dart';
import '../analytics/analytics.dart';
import '../config/env.dart';
import '../network/api_client.dart';
import '../notifications/notification_planner.dart';
import '../notifications/push_service.dart';
import '../offline/outbox.dart';
import '../storage/kv_store.dart';

/// Dependency graph. Platform-backed providers are overridden in `main.dart`
/// (real plugins) and in tests (fakes) — features only depend on these providers.

final kvStoreProvider = Provider<KvStore>((_) => throw UnimplementedError('Override kvStoreProvider in main()'));
final secureStoreProvider = Provider<KvStore>((_) => SecureKvStore());

final tokenStoreProvider = Provider((ref) => TokenStore(ref.watch(secureStoreProvider)));
final apiClientProvider = Provider((ref) => ApiClient(baseUrl: Env.apiBaseUrl, tokens: ref.watch(tokenStoreProvider)));
final outboxProvider = Provider((ref) => Outbox(ref.watch(kvStoreProvider)));

final authRepositoryProvider = Provider((ref) => AuthRepository(api: ref.watch(apiClientProvider), tokens: ref.watch(tokenStoreProvider)));
final consentRepositoryProvider =
    Provider((ref) => ConsentRepository(api: ref.watch(apiClientProvider), store: ref.watch(kvStoreProvider)));
final challengeRepositoryProvider = Provider(
  (ref) => ChallengeRepository(api: ref.watch(apiClientProvider), outbox: ref.watch(outboxProvider), cache: ref.watch(kvStoreProvider)),
);
final rewardsRepositoryProvider = Provider((ref) => RewardsRepository(ref.watch(apiClientProvider)));
final calendarRepositoryProvider =
    Provider((ref) => CalendarRepository(api: ref.watch(apiClientProvider), cache: ref.watch(kvStoreProvider)));

/// Ad SDK sinks (Firebase/Google Ads, Meta, TikTok) are appended here once added.
final adSinksProvider = Provider<List<AdSink>>((_) => [DebugAdSink()]);
final analyticsProvider = Provider((ref) {
  final consents = ref.watch(consentRepositoryProvider);
  return Analytics(sinks: ref.watch(adSinksProvider), adsConsent: () => consents.granted(ConsentKind.adsMeasurement));
});

final localNotificationsProvider = Provider<LocalNotificationScheduler>((_) => NoopLocalNotificationScheduler());
final pushServiceProvider = Provider<PushService>((_) => NoopPushService());
