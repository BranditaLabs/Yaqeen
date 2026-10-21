# azkar

**Screens (design canvas):** Morning/evening azkar with counters, Duas by category.

**Built:** —

**To build:** data/: content_repository (GET /v1/content?since=… → local cache) · presentation/: azkar_screen, duas_screen

**Rule:** Only reviewer-approved (published) content is served by the API.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
