# notifications

**Screens (design canvas):** Inbox of received campaign pushes.

**Built:** core/notifications/push_service.dart ✅ (interface + deep-link routing)

**To build:** presentation/: inbox_screen

**Rule:** Remote pushes respect server guardrails; local worship reminders live in core/notifications.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
