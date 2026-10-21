# prayer

**Screens (design canvas):** Prayer times, Qibla, Notifications settings (adhan per prayer, pre-reminder, quiet hours), Inbox.

**Built:** core/notifications/notification_planner.dart ✅ (pure planning, iOS 64 limit)

**To build:** domain/: prayer_calculator (adhan package, Egyptian method default) · data/: location_repository · presentation/: prayer_screen, qibla_screen, notification_settings_screen, inbox_screen

**Rule:** Times are computed on-device from location; the server never receives prayer times or location history.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
