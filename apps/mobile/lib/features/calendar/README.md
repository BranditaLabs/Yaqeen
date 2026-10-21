# calendar

**Screens (design canvas):** Merged Hijri × 365-day calendar: done / partial / qada / missed / future, qada button.

**Built:** domain/hijri_day.dart ✅, data/calendar_repository.dart ✅ (offline cache)

**To build:** presentation/: calendar_screen (month grid, RTL, Western digits)

**Rule:** Hijri dates come from the API (Umm al-Qura + Egypt adjustment set in the admin).

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
