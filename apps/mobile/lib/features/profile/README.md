# profile

**Screens (design canvas):** Profile, settings (language, prayer method, Hijri ±, consents), data export & account deletion.

**Built:** —

**To build:** presentation/: profile_screen, settings_screen, privacy_screen (calls GET /v1/me/export and DELETE /v1/me)

**Rule:** Consent toggles call ConsentRepository.set(..., ConsentSource.settings).

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
