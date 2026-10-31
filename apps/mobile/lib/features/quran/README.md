# quran

**Screens (spec §5.10–5.11, §5.30):** Quran index (`presentation/quran_index_screen.dart`: continue reading, ayah search, wird · khatma · listen orbs, surahs / juz / saved), the reader (`reader_screen.dart` + `mushaf_page.dart`: paper / white / night, font 22–34, page turns, «انتقل إلى», markers, memorise mode), the ayah sheet (tafsir, notes, highlights, bookmarks), the khatma planner (`khatma_screen.dart`). Listen and reciters live in `features/listen`, hifz in `features/hifz`.

**Built:**
- `domain/`: `quran_data.dart` (bundled Uthmani text, pages, juz / hizb / sajdah), `ayah_search.dart` (Uthmani ↔ everyday spelling), `wird.dart`, `khatma.dart`, `reading_stats.dart`, `annotations.dart` (highlights, notes, coloured bookmarks).
- `data/`: `quran_repository.dart` (parses the bundled text off the UI isolate), `reading_repository.dart` (last read, wird, khatma, annotations; serialised writes), `tafsir_repository.dart` (installed tafsir packs).
- `presentation/`: the screens and sheets above, `quran_providers.dart`, `ayah_results.dart`, `jump_sheet.dart`, `note_sheet.dart`.

**Rule:** The reader is fully offline. Reading activity never goes to analytics or to the server (only the opt-in encrypted backup). Tafsir text comes only from a licensed pack; until then it stays bracketed.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; local store, packs) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
