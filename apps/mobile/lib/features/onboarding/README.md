# onboarding

**Screens (design canvas):** Splash → Welcome → Language → Location → Consent → Goal → Download (canvas row "First run").

**Built:** data/auth_repository.dart, data/consent_repository.dart ✅

**To build:** presentation/: splash_screen, welcome_screen, language_screen, location_screen, consent_screen, goal_screen, download_screen

**Rule:** Consent screen writes the 4 buckets with source=onboarding. ads_measurement defaults OFF; on iOS request ATT only after the user opts in.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
