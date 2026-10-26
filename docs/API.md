# API reference

Base URL: `API_URL` (local `http://localhost:4000`). JSON only. Schemas: `packages/contracts/src/api.ts`.

**Errors** are always `{ "error": { "code": "snake_case", "message": "…", "details"?: … } }`. Clients branch on `code`, never on `message`.

**Auth:** app routes use `Authorization: Bearer <accessToken>` (15 min). Admin routes use the admin token (different secret + audience). Rate limits: 300 req/min/IP globally; sign-in and link 10/min; admin login 5 per 5 min; redeem 5/min.

## Public — app

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET | `/health` · `/ready` | — | Liveness · readiness (DB + Redis) |
| POST | `/v1/auth/sign-in` | — | `{provider: google\|apple\|guest, idToken?, displayName?, locale}` → session |
| POST | `/v1/auth/refresh` | — | `{refreshToken}` → new session; old token revoked |
| POST | `/v1/auth/sign-out` | user | Revokes all refresh tokens |
| POST | `/v1/auth/link` | guest | `{provider: google\|apple, idToken}` → session. New identity: the guest becomes the account. Existing identity: guest points move over as two ledger rows (`merge-out:` / `merge:`), audited, guest sessions revoked. `not_a_guest` if already linked |
| GET | `/v1/config` | — | Remote config: `features` (+ `featureRollout` %), min versions, maintenance, splash verse, Hijri offset, `points` (incl. `dailyTotal`, `cheapestRewardPoints`). Cached 5 min |
| GET | `/v1/calendar/hijri?year&month&offset` | — | Gregorian month → Hijri days (UAQ + Egypt adjustment + personal offset) |
| GET | `/v1/content?type&since` | — | Published duas/azkar only; `since` for incremental sync |
| GET | `/v1/content/reciters` | — | Active licensed recitations `{id, nameAr, nameEn, style, riwaya, baseUrl, timingUrl, sampleUrl, sizeBytes}`. Files: `<baseUrl>/<sss>.mp3` (zero-padded surah); `timingUrl` → `{"<surah>": [[startMs, endMs], …]}` (index 0 = ayah 1). The CDN must honour `Range` (resumable downloads). |
| GET | `/v1/content/packs` | — | Downloadable packs `{id, kind, version, url, sha256, sizeBytes}` — verify sha256 before installing |
| GET | `/v1/daily-task?date` | — | مهمة اليوم |
| GET | `/v1/me` | user | Profile + settings |
| PATCH | `/v1/me/settings` | user | Partial `UserSettings` |
| GET · PUT | `/v1/me/consents` | user | 4 buckets; PUT records an immutable consent event |
| POST | `/v1/me/devices` | user | Register/refresh FCM token |
| GET | `/v1/me/ledger` · `/v1/me/redemptions` | user | Points history · issued codes |
| POST | `/v1/me/campaigns/:id/opened` | user | Push opened; idempotent (`{counted}`), feeds open rate |
| GET | `/v1/me/export` | user | PDPL data access — everything held about the user |
| GET · PUT | `/v1/me/public-profile` | user (PUT: not guest) | «بطاقة يقين» settings: handle, name, bio, ≤ 8 links, visibility switches, theme; GET returns a suggested draft before the first save, plus `url` and `views`. Errors `handle_taken` (409), `handle_reserved`, `account_required` |
| GET | `/v1/me/public-profile/available?handle=` | user | `{available}` |
| GET | `/go/store?src=card·medal·missing&ref=` | — | The card page's shop button: counts the click, 302 to the store (admin link or `STORE_URL`) with UTM |
| GET | `/t/:code` | — | A physical tag: 302 → `/u/<handle>` when activated and published (no-store), activation page when blank, 404 page otherwise |
| POST | `/v1/me/events` | user (30/min) | Consented product events `{anonId, platform, appVersion, locale, events[≤50] {name, props, at}}` → `202 {accepted}`; only `PRODUCT_EVENTS` with allowed values are kept, nothing without the `product_analytics` consent, never linked to the account |
| GET · POST | `/v1/me/tags` | user (POST: not guest; 10 / 10 min) | Key medals / cards: list the active ones `[{code, kind, url, linkedAt, scans}]`; activate `{code}` (any case, dashes, or a pasted `/t/` link). Errors `not_found` (unknown, taken or switched off — indistinguishable), `tag_limit` (409, max 10), `account_required` |
| DELETE | `/v1/me/tags/:code` | user | Switch a lost tag off for good (204) |
| GET | `/v1/me/journey` | user | Private journey (`MyJourney`): `lifetimePoints`, `level {…, nextAt}`, `streak`, `challengeDay`, `challengeOf`, `events[] {kind: joined·challenge_start·challenge_day·level·badge, date, value}` newest first. The public view adds `timeline` (≤ 12 events) only when `show.timeline` is on |
| GET | `/v1/public/profiles/:handle` | public | What a scanner sees (cached 60 s): level, streak, challenge day, badges, member since — each only if switched on; never worship detail. 404 when unpublished |
| GET | `/u/:handle` | public | The card as a script-free HTML page (Arabic/English by browser) with the get-the-app and store CTAs; counts human opens |
| GET | `/get-app` | public | Smart redirect to Google Play / the App Store by user agent (store site otherwise) |
| DELETE | `/v1/me` | user | PDPL erasure request (202, 30-day grace). Sessions and devices end at once; `job:purge` anonymises after 30 days (ledger kept). Signing in again during the grace period cancels the request |
| POST | `/v1/challenge/enroll` | user (not guest) | Starts day 1 today |
| GET | `/v1/challenge/summary` | user | Day number, streak, balance, today, task values |
| GET | `/v1/challenge/days?from&to` | user | ≤ 92 days; status per day for the merged calendar |
| GET | `/v1/challenge/calendar?month=YYYY-MM` | user | Merged month: Hijri day + `challenge` status (null outside the journey) + `special` pips, plus journey, qada window, points |
| POST | `/v1/challenge/tasks/:task/complete` | user | `{date, clientEventId}` → `{awarded, milestoneAwarded, day}`; idempotent; qada within the admin-set window |
| POST | `/v1/challenge/bonuses/:kind/claim` | user | Today only; eligibility computed server-side from the Hijri date |
| GET | `/v1/rewards` | user | Catalogue with `available` for the caller's balance |
| POST | `/v1/rewards/:id/redeem` | user | Debits points, creates a single-use Shopify code; refunds on Shopify failure. Send `Idempotency-Key` (one per confirm tap): a retry returns the same code without a second debit (`redemption_in_progress` while the first is still with Shopify) |

