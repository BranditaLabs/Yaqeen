# hifz

**Screens (design canvas):** Juz Amma plan, today's passage, spaced review (hard/good/easy = 1/3/14 days).

**Built:** domain/review_scheduler.dart ✅

**To build:** data/: hifz_local_store (on-device only) · presentation/: hifz_screen, review_card

**Rule:** Hifz progress stays on the device in v1 (no server sync, no analytics).

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
