import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calendar/data/calendar_repository.dart';
import '../../features/challenge/data/challenge_repository.dart';
import '../../features/notifications/data/inbox_repository.dart';
import '../../features/notifications/data/reminder_service.dart';
import '../../features/onboarding/data/auth_repository.dart';
import '../../features/onboarding/data/consent_repository.dart';
import '../../features/prayer/data/city_repository.dart';
import '../../features/prayer/data/prayer_repository.dart';
import '../../features/rewards/data/rewards_repository.dart';
import '../analytics/analytics.dart';
import '../config/env.dart';
import '../config/remote_config.dart';
import '../network/api_client.dart';
import '../network/connectivity.dart';
import '../notifications/notification_planner.dart';
import '../notifications/push_service.dart';
import '../offline/outbox.dart';
import '../platform/device_services.dart';
import '../platform/location_service.dart';
import '../platform/social_auth.dart';
import '../settings/app_settings.dart';
import '../settings/settings_repository.dart';
import '../storage/kv_store.dart';
import '../storage/local_store.dart';

/// Dependency graph. Platform-backed providers are overridden in `main.dart`
/// (real plugins) and in tests (fakes) — features only depend on these providers.

final kvStoreProvider = Provider<KvStore>((_) => throw UnimplementedError('Override kvStoreProvider in main()'));
final secureStoreProvider = Provider<KvStore>((_) => SecureKvStore());
final localStoreProvider = Provider((ref) => LocalStore(ref.watch(kvStoreProvider)));

/// Injectable clock (tests pin "now").
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final tokenStoreProvider = Provider((ref) => TokenStore(ref.watch(secureStoreProvider)));
final apiClientProvider = Provider((ref) => ApiClient(baseUrl: Env.apiBaseUrl, tokens: ref.watch(tokenStoreProvider)));
final outboxProvider = Provider((ref) => Outbox(ref.watch(kvStoreProvider)));
final outboxSyncProvider = Provider(
  (ref) => OutboxSync(
    api: ref.watch(apiClientProvider),
    outbox: ref.watch(outboxProvider),
    isSignedIn: () async => (await ref.read(tokenStoreProvider).accessToken) != null,
  ),
);

/* --------------------------------------------------------------- platform */

final deviceServicesProvider = Provider<DeviceServices>((_) => FakeDeviceServices());
final locationServiceProvider = Provider<LocationService>((_) => FakeLocationService());
final compassServiceProvider = Provider<CompassService>((_) => FakeCompassService());
final socialAuthProvider = Provider<SocialAuth>((_) => FakeSocialAuth());
final connectivityProvider = Provider<ConnectivityMonitor>((_) => const AlwaysOnline());

/// Live online/offline state (starts optimistic).
final onlineProvider = StreamProvider<bool>((ref) async* {
  final c = ref.watch(connectivityProvider);
  yield await c.isOnline();
  yield* c.changes;
});

/* ----------------------------------------------------------- repositories */

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(store: ref.watch(kvStoreProvider), outbox: ref.watch(outboxProvider)));
final remoteConfigRepositoryProvider = Provider(
  (ref) => RemoteConfigRepository(api: ref.watch(apiClientProvider), cache: ref.watch(kvStoreProvider), now: ref.watch(clockProvider)),
);
final authRepositoryProvider = Provider(
  (ref) => AuthRepository(api: ref.watch(apiClientProvider), tokens: ref.watch(tokenStoreProvider), store: ref.watch(kvStoreProvider)),
);
final consentRepositoryProvider =
    Provider((ref) => ConsentRepository(api: ref.watch(apiClientProvider), store: ref.watch(kvStoreProvider)));
final challengeRepositoryProvider = Provider(
  (ref) => ChallengeRepository(
    api: ref.watch(apiClientProvider),
    outbox: ref.watch(outboxProvider),
    sync: ref.watch(outboxSyncProvider),
    cache: ref.watch(kvStoreProvider),
  ),
);
final rewardsRepositoryProvider = Provider((ref) => RewardsRepository(ref.watch(apiClientProvider), cache: ref.watch(kvStoreProvider)));
final calendarRepositoryProvider =
    Provider((ref) => CalendarRepository(api: ref.watch(apiClientProvider), cache: ref.watch(kvStoreProvider)));

/* ------------------------------------------------- start-up loaded state */

/// Loaded in main() before the first frame so the first paint already has the right locale.
final initialSettingsProvider = Provider<AppSettings>((_) => const AppSettings());
final initialConfigProvider = Provider<RemoteConfig>((_) => const RemoteConfig());
final initialSessionProvider = Provider<Session>((_) => Session.none);

/* -------------------------------------------------------------- analytics */

/// Ad SDK sinks (Firebase/Google Ads, Meta, TikTok) are appended here once added.
final adSinksProvider = Provider<List<AdSink>>((_) => [DebugAdSink()]);
final analyticsProvider = Provider((ref) {
  final consents = ref.watch(consentRepositoryProvider);
  return Analytics(
    sinks: ref.watch(adSinksProvider),
    adsConsent: () => consents.granted(ConsentKind.adsMeasurement),
    store: ref.watch(kvStoreProvider),
  );
});

final localNotificationsProvider = Provider<LocalNotificationScheduler>((_) => NoopLocalNotificationScheduler());

/// Deep links from tapped local notifications and pushes (overridden in main()).
final notificationTapsProvider = StreamProvider<Uri>((_) => const Stream.empty());

/* ------------------------------------------------------------ worship data */

final cityRepositoryProvider = Provider((_) => CityRepository());
final prayerRepositoryProvider = Provider((_) => const PrayerRepository());
final inboxRepositoryProvider = Provider((ref) => InboxRepository(ref.watch(localStoreProvider), now: ref.watch(clockProvider)));
final reminderServiceProvider = Provider(
  (ref) => ReminderService(
    scheduler: ref.watch(localNotificationsProvider),
    store: ref.watch(localStoreProvider),
    inbox: ref.watch(inboxRepositoryProvider),
  ),
);
final pushServiceProvider = Provider<PushService>((_) => NoopPushService());
