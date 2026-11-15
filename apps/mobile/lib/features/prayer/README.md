# prayer

**Screens (design canvas):** Prayer times, Qibla, Notifications settings (adhan per prayer, pre-reminder, quiet hours), Inbox.

**Built:** `domain/` prayer calculator, clock, astronomy and Qibla (on-device, Egyptian method default) · `data/` prayer and city repositories · `presentation/` prayer screen, Qibla (full-screen orbit), city picker, labels. Adhan & notification settings and the inbox are in `features/notifications`; planning is `core/notifications/notification_planner.dart`.

**Rule:** Times are computed on-device from location; the server never receives prayer times or location history.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
