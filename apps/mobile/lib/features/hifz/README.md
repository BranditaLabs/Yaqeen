# hifz

**Screens (design canvas):** `22 · Hifz plan` — today's passage, spaced review (hard/good/easy = 1/3/14 days), plan sheet.

**Built:** `domain/review_scheduler.dart` · `domain/hifz_plan.dart` (goals, portions, cursor, estimate, 14-day strip) ·
`data/hifz_repository.dart` (LocalStore doc `hifz`) · `presentation/hifz_controller.dart`, `hifz_screen.dart`.

**Rule:** Hifz progress stays on the device in v1 (no server sync, no analytics, not in the server export).
Due review days feed the local «مراجعة مستحقة» reminders through `reminderInputsProvider`.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
