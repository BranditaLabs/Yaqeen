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
| GET | `/v1/content?type&since` | — | The reviewer-approved version of each dua/zikr (an edit in review keeps serving the last approved one); `since` compares the approval time for incremental sync |
| GET | `/v1/content/reciters` | — | Curated recitations (active, `sort_order`) `[{id, nameAr, nameEn, style: murattal\|mujawwad\|muallim, riwaya, source: qf\|own, qfId, hasTimings, baseUrl, timingUrl, sampleUrl, sizeBytes}]`. `qf` = Quran.com / Quran Foundation (resolve each surah below; `baseUrl` null). `own` = our CDN: `<baseUrl>/<sss>.mp3` + `timingUrl`. Cache 1 h + ETag. |
| GET | `/v1/content/reciters/:id/surahs/:n` | — | `{reciterId, surah, url, sizeBytes, durationMs, timings: [[startMs, endMs], …] \| null}` (index 0 = ayah 1, from QF verse timestamps). QF audio is served by their CDN (`Range` supported). Unknown/inactive reciter or `n ∉ 1…114` → 404 `not_found`; upstream down → 503 `content_unavailable`. Cache 24 h + ETag. |
| GET | `/v1/content/reciters/:id/timings` | — | Every surah's timings `{"<surah>": [[startMs, endMs], …]}` — the app's offline `timings.json` (built from the per-surah answers, cached 24 h). `own` reciters → 302 to `timingUrl`. |
| GET | `/v1/content/tafsirs` | — | Curated tafsirs `[{id, nameAr, nameEn, language, authorAr, authorEn, source: "qf", attribution}]` — `muyassar` first, `ibn-kathir`, `saadi`, `ibn-kathir-en`. |
| GET | `/v1/content/tafsirs/:id/surahs/:n` | — | `{tafsirId, surah, attribution, ayat: {"s:a": text}}` — plain text (HTML tags, scripts and `<sup>` footnotes stripped; entities decoded). A commentary covering several ayat is keyed by the first; the others are absent. 404 / 503 as above. Cache 24 h + ETag. |
| GET | `/v1/content/tafsirs/:id/by-ayah/:key` | — | `{tafsirId, ayahKey, text, attribution}` for one ayah (`2:255`); a grouped commentary is returned for each ayah it covers. Invalid key → 404. |
| GET | `/v1/content/packs` | — | Downloadable packs `{id, kind, version, url, sha256, sizeBytes}` — verify sha256 before installing |
| GET | `/v1/daily-task?date` | — | مهمة اليوم |
| GET | `/v1/me` | user | Profile + settings |
| PATCH | `/v1/me/settings` | user | Partial `UserSettings` |
| GET · PUT | `/v1/me/consents` | user | Buckets `worship_reminders`, `challenge_rewards`, `store_offers`, `ads_measurement`, `product_analytics`, `cloud_backup`; PUT records an immutable consent event. Granting `cloud_backup` needs a full account (`account_required` for guests); withdrawing it deletes the user's backups in the same transaction |
| POST | `/v1/me/devices` | user | Register/refresh FCM token |
| GET | `/v1/me/ledger` · `/v1/me/redemptions` | user | Points history · issued codes |
| POST | `/v1/me/campaigns/:id/opened` | user | Push opened; idempotent (`{counted}`), feeds open rate |
| GET | `/v1/me/export` | user | PDPL data access — everything held about the user, including `backups[]` (the cloud backup, opened). The admin export never includes backups |
| GET | `/v1/me/backup` | user (not guest, `cloud_backup` granted) | Cloud backup manifest `{kinds: [{kind, version, updatedAt}]}` — never the content. See › Cloud backup |
| GET | `/v1/me/backup/:kind` | same | `{kind, version, updatedAt, data}`; 404 when that kind was never written |
| PUT | `/v1/me/backup/:kind` | same (60/min) | `{baseVersion, data, deviceId?}` → `{version, updatedAt}`. Optimistic concurrency: `baseVersion` must equal the current version (0 = none yet), else 409 `backup_conflict` with the current document in `details`; the app merges and retries |
| GET · PUT | `/v1/me/public-profile` | user (PUT: not guest) | «بطاقة يقين» settings: handle, name, bio, ≤ 8 links, visibility switches, theme; GET returns a suggested draft before the first save, plus `url` and `views`. A new handle passes the community name filter (`handle_reserved`); while support hides the name the suggestion is the neutral `yaqeen_<id>` and any other new handle is `409 name_locked`. Errors `handle_taken` (409), `handle_reserved`, `name_locked` (409), `account_required` |
| GET | `/v1/me/public-profile/available?handle=` | user | `{available}` |
| GET | `/go/store?src=card·medal·missing&ref=` | — | The card page's shop button: counts the click, 302 to the store (admin link or `STORE_URL`) with UTM |
| GET | `/t/:code` | — | A physical tag: 302 → `/u/<handle>` when activated and published (no-store), activation page when blank, 404 page otherwise |
| POST | `/v1/me/events` | user (30/min) | Consented product events `{anonId, platform, appVersion, locale, events[≤50] {name, props, at}}` → `202 {accepted}`; only `PRODUCT_EVENTS` with allowed values are kept, nothing without the `product_analytics` consent, never linked to the account |
| GET · POST | `/v1/me/tags` | user (POST: not guest; 10 / 10 min) | Key medals / cards: list the active ones `[{code, kind, url, linkedAt, scans}]`; activate `{code}` (any case, dashes, or a pasted `/t/` link). Errors `not_found` (unknown, taken or switched off — indistinguishable), `tag_limit` (409, max 10), `account_required` |
| DELETE | `/v1/me/tags/:code` | user | Switch a lost tag off for good (204) |
| GET | `/v1/encode/:token` | encoding token (30/min per IP) | Staff encoder (`EncodeSessionView`): `{batch, kind, baseUrl, expiresAt, codes[] {code, encodedAt}}` — that batch's working codes only (switched-off ones left out), print order, `no-store`. Unknown, malformed, expired, revoked and voided-batch tokens all answer the same `404 not_found` |
| POST | `/v1/encode/:token/written` | encoding token (120/min per IP) | `{code, uid?: hex, locked}` after a chip was written and read back → `{code, encodedAt, encoded, total}`. Idempotent (a repeat or a re-encode refreshes the last write). `code_not_in_batch` (409) for another batch's or a switched-off code; the session is checked before the body. The token is redacted from request logs |
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

