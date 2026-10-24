# azkar

**Screens:** `16 · Azkar counter` (`presentation/azkar_screen.dart`). Duas live in `features/duas`.

**Built:** `domain/azkar_progress.dart` (per-day counts, set completion → `morning_azkar` / `evening_azkar` once) ·
`data/azkar_store.dart` (device only) · `presentation/azkar_controller.dart` (tap-down counting, debounced writes).
Content comes from `features/content` (reviewed items only; every text shows its source).

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
