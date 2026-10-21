# quran

**Screens (design canvas):** Main, Index (search + Hifz link), Read (paper/white/night, font 22–34, lock, swipe page turns), Listen, Reciters.

**Built:** —

**To build:** domain/: mushaf_page, ayah, bookmark · data/: quran_local_source (bundled Uthmani text, offline), audio_repository · presentation/: quran_main, quran_index, reader

**Rule:** Reader must be fully offline. Never send reading activity to analytics.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