## Webhooks

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| POST | `/webhooks/shopify/orders-paid` | `X-Shopify-Hmac-Sha256` over the raw body with `SHOPIFY_WEBHOOK_SECRET` (401 `unauthorized` otherwise) | Our `YQ-XXXX-XXXX` codes on the paid order become `used` (`usedAt`, `shopifyOrderId`). Idempotent — Shopify retries are no-ops. Nothing about the customer is stored. In the background, with flag `serverConversions`, credentials and the buyer's current `ads_measurement` consent, a `purchase` goes to the configured ad platforms once per order (`conversion_sends`; docs/ANALYTICS_EVENTS.md). → `{ ok, used }` |

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
| GET · PUT | `/admin/content/daily-tasks` | read: editor/reviewer · write: content_editor (every write goes to `pending_review`) |
| POST | `/admin/content/daily-tasks/:date/review` | religious_reviewer, never the task's author; approve → served by `GET /v1/daily-task` |
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
| GET | `/admin/rewards/shopify/status` | marketing, support — `{configured, connected, shopName, domain, scopes, lastError, webhook: {configured, lastUsedAt}, conversions: {enabled, salted, platforms: {meta, ga4, tiktok}, lastSentAt}}` (booleans only, never credentials) |
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
| GET · POST | `/admin/tags/batches` | read: support, marketing · mint: marketing | Batches with totals (`total`, `active`, `disabled`, `encoded` = working tags written by the staff encoder); mint `{batch, kind: medal·card, count ≤ 5000}` (audited, `batch_exists`) |
| GET | `/admin/tags/batches/:batch.csv` | support, marketing | `code,printed_code,url,kind` for the manufacturer (NFC NDEF URI + QR print) |
| GET | `/admin/tags?batch=&status=unclaimed·active·disabled&code=` | support, marketing | Tags with the linked card's handle (never worship), plus `encodedAt` / `encodedLocked` (chip state from the staff encoder) |
| POST | `/admin/tags/:code/disable` · `/release` | support | Switch off (e.g. reported lost) / re-issue as blank; `{reason}`, audited |
| GET · POST | `/admin/tags/batches/:batch/encode-sessions` | marketing | Staff NFC encoding sessions. GET lists them (`AdminEncodeSession`, never the token). POST opens one for 2 h → `201 {id, batch, createdAt, expiresAt, revokedAt, active, token, url: yaqeen://encode/<token>}` — the token (32 random bytes, base64url) is returned once and only its SHA-256 is stored; audited `tags.encode_session.create` (no token in the log). `batch_void` for a voided batch |
| DELETE | `/admin/tags/batches/:batch/encode-sessions/:id` | marketing | Revoke at once (204), audited `tags.encode_session.revoke` |
| POST | `/admin/users/:id/public-profile/unpublish` | support | Hide a user's public card (`{reason}`), audited. The user detail includes `publicProfile {handle, published, views, url}` |

