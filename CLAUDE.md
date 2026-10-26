# CLAUDE.md — Yaqeen (يقين)

You are building **Yaqeen**, a premium Islamic app (iOS + Android) with an API and an admin dashboard.
This file is your operating manual. The full product + UI/UX spec is **`docs/APP_SPEC.md`** — read the
section for a feature before you touch it. Tickets are in `docs/APP_SPEC.md §12 Build plan`.

## Repo map

| Path | What | Run |
| --- | --- | --- |
| `apps/mobile` | Flutter app (Riverpod, go_router) | `cd apps/mobile && flutter pub get && flutter gen-l10n && flutter test` |
| `apps/admin` | Next.js 15 dashboard (Arabic RTL, Tailwind 4) | `pnpm dev:admin` · `pnpm --filter @yaqeen/admin build` |
| `services/api` | Fastify 5 + Drizzle + Postgres 16 + Redis 7 | `pnpm dev:api` · `pnpm --filter @yaqeen/api test` |
| `packages/contracts` | zod schemas shared by API + admin (mirrored in Dart) | `pnpm --filter @yaqeen/contracts build` |
| `packages/design-tokens` | colours, tints, gradient, radii, fonts → generated CSS | `pnpm --filter @yaqeen/design-tokens build` |
| `packages/brand` | logo masters, app icons, splash layers + generator | `python3 packages/brand/scripts/generate.py` |
| `docs/` | spec, architecture, data model, API, privacy, notifications, analytics, conventions, roadmap, ADRs | |

First run: `pnpm install && docker compose up -d && pnpm db:migrate && pnpm db:seed` (see README).

## Before you say "done"

```bash
pnpm typecheck && pnpm test                                   # add TEST_DATABASE_URL=… for Postgres tests
pnpm --filter @yaqeen/admin build
cd apps/mobile && flutter analyze --no-fatal-infos && flutter test
```

A ticket is done when its **acceptance criteria** in the spec pass, tests cover the logic, and the
screen matches its design artboard (spacing, type, colour, RTL, states). Say exactly what you verified.

## Non-negotiables (break none of these)

