# onboarding

**Screens (design canvas):** Splash → Welcome → Language → Location → Consent → Goal → Download (canvas row "First run").

**Built:** `data/` auth and consent repositories · `presentation/` splash (+ gate), welcome, language, prayer (location + method), consent, goal, routine and download steps, the sign-in sheet and the session controller.

**Rule:** Consent screen writes the 4 buckets with source=onboarding. ads_measurement defaults OFF; on iOS request ATT only after the user opts in.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
