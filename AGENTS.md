# AGENTS.md — Yaqeen (يقين)

Guide for any coding agent working in this repo (Codex, Cursor, Copilot, Claude, …).
**`CLAUDE.md` is the full operating manual and wins on any conflict.**
**`docs/APP_SPEC.md` is the product + UI/UX spec.** Read the section for a feature before you touch it.

## Repo map

| Path | What |
| --- | --- |
| `apps/mobile` | Flutter app (Riverpod, go_router), Arabic RTL first |
| `apps/admin` | Next.js 15 dashboard (Arabic RTL, Tailwind 4) |
| `services/api` | Fastify 5 + Drizzle + Postgres 16 + Redis 7 |
| `packages/contracts` | zod schemas shared by API + admin (mirrored in Dart) |
| `packages/design-tokens` · `packages/brand` | colours/radii/fonts · logo, icons, splash |
| `docs/` | spec, architecture, API, privacy, ADRs, release (`RELEASE_MOBILE.md`), packs (`CONTENT_PACKS.md`) |

## Setup and checks (run before saying "done")

```bash
pnpm install && docker compose up -d && pnpm db:migrate && pnpm db:seed   # first run
pnpm typecheck && pnpm test                                               # TEST_DATABASE_URL=… for Postgres tests
pnpm --filter @yaqeen/admin build
cd apps/mobile && flutter pub get && flutter gen-l10n && flutter analyze --no-fatal-infos && flutter test
```

- Golden tests live in `apps/mobile/test/goldens`. Update them with `flutter test --update-goldens <file>` only for
  intended visual changes. Look at the diff first.
- CI (`.github/workflows/ci.yml`) also builds the release APK and runs it on an Android emulator (`mobile-smoke`).
  Start-up must never block the first frame (`lib/app/bootstrap.dart`).

## Non-negotiables

1. Worship data never reaches ad platforms. Only contract `AD_EVENTS`, only with `ads_measurement` consent.
2. Admins see worship **aggregates only**.
3. The points ledger is append-only (new row + unique `ref_key`). Admin writes are audited.
4. Religious content publishes only after approval by a `religious_reviewer` who is not the author.
5. Marketing pushes respect prayer guardrails. Worship reminders are local notifications.
6. Offline first: Quran, prayer times, Qibla, azkar, duas, hifz, challenge ticks (Outbox).
7. Arabic RTL first, Western digits (`YqFormat.number`). English fully supported.
8. Brand: logo only from artwork (`YqLogo`). Colours only from tokens. No geometric ornament.
9. **No invented religious text.** Quran, tafsir, hadith and audio come only from licensed sources (spec §10).
   Placeholders stay visibly bracketed.

**Ask the owner before:** adding a paid service, a new ad/analytics event, changing points economics, or anything
touching user privacy.

## Conventions

- **Contracts first:** `packages/contracts/src/api.ts` → API route → admin → Dart model + parse test.
- **Mobile layering:** `features/<x>/{domain,data,presentation}`. Platform plugins go behind `core/` interfaces with
  no-op defaults, overridden in `main.dart`.
- **Strings:** `lib/l10n/app_ar.arb` (template) + `app_en.arb`. No hard-coded user-facing text.
- **RTL icons:** never swap `chevron_left`/`chevron_right` (or arrows) by text direction yourself. They are
  `matchTextDirection` and Flutter mirrors them. Use the LTR glyph (back = left, forward = right).
- **Design system:** read `docs/DESIGN_SYSTEM.md` before building a screen.
  - Every screen sits on `AmbientBackground`, which follows the living sky (`core/design/living_sky.dart`). Pass
    `lights:` only for accents (`goldLights` on reward, challenge and calendar screens).
  - Every screen is a `YqCanvas`: a `YqStage` (living sky; `compact` on pushed screens, `gold` on reward screens) with a `YqStageBar` and one `YqMoment`, then up to three `YqOrb`s, then a `YqTimeline` / `YqGroup`s / lazy `slivers`. The reader and splash are the only exceptions (DESIGN_SYSTEM §3).
  - Tab bar = the living dock (`FloatingTabBar`).
  - Shadows under translucent glass go through `OuterShadow` (never a plain `BoxShadow` under a see-through fill).
  - Loading states are shaped like the content: `YqSkeletonOrbs`, `YqSkeletonRows`, `YqSkeletonText`, `YqSkeletonBox.circle`.
- **Public card (بطاقة يقين):** opt-in; shows only switched-on fields and never worship detail (CLAUDE.md rules 1–2). Server page in `services/api/src/web/profile-page.ts` (escape every user string; https links only); app in `features/card` (journey: `journey_widgets.dart`, Profile tab `JourneySection`); physical medals/cards: `services/tags.service.ts`, `routes/admin/tags.routes.ts`, `/t/:code` in `profile.routes.ts`, app «ميدالياتي» sheet in `card_screen.dart` (the app does not write NFC); admin programme in `routes/admin/cards.routes.ts` + `services/{cards-settings,card-stats}.service.ts`, pages `apps/admin/src/app/(dash)/{cards,tags}`.
  - Tests pin the sky with the harness `skyClock:` so goldens are deterministic.
- **Routine:** `quranSlot`/`hifzSlot`/`dhikrSlot` (`RoutineSlot`) drive Home's «Your day» stops and local reminders.
  They are device-only and never go in `serverPatch()`.
- **Performance:**
  - Live blur (`LiquidGlass(blur: …)`, `BackdropFilter`) only on fixed chrome, never on cards inside scroll views.
  - Long lists are lazy (`SliverList.builder` / `ListView.builder`).
  - Per-second tickers wrap only the text that changes, inside a `RepaintBoundary`.
  - Watch providers with `.select` for the fields you use.
  - Heavy parsing/hashing goes off the UI isolate (`compute` / `Isolate.run`).
- **Downloads:** go through the app-wide `DownloadQueue` (`core/network/download_queue.dart`). Never tie them to a
  screen's lifetime.
- **API:** pure logic in `src/domain` (unit-tested), DB orchestration in `services/`, HTTP in `routes/`. Use stable
  snake_case error codes.
- **Schema change:** `pnpm db:generate`, then commit the SQL. CI fails on drift.
- **Never commit** secrets, signing material (`key.properties`, keystores, `Secrets.xcconfig`) or licensed content packs.