## Profile & community (design `docs/design/2026-11-profile-community-quran.md` §3)

Contracts: `packages/contracts/src/community.ts`. Competition endpoints answer `403 feature_off` while their flag is off (`leagues`, `tournaments`, `leaderboard`). Every public projection carries only name/@handle, avatar (a photo only when the owner is visible and attested 18+), the public level ring (nightly snapshot) and snapshot period points; visibility (active, not deletion-requested, switched on, not banned, not left, not blocked either way) is applied at read time.

| Method & path | Body → response | Errors |
| --- | --- | --- |
| GET `/v1/me/profile` | → `MeProfile` (own avatar as authed paths; live level and week points, self only) | — |
| PATCH `/v1/me/profile` | `UpdateProfileRequest` (`displayName`, preset/initial `avatar`) → `MeProfile` | 403 `account_required`, 400 `invalid_name`, 409 `name_locked` |
| PUT `/v1/me/avatar/photo` | raw `image/jpeg\|png\|webp` ≤ 3 MB → `Avatar` (re-encoded 96/256 WebP, EXIF stripped) | 403 `account_required`, 409 `photo_locked`, 413 `photo_too_large`, 415 `photo_type`, 422 `photo_unreadable`, 429 `rate_limited` (10/h) |
| DELETE `/v1/me/avatar/photo` | → `Avatar` (preset if set, else initial) | — |
| GET `/v1/me/avatar/photo/:size` | own active photo, 96 or 256, per-size ETag | 404 |
| POST `/v1/me/attestation` | `AttestRequest` → `CommunitySettings` (audited `user.attest_adult`) | 403 `account_required` |
| GET/PUT `/v1/me/community` | `CommunityUpdate` → `CommunitySettings` (one transaction: switches, attestation, consent recompute, draft card + handle, leave on off) | 403 `account_required` · `community_banned` · `feature_off`, 400 `attestation_required` · `name_required` · `invalid_name`, 409 `name_locked` |
| PUT `/v1/me/consents` | `{kind:'community', granted:false}` leaves everything; granting is refused | 403 `use_community_settings` |
| GET `/v1/me/badges` | → `Badge[]` newest first | — |
| GET `/v1/leagues/current` · `/v1/leagues/history` | → `LeagueCurrent` (`off` · `closing` · `joined`) · `LeagueHistoryItem[]` (12 weeks) | 403 `feature_off` |
| GET `/v1/tournaments` · `/v1/tournaments/:id` | → `Tournament[]` · `Tournament` | 404 |
| POST/DELETE `/v1/tournaments/:id/join` | `JoinTournamentRequest` → `Tournament` | 403 `account_required` · `community_banned`, 409 `tournament_not_open`, 400 `ack_required` · `attestation_required` · `name_required` |
| GET `/v1/tournaments/:id/standings?cursor=` | → `TournamentStandings` (pages of 100) | 404 |
| GET `/v1/leaderboard?scope=global\|country` | → `LeaderboardView` (top 100 + me) | 409 `country_unknown` · `country_too_small` |
| POST `/v1/community/reports` | `ReportRequest` → 204 | 404, 429 `rate_limited` (20 / 24 h) |
| GET/POST `/v1/community/blocks`, DELETE `/v1/community/blocks/:handle` | `BlockRequest` → `BlockedUser[]` / 204 | 404 |
| GET `/v1/public/avatars/:photoId/:size.webp` | public photo (`max-age=300`) only when visible + attested | 404 |
| GET `/u/assets/avatars/:id.webp` | preset art, immutable | 404 |

