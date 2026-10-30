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
- **Agent tooling** (Claude Code project skills in `.claude/skills`, vendored as published; MIT/Apache licences inside):
  - `DESIGN.md` (repo root, Stitch / awesome-design-md format) is the design brief for agents. Its front matter is generated from `packages/design-tokens/tokens.json` (`pnpm --filter @yaqeen/design-tokens build`; `--check` fails on drift); edit the prose by hand.
  - Design: `impeccable` (critique/audit/polish; telemetry and its hook are off in `.impeccable/config.json`, and its engine is a checksum-verified download on first use), `taste-skill` (web pages only — run it with `--keep palette,type` so it keeps Yaqeen's tokens), `img2threejs` (image → Three.js model; don't run its installer or `img2` harness, which edit user settings).
  - `playwright-cli` drives a real browser for the admin and the API-rendered pages. In a cloud container point it at the bundled Chromium: `--config` with `{"browser":{"browserName":"chromium","launchOptions":{"executablePath":"/opt/pw-browsers/chromium-*/chrome-linux/chrome"}}}`.
  - Code graph: `pip install graphifyy` → `graphify extract . --code-only && graphify cluster-only . --no-label` (ignores in `.graphifyignore`, output `graphify-out/` is git-ignored); then `graphify query "…"`, `graphify explain X`, `graphify affected X` before cross-cutting changes.
  - None of these skills override the non-negotiables (brand, tokens, no ornament, RTL, privacy).
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
- **Observability & delivery:** errors via Sentry (`services/api/src/lib/observability.ts`, `apps/admin/src/sentry.shared.ts`, app `core/platform/error_reporter.dart`) — scrub everything personal; metrics `services/api/src/lib/metrics.ts` (route templates only); product analytics only through `PRODUCT_EVENTS` (closed list, never worship; a test mirrors it in Dart); deploys only through `.github/workflows/deploy.yml` / `tools/deploy/deploy.sh` (migrations backwards compatible).
- **Ramadan, widgets, website:** Ramadan mode in `features/ramadan` (on only with flag `ramadan` and a Ramadan/Sha'ban Hijri date; the log is device-only; Ramadan bonuses are claimed with the tick's date). Home-screen widgets read the snapshot from `features/home/data/widget_snapshot.dart` (written after each re-plan through `HomeWidgetPublisher`); native code in `android/.../NextPrayerWidget.kt` and `ios/YaqeenWidget/` — colours only from the generated `yq_tokens.xml` / `YqTokens.swift` (`pnpm --filter @yaqeen/design-tokens build`). The public website is `services/api/src/web/site-pages.ts` (no scripts; keep owner-only legal facts bracketed; bump `LEGAL_VERSION` when the policy changes) and `docs/STORE_LISTING.md` must match what the build collects.
- **Quran:** the mushaf text is never altered — search works on derived keys (`core/text/arabic.dart` `searchKey`) and highlights map back to the original. Reader state lives in `features/quran/presentation/reader_screen.dart` (spread, focus, memorise); annotations, stats and the khatma are device-only in `ReadingRepository` (writes go through `_serial`). Markers in the text are plain hairline pills (no ornament).