## Admin

Roles: `super_admin` (always allowed), `content_editor`, `religious_reviewer`, `marketing`, `support`.

| Method | Path | Roles |
| --- | --- | --- |
| POST | `/admin/auth/login` | — (email + password + TOTP) |
| GET | `/admin/auth/me` | any |
| GET | `/admin/overview` | any — aggregates only |
| GET | `/admin/overview/series?metric=dau&range=7d\|30d\|90d` | any — daily active users; days with 1–19 users are `null` |
| GET | `/admin/overview/funnel` · `/admin/overview/adherence?date` | any — k-anonymity ≥ 20 (`null` when suppressed) |
| GET | `/admin/overview/alerts` | any — pending reviews, tomorrow's task missing, low reward stock, Shopify errors, moon sighting |
| PUT | `/admin/auth/me/test-devices` | any — `{tokens[]}` (≤ 5) for campaign test sends |
| GET | `/admin/users` · `/admin/users/:id` | support, marketing — masked email, no worship history |
| POST | `/admin/users/:id/points` | support — reason required, ≤ 5,000, audited |
| POST | `/admin/users/:id/status` | support — reason required, audited |
| GET | `/admin/users/:id/export` | support — PDPL export, audited. Worship history and ledger ref keys excluded |
| GET | `/admin/content` | content_editor, religious_reviewer |
| POST · PUT | `/admin/content` · `/admin/content/:id` | content_editor — edits return the item to draft |
| POST | `/admin/content/:id/submit` | content_editor |
| POST | `/admin/content/:id/review` | religious_reviewer — not on your own edit |
| GET · PUT | `/admin/content/daily-tasks` | read: editor/reviewer · write: content_editor |
| GET | `/admin/campaigns` · `/admin/campaigns/stats` | marketing |
| POST | `/admin/campaigns/preview` | marketing — reach estimate + copy lint |
| POST | `/admin/campaigns` | marketing — copy lint must pass |
| POST | `/admin/campaigns/:id/cancel` | marketing |
| POST | `/admin/campaigns/test` | marketing — admin's own test devices only; copy lint applies |
| GET | `/admin/rewards/program` | marketing, support — settings, all six tasks, bonuses, milestones, totals by reason |
| PUT | `/admin/rewards/program` | super_admin — `{settings, tasks[6]}`; active task points must equal `dailyTotal`; qada cap ≤ daily total |
| PUT | `/admin/rewards/milestones` | super_admin — replaces the list of automatic streak bonuses |
| PUT | `/admin/rewards/bonus-rules/:kind` | super_admin |
| GET | `/admin/rewards/grants` | marketing, support |
| POST | `/admin/rewards/grants/preview` · `/admin/rewards/grants` | super_admin — gift points to a segment; one ledger row per user, idempotent |
| GET · POST · PUT | `/admin/rewards` · `/admin/rewards/:id` | read: marketing, support · write: marketing — cost, value, validity, monthly cap, per-user monthly limit, collections |
| GET | `/admin/rewards/redemptions` | marketing, support |
| GET | `/admin/rewards/shopify/status` | marketing, support — `{configured, connected, shopName, domain, scopes, lastError}` |
| GET | `/admin/rewards/shopify/collections?search` | marketing |
| GET | `/admin/settings/config` | any |
| PATCH | `/admin/settings/config` | super_admin — not `hijri`, `points` or `splashVerse` (own endpoints) |
| PUT | `/admin/settings/splash-verse` | content_editor — creates a `splash_verse` item in review; live after a reviewer (≠ author) approves |
| POST | `/admin/settings/hijri/preview` · `/admin/settings/hijri` | religious_reviewer — save blocked if the preview has warnings |
| GET | `/admin/settings/audit` | super_admin |
| GET · POST · PATCH | `/admin/settings/team` · `/admin/settings/team/:id` | super_admin — new admin's TOTP secret is returned once |

