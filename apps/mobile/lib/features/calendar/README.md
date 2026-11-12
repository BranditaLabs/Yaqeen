# calendar

**Screens (design canvas):** Merged Hijri × 365-day calendar: done / partial / qada / missed / future, qada button.

**Built:** `domain/hijri_day.dart`, `data/calendar_repository.dart` (offline cache), `data/hijri_today.dart`, `presentation/calendar_screen.dart` (Hijri month stepping, journey · streak · balance orbs, luminous day discs, day sheet, qada).

**Rule:** Hijri dates come from the API (Umm al-Qura + Egypt adjustment set in the admin).

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
