# Roadmap

## Open decisions (owner: product)

| # | Decision | Default in code |
| --- | --- | --- |
| 1 | Bonus points: white days +30, Mon/Thu fasting +30, Kahf on Friday +20 | Seeded but **disabled** |
| 2 | Qada window | 7 days (editable in the dashboard) |
| 2b | Streak milestones: 7 d +50, 30 d +200, 100 d +500 | Seeded but **disabled** |
| 3 | Free-shipping reward cost (4,000) vs. actual shipping cost | 4,000 |
| 4 | "باكدج الطمأنينة" discount value | Not seeded |
| 5 | Use an MMP (AppsFlyer/Adjust)? | No |
| 6 | Religious review of all seeded content (one sample zikr is seeded as draft) | Draft |
| 7 | PDPL: hosting region, licence, DPO, transfer authorisation | — |
| 8 | Licences for ZEYADA Arabic 1 + Canela Text (desktop, **app embedding**, web) and the font files | Fallback fonts |
| 9 | Vector (SVG/PDF) logo masters from the designer — only PNGs were delivered | PNG up to 4500 px |

## Phase 1 — foundation ✅ (this repo)

- API: auth (Google/Apple/guest), consents with history, challenge engine (idempotent, offline-safe, qada cap), rewards → Shopify codes with refunds, content review workflow, campaigns with guardrails + dispatcher, remote config, Hijri with Egypt adjustment, admin RBAC + audit. 61 tests (7 against real Postgres).
- Points program fully controlled from the dashboard: daily total, qada cap & window, challenge length, task names/values/on-off, streak milestones, bonuses, bulk grants, reward catalogue with caps, per-user limits and validity.
- Admin: login with 2FA, overview, users, content review, campaigns with lock-screen preview, points & rewards, settings (Hijri, flags, team, audit).
- Mobile: design system, shell + router, network/outbox/analytics/notification planning, challenge + redeem screens, repositories for challenge/rewards/calendar/auth/consents.

## Phase 2 — app features

- [ ] Onboarding flow (7 screens) + Google/Apple sign-in + consent screen
- [ ] Prayer times on-device (`adhan`), Qibla, notification settings → `flutter_local_notifications`
- [ ] Quran reader (offline Uthmani text, paper/white/night, lock, swipe), index & search, bookmarks
- [ ] Listening + reciters (audio streaming & downloads)
- [ ] Azkar & duas with counters, synced from `/v1/content?since`
- [ ] Merged Hijri × 365 calendar screen with qada
- [ ] Hifz (Juz Amma plan, review card using `ReviewScheduler`)
- [ ] FCM push + inbox; ad SDK sinks with ATT
- [ ] Profile, settings, data export & delete

## Phase 3 — hardening before launch

- [x] Erasure job for `deletion_requested` users (30-day grace, `job:purge`)
- [x] Admin TOTP secrets sealed at rest (`ADMIN_SECRETS_KEY`, AES-256-GCM)
- [x] The approved content version stays live while an edit is in review (`content_items.live`)
- [x] Shopify webhook (`orders/paid`) → redemption `used` (signed, idempotent). Server-side `purchase` to ad platforms is **not** built — needs a decision (new third-party data flow)
- [x] Unused codes → `expired` (daily, in `job:purge`)
- [x] Dispatcher uses each user's picked city (coarse coordinates) + prayer method, else their zone's largest city, else Cairo
- [x] Load test (`pnpm --filter @yaqeen/api load`); Sentry + Prometheus
- [ ] App Store privacy labels & Play data-safety form from SECURITY_PRIVACY.md
