# quran

**Screens (spec §5.10–5.13, §5.25, §5.30):** Quran index (`presentation/quran_index_screen.dart`: continue reading or «أكمل جلستك», ayah search, wird · khatma · listen orbs, surahs / juz / saved, long-press → modes sheet), the reader «صفحة واحدة» (`reader_screen.dart` + `madani_page.dart` / `mushaf_page.dart`): the printed page is the only Quran surface; reading, listening, memorising and reciting are layers on it (`presentation/session/`), switching never pushes a route. The ayah sheet (layers «من هنا · إلى هنا», tafsir, notes, highlights, bookmarks), the khatma planner (`khatma_screen.dart`). The player sheet and mini player live in `features/listen`, the hifz plan and grade sheet in `features/hifz`, the recite controller in `features/recite`.

**Built:**
- `domain/`: `quran_data.dart` (bundled Uthmani text, pages, juz / hizb / sajdah), `passage.dart` (`Passage`, `QuranMode`, bundled surah → page table), `quran_session.dart` (wird · khatma · hifz · review · free; stages, staleness, JSON), `ayah_search.dart` (Uthmani ↔ everyday spelling), `wird.dart` (`WirdRules`, `WirdClock`), `khatma.dart`, `reading_stats.dart`, `annotations.dart` (highlights, notes, coloured bookmarks).
- `data/`: `quran_repository.dart` (parses the bundled text off the UI isolate), `reading_repository.dart` (last read, wird, khatma, annotations; serialised writes), `tafsir_repository.dart` (installed tafsir packs).
- `data/session_store.dart`: the running session, device-only (KV `quran.session.v1`; never in backup, export, analytics or admin; wiped on account deletion, kept on sign-out).
- `presentation/`: the screens and sheets above, `quran_providers.dart`, `ayah_results.dart`, `jump_sheet.dart`, `note_sheet.dart`.
- `presentation/session/`: `QuranModeDock`, the read / listen / memorise / recite strips, `follow_audio.dart`, `active_session.dart` (saved on every change), `session_line.dart`, `session_start_sheet.dart`, `session_end_card.dart`, `passage_picker_sheet.dart`, `quran_entry.dart` (Home's `startWirdSession`, `openQuranListen`, `quranResumeProvider`).

**Rule:** The reader is fully offline. Reading activity never goes to analytics or to the server (only the opt-in encrypted backup). Tafsir text comes only from a licensed pack; until then it stays bracketed.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; local store, packs) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
