# ADR 0007 — Quran text from pinned open data; prayer engine ported to Dart

**Status:** accepted for development · licence choice open (spec §13.1) · 2026-10

**Context.** Rule 9 forbids invented religious text; the mushaf must work offline on day one (spec §5.8) and prayer times must match the Egyptian General Authority within a minute (§5.5). The sandbox that builds the app cannot reach Tanzil or AlAdhan.

**Decision.**
- **Quran text:** `tools/quran/build_quran.py` builds `assets/quran/quran.json` from pinned npm packages — `quran-json@3.1.2` (CC-BY-4.0, Uthmani text from QuranEnc/KFGQPC) and `quran-meta@7.0.0` (MIT, Madani page/juz/hizb boundaries). The text is never edited; a test pins the asset's SHA-256 and checks 6,236 ayat on 604 pages. Swapping to another licensed source is a rebuild, not a code change.
- **Fonts:** Amiri Quran (OFL) bundled; KFGQPC page fonts become an optional pack once licensed.
- **Prayer times:** a pure-Dart port of the adhan-js astronomy (`features/prayer/domain`), golden-tested against the JS reference for 8 cities, both Asr schools and DST (`tools/prayer/golden.mjs`). Times are UTC instants shown in the place's IANA zone (`timezone` package), so travel and Egypt's DST are handled without the device zone.

**Consequences.** Fully offline Quran and prayer from install. Before launch the owner confirms the text licence (attribution in About) and a spot-check against the official Egyptian timetable for Cairo, Alexandria and Aswan.