**Admin** (`/admin/competitions`, guards read = marketing·support, writes per role; every write audited and bumps the `community` cache): tournaments (CRUD, publish, close, cancel — `AdminTournamentCreate/Patch`, Cairo days), `/leagues/settings` (applies from the next week), `/leagues/stats`, `/leagues/groups/:id`, `/leagues/rollover` (super admin), `/leaderboard`, `/competitors` (+ `:userId`, `:userId/photos/:photoId/:size` — any status within 7 days, `private, no-store`), `POST /competitors/:userId/:action` (`hide-name` · `restore-name` · `hide-photo` · `restore-photo` · `ban` · `unban`, `AdminReason`), `/reports` + resolve, `/badges`. Admin errors: `tournament_dates`, `slug_taken`, `tournament_not_editable`, `tournament_closed`, `settings_invalid`, `nothing_to_restore`, `account_inactive` (restore-photo on an account that is not active), `reason_required`, `validation_failed`. A tournament being finalized can no longer be cancelled (`tournament_closed`). `restore-photo` re-activates the photo only while the user kept the avatar the hide left them; if they chose another one since, it only unlocks uploads (audit `photoRestored: false`).

## Recordings «تلاواتي» (design `docs/design/2026-11-profile-community-quran.md` §16)

Contracts: `packages/contracts/src/recordings.ts` (fixtures `apps/mobile/test/fixtures/recordings`, matcher vectors `packages/contracts/fixtures/recitation-match`). The user's **own voice** reciting verses they chose — user content, never sent to analytics or ad sinks. Flag `recordings` (off by default): uploads and sharing answer `403 feature_off`, member/web views 404; the owner can always list, play and delete their own.

- **Format** (`RECORDING_FORMAT`): AAC-LC in `.m4a`, mono, 16 kHz, ≈ 32 kbps, ≤ 30 s (`RECORDING_MAX_MS`, + 250 ms encoder tolerance), ≤ 200 KB. The server reads the real duration, channels, rate and audio object type from the file (`ftyp`, `mdhd`, `mp4a`, `esds`) and stores the bytes as uploaded.
- **Limits:** 3 per profile (`recordings_limit`), 10 uploads + share-verifications per Cairo day (`recording_daily_limit`; deleting does not give them back).
- **Statuses:** `private_ready` (private, never sent to the AI check) · `processing` · `approved` · `needs_review` · `rejected` (`rejectReason` not_matching · unclear · silence · too_long) · `removed` (`removed_by_moderator`). Only members/public recordings are verified, on upload or when switched from private; switching back to private keeps an approved result and abandons a pending one. Without `ASR_URL` shared recordings go to `needs_review` (never auto-approved).
- **Sharing gates** (members/public, reactions, comments, reports): signed in, not a guest (`account_required`), 18+ attestation (`attestation_required`), community opt-in with a handle (`community_required`), not banned (`community_banned`). Blocks hide both ways (views 404; actions `403 blocked`).

| Method & path | Body → response | Errors |
| --- | --- | --- |
| POST `/v1/me/recordings` | `multipart/form-data`: part `meta` = `RecordingMeta` JSON (`surah, fromAyah, toAyah, durationMs, visibility='private', commentsOn=true, clientScore?, clientWords?`), part `audio` (`audio/mp4`) → **202** `Recording` | 400 `recording_bad_format` · `recording_too_long` · `recording_invalid_range`, 413 `recording_too_large`, 409 `recordings_limit`, 429 `recording_daily_limit`, 403 gates · `feature_off` (20/h per token) |
| GET `/v1/me/recordings` | → `MyRecordings {items, leftToday}` | — |
| GET `/v1/me/recordings/:id/audio` | the owner's audio (any status), `Range` → 206, `private, no-store` | 404 |
| PATCH `/v1/me/recordings/:id` | `RecordingPatch {visibility?, commentsOn?, position?}` → `Recording` | 409 `recording_not_public` (rejected/removed), 429 `recording_daily_limit`, 403 gates |
| DELETE `/v1/me/recordings/:id` | hard delete (audio, reactions, comments, their reports) → 204 | 404 |
| GET `/v1/community/members/:handle/recordings` | any signed-in user → `MemberRecordings {owner: PublicCompetitor, items: PublicRecording[]}` (approved, members/public, not held; owner active, attested, in the community, not banned) | 404 |
| GET `/v1/recordings/:id/audio` | same visibility, `Range` → 206, `private, max-age=300` | 404 |
| PUT · DELETE `/v1/recordings/:id/reaction` | `SetReaction {kind: mashallah·barakallah·ahsant}` → `ReactionState` (one per viewer, idempotent, changeable) | 403 gates · `blocked`, 404 |
| GET `/v1/recordings/:id/comments?cursor=` | → `RecordingCommentsPage` (newest first, 20 per page, blocked authors left out) | 404 |
| POST `/v1/recordings/:id/comments` | `PostComment {text}` → **201** `RecordingComment` | 400 `comment_rejected` (`details.problem`: too_short · too_long · link · phone · blocked_word · mention · invalid_chars), 403 `comments_off` · gates · `blocked`, 429 `comment_rate_limited` (5/min, 50/day) |
| DELETE `/v1/recordings/:id/comments/:cid` | author or the recording's owner → 204 (text wiped) | 404 |
| POST `/v1/recordings/:id/report` · `/v1/recordings/:id/comments/:cid/report` | `RecordingReportRequest {reason: not_recitation·inappropriate·spam·other}` → 204 (repeat = no-op; 3 distinct reporters hide a comment / hold a recording pending support) | 429 `rate_limited` (20 / 24 h), 403 gates |
| GET `/u/:handle/r/:id.m4a` | public + approved recording of a published, unmoderated card (no auth, `Range`, `public, max-age=300`) | 404 |
| GET `/u/assets/recitations.js` | the web card's player (CSP `script-src 'self'`) | — |