1. **Worship data never reaches ad platforms.** Only `AdEvent` values (contracts `AD_EVENTS`) go to Google/Meta/TikTok, only with `ads_measurement` consent. No API exists to send worship events; don't add one.
2. **Admins see aggregates only** for worship. Per-user views show points ledger + redemptions, never which prayers/azkar.
3. **Points ledger is append-only.** Never update a balance. New row + unique `ref_key`. Admin writes are audited in the same transaction.
4. **Religious content** (duas, azkar, daily task, splash verse) publishes only after a `religious_reviewer` who is not the author approves it.
5. **Marketing pushes respect prayer**: server guardrails (quiet hours, ±prayer windows, Jumu'ah, daily cap, consent). Worship reminders are **local** notifications.
6. **Offline first** for Quran, prayer times, Qibla, azkar, duas, hifz and challenge ticks (Outbox).
7. **Arabic RTL first, Western digits** everywhere (`YqFormat.number`, `ar-EG-u-nu-latn`). English fully supported.
8. **Brand**: logo only from artwork (`YqLogo`, `/brand/*.png`) — never typeset «يقين» as a logo. Colours only from tokens. Light porcelain UI, blue as accent, liquid glass. No geometric ornament in the app.
9. **No invented religious text.** Quran text, tafsir, hadith sources and audio come from licensed sources (spec §10). Placeholders stay visibly bracketed: `[نص التفسير من المصدر المرخّص]`.

## How to work here

- **Contracts first**: change `packages/contracts/src/api.ts` → API route → admin → Dart model + parse test.
- **Mobile layering**: `features/<x>/{domain,data,presentation}`; presentation → controller (Riverpod) → repository → `ApiClient`. Platform plugins sit behind interfaces in `core/` with no-op defaults, overridden in `main.dart`.
- **Strings**: `apps/mobile/lib/l10n/app_ar.arb` (template) + `app_en.arb`. No hard-coded user-facing text except Quran/hadith content.
- **API**: pure logic in `services/api/src/domain` (unit-tested), DB orchestration in `services/`, HTTP in `routes/`. Stable snake_case error codes.
- **Schema change** → `pnpm db:generate` → commit the SQL. CI fails on drift.
- **Design source of truth**: the canvas artboards named in each spec section (links in `docs/APP_SPEC.md §0`). When code and design disagree, the spec text wins, then the artboard.
- Ask before: adding a paid service, a new ad/analytics event, changing points economics, or anything touching user privacy.

## Current state (keep updated)

Built and tested: API (auth + guest link, consents, challenge engine + qada days, rewards → Shopify with idempotent redeem, content review with stable categories, campaigns + dispatcher, remote config, Hijri + Egypt offset, admin RBAC/audit, points program, response cache, k8s deploy) · Admin (all sections incl. §7.2 gaps) · Mobile: every screen in `docs/APP_SPEC.md §5.1` (onboarding, home, Quran index/reader/listen/reciters/hifz, prayer/qibla/notifications/inbox, azkar, duas, challenge, calendar, redeem, profile), native iOS/Android projects. Start-up can't hang (`lib/app/bootstrap.dart`: time-boxed steps, plugins after first frame, `YQ-BOOT` logs; CI `mobile-smoke` runs the release APK on an emulator). Large downloads share one app-wide `DownloadQueue` (parallel, resumable across launches). Perf rules: live blur only on fixed chrome (tab bar), lazy slivers for long lists, per-second tickers wrap only their text; tabs cross-fade (`TabBranches`). `AGENTS.md` mirrors this manual for other agents. Home (§5.9) is a "living canvas" whose light follows the day (palette blended continuously between keyframes at the real prayer times — `skyPaletteAt` in `core/design/living_sky.dart`; the page glow sits under the sun's arc position): edge-to-edge sky stage (greeting, next prayer in large type, countdown, sun/moon on the day arc) → three complication orbs (Qibla orbit — Kaaba reaches the top when faced, sensor only while visible; misbaha tasbeeh, local count; liquid wird) → «Your day» timeline (prayers + azkar windows, «now» marker carrying continue-reading, challenge last) → services; goldens `test/goldens/home_{ar,en}.png`. Onboarding step 05·ب «Routine» picks when the user reads Quran / reviews hifz / does dhikr (after a prayer + minutes, a set time, or off; device-only `RoutineSlot`s); Home's timeline and local reminders follow it, editable in Notification settings «روتيني». Design system: `docs/DESIGN_SYSTEM.md` — every screen (except reader/splash) is a `YqCanvas`: living-sky `YqStage` with one large moment → `YqOrb` complications → `YqTimeline`/`YqGroup`s (per-screen table in §3); the tab bar is the living dock (ink lens lit by the sky, day thread). Public card «بطاقة يقين» (§5.26): opt-in `public_profiles` + `GET /u/<handle>` API-rendered page (themes sky/gold/night, CTA to `/get-app` and the store, open counter, support can hide it — audited) + app editor `/profile/card` and a branded QR; physical **Yaqeen key medals/cards** (sold in the store) carry permanent codes `/t/<code>` minted in admin batches (`profile_tags`, CSV for the manufacturer), activated once in the app («ميدالياتي», deep link `yaqeen://tag/<code>`), follow the handle, switch off when lost — the app no longer writes NFC; admin runs it all: `/cards` (directory + moderate/restore/release handle, settings for medal product link / shop link / CTA copy / reserved handles, daily-counter numbers) and `/tags` (batch status ordered→received→on sale, void, assign to a customer), switches `publicCards`/`medalActivation`; levels from lifetime points (`levelFor`, mirrored in Dart); opt-in journey timeline (`/v1/me/journey`, `JourneyRail`; full private journey on the Profile tab); page + preview animate (rolling digits, drawn rail, reduced-motion safe); never worship detail. Glass shadows paint outside shapes only (`OuterShadow`); skeletons are shaped (`YqSkeletonOrbs/Rows/Text`) with one RTL-aware shimmer.
Waiting on owner decisions/licences (§13): Quran fonts/Indo-Pak text, tafsir pack, recitations + timings, adhan audio, ASR model for `recite`, OAuth/Shopify/FCM credentials, Crashlytics (Firebase), the App Store listing URL, a vanity domain for cards (`PUBLIC_PROFILE_BASE_URL` — set it **before minting the first medal batch**: the `/t/<code>` URL is burned into every chip and QR), the medal/card product in the store + its manufacturer, and AASA/assetlinks on the store theme. Placeholders stay bracketed and features stay flagged until then.
