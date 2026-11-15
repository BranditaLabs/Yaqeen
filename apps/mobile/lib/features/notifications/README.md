# notifications

**Screens (design canvas):** Inbox of received campaign pushes.

**Built:** `data/inbox_repository.dart`, `data/reminder_service.dart`, `domain/inbox_item.dart`, `presentation/` inbox (each day as a timeline), adhan & notification settings (today's reminders, «روتيني»), `reminders_controller.dart` (re-plans local reminders). Push routing is `core/notifications/push_service.dart`.

**Rule:** Remote pushes respect server guardrails; local worship reminders live in core/notifications.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