**Admin «التلاوات»** (`/admin/recordings`, read: religious_reviewer · support; every decision audited in the same transaction): `GET /queue` → `AdminRecordingQueue` (only `needs_review`, held/reported, removed ≤ 7 days; reported/hidden comments — never a user's list; the transcript only while queued) · `GET /:id/audio` (only while queued, `private, no-store`) · `POST /:id/decision` `AdminRecordingDecision` (`approve` · `reject` + `rejectReason` = religious_reviewer; `dismiss` · `remove` · `restore` = support) · `POST /comments/:id/decision` `AdminCommentDecision` (`remove` · `restore` · `dismiss`, support). Errors: `role_not_allowed`, `not_in_review`, `nothing_to_dismiss`, `nothing_to_restore`, `already_removed`, `reject_reason_required`.

**Internal ASR** (`services/asr`, not public): `POST {ASR_URL}/verify` raw `.m4a` + `X-ASR-Token` → `AsrVerifyResponse {durationMs, speechMs, transcript, words:[{text,startMs,endMs}]}`; 401, 413 `too_large`/`too_long`, 422 `undecodable`, 503 `not_configured`.

## Cloud backup

Opt-in (consent `cloud_backup`, off by default, signed-in accounts only) copy of the user's device-first progress — spec §6.13, docs/SECURITY_PRIVACY.md rule 8.

- **Kinds** (closed list, contracts `BACKUP_KINDS`): `quran_reading` (last page, bookmarks, today's wird, reading stats), `quran_notes` (highlights, notes), `khatma` (plan + history), `hifz`, `azkar` (today's counts, favourite duas), `listen` (reciter, position, today's listening time), `routine` (three routine slots), `ramadan` (log per Hijri year), `tasbeeh`. Anything else is 400 `validation_failed`.
- `data` is a JSON object of at most 256 KB (UTF-8, `BACKUP_MAX_BYTES`), else 413 `backup_too_large`. It is opaque to the server and sealed with AES-256-GCM (`BACKUP_SECRETS_KEY`) before storage.
- Errors: 403 `backup_off` (consent not granted), 403 `account_required` (guest), 409 `backup_conflict` (`details` = `{kind, version, updatedAt, data}` or null), 413 `backup_too_large`.
- Withdrawing the consent (`PUT /v1/me/consents {kind: cloud_backup, granted: false}`) and the erasure purge delete every row. No admin route reads backups.

## Common error codes

`validation_failed` · `unauthorized` · `invalid_token` · `role_not_allowed` · `account_required` · `account_suspended` · `not_enrolled` · `future_date` · `before_enrollment` · `outside_qada_window` · `already_completed` · `task_inactive` · `insufficient_points` · `reward_out_of_stock` · `shopify_unavailable` · `not_a_guest` · `no_test_devices` · `push_not_configured` · `use_splash_verse_endpoint` · `user_reward_limit_reached` · `bonus_not_eligible` · `bonus_already_claimed` · `cannot_review_own_edit` · `not_pending_review` · `invalid_total` · `duplicate_task` · `use_program_endpoint` · `hijri_invalid_sequence` · `copy_issues` · `backup_off` · `backup_conflict` · `backup_too_large` · recordings: `recording_too_long` · `recording_too_large` · `recording_bad_format` · `recording_invalid_range` · `recordings_limit` · `recording_daily_limit` · `recording_not_public` · `attestation_required` · `community_required` · `comments_off` · `comment_rejected` · `comment_rate_limited` · `blocked`