### Public profile moderation

| GET | `/admin/analytics?days=30` | marketing, support | Product analytics aggregates (`ProductAnalyticsReport`); counts under 20 are `null` |
| GET | `/admin/cards?search=&status=published·hidden·moderated` | support, marketing | Cards directory (public fields, opens, active medals) |
| POST | `/admin/cards/:userId/moderate` · `/restore` · `/release-handle` | support | `{reason}`, audited. Moderated cards 404 and the owner's PUT `published:true` → 403 `card_moderated` |
| GET · PUT | `/admin/cards/settings` | read: support, marketing · write: marketing | `CardsSettings` (https links, CTA copy ar/en, reserved handles), audited |
| GET | `/admin/cards/stats?days=30` | support, marketing | `CardsStats`: daily counters + totals, published cards, active tags, activation per batch |
| PATCH | `/admin/tags/batches/:batch` | marketing | `{status: ordered·received·on_sale, note}`, audited |
| POST | `/admin/tags/batches/:batch/void` | marketing, support | `{reason}`: batch void + every tag switched off, audited |
| POST | `/admin/tags/:code/assign` | support | `{userId, reason}`: link a blank tag to an active signed-in account, audited |
| GET · POST | `/admin/tags/batches` | read: support, marketing · mint: marketing | Batches with totals; mint `{batch, kind: medal·card, count ≤ 5000}` (audited, `batch_exists`) |
| GET | `/admin/tags/batches/:batch.csv` | support, marketing | `code,printed_code,url,kind` for the manufacturer (NFC NDEF URI + QR print) |
| GET | `/admin/tags?batch=&status=unclaimed·active·disabled&code=` | support, marketing | Tags with the linked card's handle (never worship) |
| POST | `/admin/tags/:code/disable` · `/release` | support | Switch off (e.g. reported lost) / re-issue as blank; `{reason}`, audited |
| POST | `/admin/users/:id/public-profile/unpublish` | support | Hide a user's public card (`{reason}`), audited. The user detail includes `publicProfile {handle, published, views, url}` |

## Common error codes

`validation_failed` · `unauthorized` · `invalid_token` · `role_not_allowed` · `account_required` · `account_suspended` · `not_enrolled` · `future_date` · `before_enrollment` · `outside_qada_window` · `already_completed` · `task_inactive` · `insufficient_points` · `reward_out_of_stock` · `shopify_unavailable` · `not_a_guest` · `no_test_devices` · `push_not_configured` · `use_splash_verse_endpoint` · `user_reward_limit_reached` · `bonus_not_eligible` · `bonus_already_claimed` · `cannot_review_own_edit` · `not_pending_review` · `invalid_total` · `duplicate_task` · `use_program_endpoint` · `hijri_invalid_sequence` · `copy_issues`
