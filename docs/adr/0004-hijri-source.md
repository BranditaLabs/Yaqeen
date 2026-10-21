# ADR 0004 — Hijri dates from Umm al-Qura with an Egypt adjustment

**Status:** accepted · 2026-10

**Context.** Users expect the Egyptian (Dar al-Ifta) date, which can differ from computed calendars by a day after moon sighting.

**Decision.** AlAdhan `calendarMethod=UAQ` as the base, cached per month. A religious reviewer sets a regional ±1 offset effective from a Hijri month; the API refuses adjustments that create a month that is not 29 or 30 days. Users may add a personal ±2 offset.

**Consequences.** One manual action per disputed month, fully audited. Depends on AlAdhan availability — cached for 30 days, and the app caches months offline.
