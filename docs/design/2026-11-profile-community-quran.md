# Yaqeen: Profile, Identity, Community (leagues, tournaments, leaderboard) and the One-Page Quran

Design for the approved owner request (2026-11), revision 2 (applies the 32 blocking critique items and the non-blocking notes; resolution table in §15). The scope is complete and approved. The owner has already answered the privacy and economics questions (§1.2), so nothing here is deferred or waiting on sign-off. The `contracts` stream commits this file as `docs/design/2026-11-profile-community-quran.md`. Where this doc and older spec text disagree, the new APP_SPEC text in §12 wins.

The avatar art from `yaqeen-avatars.zip` is already committed at d552ca0: `apps/mobile/assets/avatars/*.webp`, `packages/brand/avatars/{avatars.json,svg/}`, and `pubspec.yaml` lists `assets/avatars/`. No stream imports it again.

---

## 0. Summary

| # | Owner ask | What ships |
|---|---|---|
| 1 | Rebuild Profile, premium, "not all this colors" | New Profile tab. Stage: avatar inside a level ring, name, level caption. Orbs: Level · Points · League, all working in place. Body: badges strip, journey, «المنافسة» group, card row, rewards group. Settings move to `/profile/settings`. Palette: porcelain + ink + lapis; gold only for achievement. |
| 2 | Photo or preset avatar | 16 bundled presets (`m01..m08`, `f01..f08`) or a photo. The server re-encodes photos with `sharp` (EXIF stripped) into 96/256 WebP stored in Postgres `bytea` (no paid service). Shared `YqAvatar` / `YqLevelAvatar`. A photo is shown to others only when the owner is visible and has attested they are 18+ (or have guardian consent). Support can hide a photo, audited. |
| 3 | Onboarding shows the profile | New step `05·ج «ملفّك»` at `/onboarding/profile`: avatar, name, levels explainer, weekly-league opt-in (off by default, needs sign-in, the age attestation and a connection). |
| 4 | Seamless Quran read / listen / rehearse | "One Page": the printed Madani page is the only Quran surface. Read · listen · memorise · recite are layers switched by a mode dock. The reader follows the audio. App-wide mini player. Guided hifz/review sessions. `/quran/listen` and `/quran/recite` redirect into the reader. |
| 5 | Shimmers everywhere | Sweep list in §10, plus a test that fails on any `CircularProgressIndicator` / `LinearProgressIndicator` / `RefreshProgressIndicator` in `lib/`. |
| 6 | Home profile place with level ring | A 48-pt chip at the start of the Home header row: avatar with a lapis level ring and level numeral; tap opens `/profile`. Home also shows the one-time week result and level-up moment. |
| 7 | Level-based app + competitions | Weekly leagues (6 divisions, groups of ~30, promote/demote), admin seasonal tournaments, and a level leaderboard (global + opt-in country board). **Badges only**: no points minted, economics unchanged. Opt-in, off by default, leave any time, block + report + moderation (audited). Public standings are **nightly snapshots**, never live. |
| 8 | Systematic, clean | Contracts first (which also pre-registers every route and every ARB key), then parallel streams with disjoint file ownership. |

---

## 1. Product rules and privacy

### 1.1 Non-negotiables restated for this feature
- **Rule 1.** No league, tournament, leaderboard, badge, block, avatar or Quran-session event goes to any ad sink. No new `PRODUCT_EVENTS` event is added. The only analytics change is a new value `profile` in the existing `onboarding_step.step` list (a screen name, no worship data).
- **Rule 2.** Other users and admins see **only**:
  - display name (or `@handle`, or «عضو يقين» when hidden),
  - photo (only when the owner attested 18+ and is visible) or preset avatar,
  - level ring (level number + progress) computed from the **public lifetime snapshot**,
  - the **period's point total as of the end of the previous Cairo day** (week or tournament window).

  They never see which prayers, azkar or tasks, never per-day or per-task breakdowns, never streaks inside competitions, never Quran/hifz/session data, and **never anything live or time-ordered**:
  - **Snapshot rule (normative).** Every public standing, rank, period total and public level ring is read from snapshots refreshed **once per Cairo day** by the community job, covering ledger activity up to Cairo 00:00 of the current day. A points insert never changes any public view until the next nightly snapshot. `last_earned_at` and any other time ordering are never stored for ranking and never exposed.
  - The caller's own live totals (week points, tournament points, balance) are shown only to the caller (`MeProfile.weekPoints`, `Tournament.me.points`), never in a list row.
  - Final results at week/tournament close come from the live rollups at the closing boundary (which is itself a Cairo midnight).
  - Admin competition screens use the same snapshot projections plus aggregates suppressed below K_ANONYMITY = 20.
- **Rule 3.** The points ledger stays append-only. Competitions **never insert ledger rows**. Badges live in a separate append-only `user_badges` table with a unique `(user_id, ref_key)`. `points_earned_daily` and `user_point_totals` are derived caches maintained by an `AFTER INSERT` trigger that only reads `NEW`, rebuildable at any time by `yq_rebuild_points_rollups()`. They are not balances.
- **Rule 5.** No marketing push for competition results. Results appear in-app: a one-time «انتهى الأسبوع» sheet on the next app open (Home, after the first frame). Worship reminders are untouched.
- **Rule 6.** Avatar choice and name are written locally first and synced via the Outbox. Presets render offline from bundled assets. **Joining** any competition is a direct online call (offline: «تحتاج اتصالاً للانضمام»); **leaving** is queued in the Outbox and hides the user locally at once. Leaderboards and leagues are online data, cached for offline viewing with an offline banner.
- **Rule 7.** Arabic RTL first, Western digits (`YqFormat.number`), all copy in ARB.
- **Rule 8.** Tokens only:
  - porcelain ground, ink text, muted secondary, `line` hairlines;
  - **lapis is the only accent** (rings, active states, links);
  - **gold only for achievement**: earned badges, level-reached rail dots, the one-shot level-up glint, the top level (منارة) ring, a met session goal, podium ranks 1–3 after a period closes.
  - No raw ARGB literals in touched files: use `YqColors.x.withValues(alpha:)`.
  - Division marks are monochrome (ink numeral tier mark on a `line` ring). The division named «ذهب» never gets gold styling.
- **Rule 9.** Tournament titles and descriptions are marketing copy and must not quote Quran, hadith or dua. The admin form says so. The sincerity line in §1.4 is product copy.

### 1.2 Owner decisions (final)
- (a) Both weekly leagues (opt-in) and admin seasonal tournaments, plus a level leaderboard (global and by country).
- (b) Rewards are badges only. No points minted; points economics unchanged.
- (c) Public fields are exactly those in §1.1 rule 2. Opt-in, off by default, leave any time. Support can hide abusive photos or names, audited.

### 1.3 Opt-in model (PDPL)
- New consent kind `community` (contracts `ConsentKind`, Postgres `consent_kind` enum, Dart `ConsentKind.community('community')`, default `false`).
- `community` is **granted** when any of these is true: `community_members.leagues`, `community_members.leaderboard`, or an active (not left, tournament not closed/cancelled) tournament entry. `leaderboard_country` only refines `leaderboard` and never grants alone.
- **One helper, every path.** `recomputeCommunityConsent(tx, uid, source)` (in `community.service`) recomputes the state and, when it flipped, upserts `consents` and inserts `consent_events` (with `POLICY_VERSION`, `source`, and `attested_adult` when the change came from a join). It is called from: `PUT /v1/me/community`, tournament join, tournament leave, the generic consent route (withdraw), the community job (tournament close/cancel), support `ban` / `hide_name` / `hide_photo` (any action that changes membership), erasure, and erasure cancel. `consent_events.source` (text) gains the values `system` (job), `support` (moderation) and `erasure`; contracts export `ConsentEventSource = ['onboarding','settings','system_prompt','system','support','erasure']`. The client-facing `ConsentUpdate.source` enum is unchanged.
- **Generic consent route** `PUT /v1/me/consents` (`me.routes.ts`): `{kind:'community', granted:false}` runs the same transaction as leaving everything (switches false, `left_at` on live rows, consent event source `settings`). `{kind:'community', granted:true}` is refused with `403 use_community_settings`.
- **Who can opt in.** Signed-in, non-guest accounts only (`account_required`). The app gates guests behind `showSignInSheet`.
- **Age attestation (PDPL minors).** Every join (league, leaderboard, country board, tournament, the onboarding switch) requires the switch «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري». The request carries `attestAdult: true` the first time; the server sets `users.adult_attested_at` and writes `consent_events.attested_adult = true` on that row. Without it: `400 attestation_required`. A photo is served publicly only when `adult_attested_at is not null`; otherwise public projections fall back to the preset (or initial). The card editor offers the same switch so card-only users can show their photo. Counsel review of this wording joins the existing bracketed list (§13 of APP_SPEC).
- **Handles.** On opt-in the server ensures a `public_profiles` row with `published=false` so every competitor has a stable `@handle`. If the user has no row, the handle comes from `competitorHandle(name)`: the first word of the name slugified to ASCII + `-` + 4 random digits; if that slug is empty (e.g. Arabic-only), `member-` + 6 random `[a-z0-9]`. The full name is never put in a new handle. Existing card handles are kept.
- **Which name.** Competitions show `users.display_name` (the profile name, max 40). `public_profiles.display_name` stays the card name. The join sheets and onboarding prefill **the first name only** (first word of the session name).
- **Country board.** `community_members.leaderboard_country` (default false) is its own switch, shown in `/profile/community` and on the leaderboard with the disclosure «وتظهر في لوحة بلدك». A country board exists only when that country has at least K_ANONYMITY = 20 country-board participants; otherwise `409 country_too_small`.
- **Leaving.** `PUT /v1/me/community {leagues:false}` (or leaderboard off, or tournament leave) sets `left_at` on the current league week and live tournament entries in the same transaction, recomputes consent and bumps caches in namespace `community`. The user disappears from standings at once (the visibility filter is applied at read time on top of snapshots). A member who leaves keeps their division and gets no outcome or badge for that period.
- **Erasure** (`DELETE /v1/me`), same transaction: switches false, leaves all live entries, `recomputeCommunityConsent(source 'erasure')`, photo `status='removed'` (`removed_by` null), `avatar_kind='initial'`, `users.country = null`, delete the user's `community_blocks` (both directions) and snapshot rows (`leaderboard_snapshot`; `snapshot_*` columns nulled). The purge job deletes all remaining rows at tombstone time (§4.4).
- **Erasure cancelled** inside the grace period: the user stays out of competitions until they opt in again, and the photo stays removed (they can upload again).
- **Export** (`/v1/me/export`): avatar kind/preset, photo metadata plus the 256-px WebP as base64, community settings (incl. country switch and attestation time), league history, tournament entries, badges, blocks the user made, and reports the user filed. **Admin export** (`exportUser(..., {includeWorship:false})`): the same new fields **except** the base64 photo (metadata only).

### 1.4 Gentle competition framing (copy rules)
- No red, no "relegated", no "last place".
  - The bottom zone label is «يبدأون الأسبوع القادم في {division}», muted.
  - Ranks below 10 show no medal styling.
  - A member with 0 snapshot points shows «—» for rank and points.
- Ties share a rank (standard competition ranking: 1, 1, 3). Display order inside a tie is handle ascending. Nobody is rewarded for ticking earlier.
- Sincerity footer on every competition screen: «تنافسٌ لطيف على الخير. لا نقاط إضافية هنا، والشارات تذكارٌ فقط.»
- Privacy line on every competition screen and join sheet: «يرى المشاركون اسمك وصورتك ومستواك ونقاط الفترة فقط، لا صلواتك ولا أذكارك ولا مهامك.»
- Snapshot line under every standings list: «يُحدَّث الترتيب كل ليلة.»
- Results are shown once and quietly. Gold appears only when a badge is earned.

### 1.5 Safety: block, report, filter, moderation, terms
- **Block** (store UGC requirement): `community_blocks(user_id, blocked_user_id)`; `POST /v1/community/blocks {handle}`, `DELETE /v1/community/blocks/:handle`, `GET /v1/community/blocks`. A block hides each user from the other's views (both directions, display only; rank numbers keep their gaps). «حظر» is an action in the report sheet; «المحظورون» list with «إلغاء الحظر» in `/profile/community`. Included in export and purge.
- **Report.** A user can report a competitor's name or photo. **Enforced in the database**: at most 20 reports per reporter per rolling 24 h, counted from `community_reports` (`429 rate_limited`). Reports go to a support queue.
- **Name filter.** `DisplayName` (contracts) rejects URLs, control characters, bidi controls (U+200E–U+200F, U+202A–U+202E, U+2066–U+2069), zero-width characters (U+200B–U+200D, U+FEFF). Server-side `nameProblem(name, reservedHandles)` in `domain/community.ts` additionally rejects the reserved-handle list (cards settings), brand impersonation («يقين», «فريق يقين», «الدعم», «الإدارة», "Yaqeen", "support", "admin", "official" — matched after `canonicalName` and case-folding), and a small Arabic/English profanity list (unit-tested, kept in that file). All map to `400 invalid_name`.
- **Terms.** `/terms` gains a «المنافسات والسلوك» section (`#community`) in `site-pages.ts`; every join sheet links to it («شروط المنافسات»). `/privacy` describes photo processing, community visibility, nightly snapshots, the country board, the age attestation, blocks, and retention (removed/replaced photos 7 days, resolved reports 180 days). `POLICY_VERSION` is bumped.
- **Support actions.** Each takes `AdminReason` (`{reason}` 3..500), is audited in the same transaction with before/after, bumps the `community` and `profile` caches, and calls `recomputeCommunityConsent` when membership changes.
  - `hide_name`: `users.name_hidden_at`. The public name becomes null (clients render «عضو يقين»). The user cannot rename until restored (`name_locked`). **Also rotates the handle** to `member-` + 6 random chars unless the card is published and not moderated; the old and new handle go in the audit row.
  - `restore_name` (the handle is not rotated back).
  - `hide_photo`: the active photo becomes `status='removed'`, `removed_by` = admin, `users.photo_locked_at` set. The avatar falls back to the preset or initial. Uploads are refused with `photo_locked` until restored.
  - `restore_photo`: re-activates the most recent photo with `removed_by is not null` and `removed_at` under 7 days old, and unlocks uploads; never a photo the user removed themselves. Otherwise `409 nothing_to_restore`. Refused for an account that is not active (`409 account_inactive`: an erasure request keeps the photo removed). If the user chose another avatar after the hide (not the one the hide left them), only uploads are unlocked and the photo stays removed.
  - `ban`: `community_members.banned_at`. Leaves all standings immediately; rejoin refused with `community_banned`.
  - `unban`.
- Support sees the photos it moderates through an admin-only photo route (§3.4) that serves any status within the 7-day retention.
- The existing whole-card `moderateCard` stays as is. A moderated card does **not** remove the user from competitions; `ban` does.

### 1.6 Levels (unchanged thresholds, one bug fixed)
- Six levels stay: 0 / 500 / 2000 / 5000 / 12000 / 25000 (بداية الطريق، على الطريق، مواظب، ثابت، راسخ، منارة). Lifetime **earned** points; spending never lowers a level.
- **Bug fix.** Lifetime points today sum every positive ledger row, including `reversal`. New contract constants:
  - `LEVEL_REASONS = ['task','qada','bonus','milestone','grant','admin_adjustment']`, `delta > 0` only. Used for the level (self) and the level leaderboard.
  - `EARNED_REASONS = ['task','qada','bonus','milestone']`. Used for league and tournament period points.
- The caller's own level is live (`MeProfile.level`). Every public level ring (lists, `/u/<handle>`, admin) uses `user_point_totals.public_lifetime` (nightly snapshot).
- **Qada timing.** Qada is credited at claim time; its points count in the Cairo day (and week, tournament) of the claim. A claim after a week or tournament closed never changes its frozen final results.
- **Guest merge.** When a guest links to an existing account (`auth.routes.ts`), the same transaction moves the guest's `points_earned_daily` rows to the account (summing on conflict). The `grant` row the merge inserts is excluded from `EARNED_REASONS`, so week/tournament points are not counted twice; it is counted once for the level via `LEVEL_REASONS`. `yq_rebuild_points_rollups()` follows `users.merged_into` for daily rows.
- `levelFor` in contracts and Dart must agree (shared fixture parity test).

---

## 2. Data model (Drizzle, migration `0017_community.sql`)

There is exactly **one** `0017` on the branch, owned by the contracts stream; the api stream never edits `schema.ts` or migrations. Edit `services/api/src/db/schema.ts`, run `pnpm db:generate`, then append the hand-written section. Follow `0014_cloud_backup.sql`: `ALTER TYPE "public"."consent_kind" ADD VALUE 'community';--> statement-breakpoint` and never use the literal `'community'` elsewhere in the same migration (Drizzle runs migrations inside a transaction; Postgres 16 allows ADD VALUE there as long as the new value is not used in it). `bytea` uses a Drizzle `customType<{data: Buffer}>({dataType: () => 'bytea'})`. The `users.avatar_photo_id → avatar_photos.id` FK is added with `ALTER TABLE … ADD CONSTRAINT` after both tables exist (the generator handles this; check the SQL).

**`users` (alter)**

| Column | Type | Notes |
|---|---|---|
| `country` | text null | ISO-3166 alpha-2, check `~ '^[A-Z]{2}$'` |
| `avatar_kind` | text not null default `'initial'` | check in (`initial`,`preset`,`photo`) |
| `avatar_preset` | text null | check in the 16 ids; required when kind=`preset`; kept as fallback when kind=`photo` |
| `avatar_photo_id` | uuid null → `avatar_photos.id` on delete set null | added after `avatar_photos` |
| `name_hidden_at`, `name_hidden_reason` | timestamptz / text null | |
| `photo_locked_at` | timestamptz null | |
| `adult_attested_at` | timestamptz null | set by any join with `attestAdult` |

**`consent_events` (alter)**: `attested_adult boolean null`.

**`avatar_photos`**
- `id uuid pk default random` (new id per upload), `user_id → users cascade`, `sha_small text not null`, `sha_large text not null` (per-size ETags), `small bytea not null` (96 px WebP), `large bytea not null` (256 px WebP), `bytes int not null`, `status text not null default 'active'` (check `active|replaced|removed`), `created_at`, `removed_at`, `removed_by uuid null → admin_users`, `removed_reason text`.
- Indexes: `(user_id, created_at desc)` (also serves the 10/hour DB rate limit), `(status, created_at desc)`.

**`community_members`**
- `user_id uuid pk → users cascade`
- `leagues bool not null default false`, `leaderboard bool not null default false`, `leaderboard_country bool not null default false`
- `division smallint not null default 1` (check 1..6)
- `banned_at`, `banned_reason`, `created_at`, `updated_at`

**`community_blocks`**: `user_id → users cascade`, `blocked_user_id → users cascade`, `created_at`; PK `(user_id, blocked_user_id)`; index `(blocked_user_id)`; check `user_id <> blocked_user_id`.

**`points_earned_daily`** (derived): `user_id → users cascade`, `day date` (Africa/Cairo date of `created_at`), `earned int not null`. PK `(user_id, day)`; index `(day, user_id)`. No time-of-day column.

**`user_point_totals`** (derived): `user_id pk → users cascade`, `lifetime_earned int not null default 0`, `public_lifetime int not null default 0` (nightly snapshot), `public_day date null`. Index `(public_lifetime desc)`.

**Trigger and functions (custom SQL)**
- `yq_points_rollup()` `AFTER INSERT ON points_ledger FOR EACH ROW`:
  - `NEW.delta > 0 and NEW.reason in EARNED_REASONS` → upsert `points_earned_daily` at `(NEW.created_at at time zone 'Africa/Cairo')::date`, `earned = earned + NEW.delta`;
  - `NEW.delta > 0 and NEW.reason in LEVEL_REASONS` → upsert `user_point_totals.lifetime_earned += NEW.delta`.
- `yq_rebuild_points_rollups()` truncates and recomputes both tables from `points_ledger`; daily rows attribute EARNED rows to `coalesce(users.merged_into, ledger.user_id)`; lifetime per `user_id`; `public_lifetime` set to `lifetime_earned`. Used by the migration backfill, tests, and operations (documented in OPERATIONS.md).
- The trigger catches every writer, including the raw-SQL grant in `rewards.routes.ts`.

**`league_weeks`**
- `starts_on date pk` (a Saturday), `starts_at`, `ends_at` (Saturday 00:00 Africa/Cairo to the next Saturday 00:00, DST-safe)
- `settings jsonb null` (the `LeagueSettings` in force for that week, filled when the week starts — by the previous week's close or by the first `ensurePlacement` — and never changed after)
- `status text default 'open'` (check `open|closed`), `closed_at`

**`league_groups`**: `id uuid pk`, `starts_on → league_weeks`, `division smallint`, `size smallint not null default 0`, `closed_at timestamptz null`, `created_at`. Index `(starts_on, division, size)`, partial index `(starts_on) where closed_at is null`.

**`league_members`**: `starts_on → league_weeks`, `user_id → users cascade`, `group_id → league_groups`, `division smallint`, `joined_at`, `left_at null`, `snapshot_points int null`, `snapshot_rank smallint null`, `final_points int null`, `final_rank smallint null`, `outcome text null` (check `up|stay|down`). PK `(starts_on, user_id)`; index `(group_id, snapshot_rank)`.

**`tournaments`**
- `id uuid pk`, `slug text unique` (`^[a-z0-9-]{3,40}$`), `title_ar`, `title_en` (≤ 60), `body_ar`, `body_en` (≤ 280).
- Window: `starts_at`, `ends_at`, `join_until` — all **Cairo 00:00** instants (`ends_at` and `join_until` exclusive; the admin picks inclusive last days, the server adds one day).
- `badge_ar`, `badge_en` (≤ 40), `min_points int default 1`.
- `status text default 'draft'` (check `draft|published|cancelled`), `finalizing_at`, `closed_at`.
- `created_by → admin_users`, `created_at`, `updated_at`.
- Checks: `starts_at < ends_at`, `join_until <= ends_at`, window ≤ 90 days.

**`tournament_entries`**: `tournament_id → tournaments cascade`, `user_id → users cascade`, `joined_at`, `left_at`, `snapshot_points`, `snapshot_rank`, `final_points`, `final_rank`. PK `(tournament_id, user_id)`; indexes `(tournament_id, snapshot_rank)`, `(tournament_id, final_rank)`.

**`leaderboard_snapshot`**: `scope text` (check `global|country`), `country text not null default ''`, `user_id → users cascade`, `rank int not null`, `lifetime int not null`, `day date not null`. PK `(scope, country, user_id)`; index `(scope, country, rank)`.

**`community_snapshot_days`**: `day date pk`, `taken_at` (marks that the nightly snapshot for that Cairo day ran).

**`user_badges`** (append-only): `id uuid pk`, `user_id → users cascade`, `kind text` (`BADGE_KINDS`), `ref_key text`, `meta jsonb` (`{startsOn?, division?, rank?, size?, tournamentId?, titleAr?, titleEn?, labelAr?, labelEn?}`), `awarded_at`. Unique `(user_id, ref_key)`.

**`community_reports`**: `id uuid pk`, `reporter_id → users cascade`, `target_user_id → users cascade`, `reason text` (check `name|photo|other`), `created_at`, `resolved_at`, `resolved_by → admin_users`, `resolution text` (check `dismissed|actioned`). Partial unique `(reporter_id, target_user_id) where resolved_at is null`; index `(reporter_id, created_at desc)` (DB rate limit).

**Other**: `app_config` key `leagues` holds `LeagueSettings` (zod defaults when absent).

Badge `ref_key`s:
- `league:<startsOn>`: kind `league_first`, `league_top3` or `league_promoted` (best tier)
- `division:<n>`: kind `division_reached`, first time `n ≥ 2`
- `tournament:<id>`: kind `tournament_podium`, `tournament_top10` or `tournament_finisher`

Streak badges (`milestone:<days>` ledger rows) and level badges (journey level crossings) stay **derived** and are unioned into the badges API as kinds `streak` and `level`.

---

## 3. Contracts and API

### 3.1 `packages/contracts/src/community.ts` (new, re-exported from `index.ts`)
Refined schemas are never `.partial()`-ed or `.extend()`-ed: each has a `…Base` object and a refined export.
```ts
export const AVATAR_PRESETS = ['m01','m02','m03','m04','m05','m06','m07','m08','f01','f02','f03','f04','f05','f06','f07','f08'] as const;
export const AvatarPresetId = z.enum(AVATAR_PRESETS);
// url/smallUrl: absolute public URLs in public projections; in MeProfile (caller only) they are the
// authed API paths '/v1/me/avatar/photo/256' and '/v1/me/avatar/photo/96', loaded with ApiClient.getBytes.
export const Avatar = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('initial') }),
  z.object({ kind: z.literal('preset'), id: AvatarPresetId }),
  z.object({ kind: z.literal('photo'), id: z.string().uuid(), url: z.string().min(1), smallUrl: z.string().min(1) }),
]);
export const SetAvatar = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('initial') }),
  z.object({ kind: z.literal('preset'), id: AvatarPresetId }),
]);
export const AVATAR_PHOTO = { maxBytes: 3 * 1024 * 1024, mimes: ['image/jpeg','image/png','image/webp'], sizes: [96, 256], minPx: 128, clientMaxPx: 1024, perHour: 10 } as const;
export const DISPLAY_NAME_MAX = 40;
const NAME_FORBIDDEN = /https?:|www\.|[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/i;
export const DisplayName = z.string().trim().min(1).max(DISPLAY_NAME_MAX).refine(s => !NAME_FORBIDDEN.test(s), 'invalid_name');
export const EARNED_REASONS = ['task','qada','bonus','milestone'] as const;
export const LEVEL_REASONS = ['task','qada','bonus','milestone','grant','admin_adjustment'] as const;
export const DIVISIONS = [
  { id: 1, key: 'bronze',  ar: 'برونز', en: 'Bronze' },
  { id: 2, key: 'silver',  ar: 'فضة',   en: 'Silver' },
  { id: 3, key: 'gold',    ar: 'ذهب',   en: 'Gold' },
  { id: 4, key: 'emerald', ar: 'زمرّد', en: 'Emerald' },
  { id: 5, key: 'ruby',    ar: 'ياقوت', en: 'Ruby' },
  { id: 6, key: 'diamond', ar: 'ألماس', en: 'Diamond' },
] as const;
export const DivisionId = z.number().int().min(1).max(6);
export const LEAGUE_WEEK = { startsOnWeekday: 6 /* Saturday */, timezone: 'Africa/Cairo' } as const;
export const K_COUNTRY_BOARD = 20; // equals K_ANONYMITY
export const LeagueSettingsBase = z.object({
  groupSize: z.number().int().min(10).max(50).default(30),
  promote: z.number().int().min(1).max(10).default(5),
  demote: z.number().int().min(0).max(10).default(5),
  divisionNames: z.array(z.object({ ar: z.string().trim().min(1).max(24), en: z.string().trim().min(1).max(24) })).length(6).optional(),
});
export const LeagueSettings = LeagueSettingsBase.refine(s => s.promote + s.demote < s.groupSize, { message: 'settings_invalid' });
export const BADGE_KINDS = ['streak','level','league_first','league_top3','league_promoted','division_reached','tournament_podium','tournament_top10','tournament_finisher'] as const;
export const Badge = z.object({
  kind: z.enum(BADGE_KINDS), refKey: z.string(), awardedAt: z.string(),
  meta: z.object({
    days: z.number().int().optional(), level: z.number().int().optional(), division: DivisionId.optional(),
    rank: z.number().int().optional(), size: z.number().int().optional(), startsOn: z.string().optional(),
    tournamentId: z.string().uuid().optional(), titleAr: z.string().optional(), titleEn: z.string().optional(),
    labelAr: z.string().optional(), labelEn: z.string().optional(),
  }).default({}),
});
export const LevelInfoSchema = z.object({ level: z.number().int().min(1).max(6), nameAr: z.string(), nameEn: z.string(),
  progress: z.number().min(0).max(1), nextAt: z.number().int().nullable() }); // mirrors the existing LevelInfo interface
export const PublicLevelRing = z.object({ level: z.number().int().min(1).max(6), progress: z.number().min(0).max(1) });
// rank is shared on ties (1,1,3); null when the member has no snapshot yet or 0 points.
export const PublicCompetitor = z.object({
  handle: z.string(), name: z.string().nullable(), avatar: Avatar, level: PublicLevelRing,
  points: z.number().int().nullable() /* snapshot; null on the level board */, rank: z.number().int().min(1).nullable(), me: z.boolean(),
});
export const ConsentEventSource = z.enum(['onboarding','settings','system_prompt','system','support','erasure']);
export const CommunitySettings = z.object({ leagues: z.boolean(), leaderboard: z.boolean(), leaderboardCountry: z.boolean(),
  banned: z.boolean(), attestedAdult: z.boolean(), country: z.string().regex(/^[A-Z]{2}$/).nullable() });
// Turning anything on is a direct online call; attestAdult is required (true) when not yet attested.
export const CommunityUpdate = z.object({ leagues: z.boolean().optional(), leaderboard: z.boolean().optional(),
  leaderboardCountry: z.boolean().optional(), displayName: DisplayName.optional(), attestAdult: z.literal(true).optional(),
  source: z.enum(['onboarding','settings']).default('settings') });
export const AttestRequest = z.object({ attestAdult: z.literal(true) });
export const LeagueOutcome = z.enum(['up','stay','down']);
export const LeagueLastWeek = z.object({ startsOn: z.string(), division: DivisionId, newDivision: DivisionId,
  rank: z.number().int().nullable(), outcome: LeagueOutcome.nullable(), badge: Badge.nullable() });
export const LeagueSummary = z.object({ division: DivisionId, divisionAr: z.string(), divisionEn: z.string(),
  rank: z.number().int().nullable() /* snapshot */, size: z.number().int(), lastWeek: LeagueLastWeek.nullable() });
export const MeProfile = z.object({
  displayName: z.string().nullable(), nameHidden: z.boolean(), handle: z.string().nullable(),
  avatar: Avatar /* authed paths for photo */, photoHidden: z.boolean(), photoPublic: z.boolean(),
  level: LevelInfoSchema, lifetimePoints: z.number().int(), weekPoints: z.number().int() /* live, self only */,
  community: CommunitySettings, league: LeagueSummary.nullable(), recentBadges: z.array(Badge).max(12), badgesCount: z.number().int(),
});
export const UpdateProfileRequestBase = z.object({ displayName: DisplayName.optional(), avatar: SetAvatar.optional() });
export const UpdateProfileRequest = UpdateProfileRequestBase.refine(v => v.displayName !== undefined || v.avatar !== undefined);
export const LeagueCurrent = z.discriminatedUnion('state', [
  z.object({ state: z.literal('off') }),
  z.object({ state: z.literal('closing') }), // a past week is still being closed
  z.object({ state: z.literal('joined'), startsOn: z.string(), endsAt: z.string(), snapshotDay: z.string().nullable(),
    division: DivisionId, divisionAr: z.string(), divisionEn: z.string(),
    nextAr: z.string().nullable(), nextEn: z.string().nullable(), prevAr: z.string().nullable(), prevEn: z.string().nullable(),
    size: z.number().int(), promoteZone: z.number().int(), demoteZone: z.number().int(),
    myLivePoints: z.number().int(), rows: z.array(PublicCompetitor), lastWeek: LeagueLastWeek.nullable() }),
]);
export const LeagueHistoryItem = z.object({ startsOn: z.string(), division: DivisionId, rank: z.number().int().nullable(),
  size: z.number().int(), points: z.number().int().nullable(), outcome: LeagueOutcome.nullable() });
export const TournamentPhase = z.enum(['upcoming','live','ended']);
export const Tournament = z.object({ id: z.string().uuid(), slug: z.string(), titleAr: z.string(), titleEn: z.string(),
  bodyAr: z.string(), bodyEn: z.string(), startsAt: z.string(), endsAt: z.string(), joinUntil: z.string(),
  phase: TournamentPhase, closed: z.boolean(), joined: z.boolean(), participants: z.number().int(),
  badgeAr: z.string(), badgeEn: z.string(),
  me: z.object({ rank: z.number().int().nullable() /* snapshot or final */, points: z.number().int() /* live, self */ }).nullable() });
export const TournamentStandings = z.object({ total: z.number().int(), snapshotDay: z.string().nullable(),
  rows: z.array(PublicCompetitor), me: PublicCompetitor.nullable(), nextCursor: z.string().nullable() });
export const JoinTournamentRequest = z.object({ acknowledge: z.literal(true), attestAdult: z.literal(true).optional() });
export const LeaderboardScope = z.enum(['global','country']);
export const LeaderboardView = z.object({ scope: LeaderboardScope, country: z.string().nullable(), snapshotDay: z.string().nullable(),
  joined: z.boolean(), countryJoined: z.boolean(), rows: z.array(PublicCompetitor), me: PublicCompetitor.nullable() });
export const ReportRequest = z.object({ handle: z.string(), reason: z.enum(['name','photo','other']) });
export const BlockRequest = z.object({ handle: z.string() });
export const BlockedUser = z.object({ handle: z.string(), name: z.string().nullable(), avatar: Avatar });
export const COMMUNITY_ERROR_CODES = ['account_required','community_banned','name_required','name_locked','invalid_name',
  'feature_off','attestation_required','use_community_settings','tournament_not_open','ack_required','country_unknown',
  'country_too_small','photo_locked','photo_too_large','photo_type','photo_unreadable','rate_limited','not_found'] as const;
// admin
export const TournamentStatus = z.enum(['draft','published','cancelled']);
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/); // a Cairo calendar day
export const AdminTournamentBase = z.object({
  slug: z.string().regex(/^[a-z0-9-]{3,40}$/),
  titleAr: z.string().trim().min(1).max(60), titleEn: z.string().trim().min(1).max(60),
  bodyAr: z.string().trim().max(280), bodyEn: z.string().trim().max(280),
  startsOn: Day, lastDay: Day /* inclusive; ends_at = lastDay+1 at Cairo 00:00 */, joinLastDay: Day.optional() /* default lastDay */,
  badgeAr: z.string().trim().min(1).max(40), badgeEn: z.string().trim().min(1).max(40),
  minPoints: z.number().int().min(1).max(100000).default(1),
});
export const AdminTournamentCreate = AdminTournamentBase;
export const AdminTournamentPatch = AdminTournamentBase.partial().merge(z.object({ reason: z.string().trim().min(3).max(500).optional() }));
// reason is required by the server when the tournament is live
export const AdminTournamentRow = Tournament.omit({ joined: true, me: true }).extend({ status: TournamentStatus,
  closedAt: z.string().nullable(), minPoints: z.number().int(), createdBy: z.string().nullable() });
export const AdminCompetitorRow = z.object({ userId: z.string().uuid(), handle: z.string().nullable(), name: z.string().nullable(),
  avatar: Avatar /* admin photo route URLs */, nameHidden: z.boolean(), photoHidden: z.boolean(), photoLocked: z.boolean(),
  banned: z.boolean(), leagues: z.boolean(), leaderboard: z.boolean(), leaderboardCountry: z.boolean(), attestedAdult: z.boolean(),
  division: DivisionId, openReports: z.number().int(), lastPhotoAt: z.string().nullable(),
  photos: z.array(z.object({ id: z.string().uuid(), status: z.enum(['active','replaced','removed']), createdAt: z.string(), removedBySupport: z.boolean() })) });
export const AdminStandingRow = PublicCompetitor.extend({ userId: z.string().uuid() });
export const CompetitorAction = z.enum(['hide-name','restore-name','hide-photo','restore-photo','ban','unban']);
export const AdminLeagueStats = z.object({ startsOn: z.string(), endsAt: z.string(), groups: z.number().int(),
  members: z.array(z.object({ division: DivisionId, count: z.number().int().nullable() })), activeShare: z.number().nullable(),
  settingsInForce: LeagueSettingsBase, lastWeek: z.object({ up: z.number().int().nullable(), down: z.number().int().nullable() }).nullable() });
export const AdminTournamentStats = z.object({ participants: z.number().int().nullable(), active: z.number().int().nullable(),
  median: z.number().nullable(), buckets: z.array(z.object({ label: z.string(), count: z.number().int().nullable() })),
  badges: z.array(z.object({ kind: z.enum(BADGE_KINDS), count: z.number().int().nullable() })) });
export const AdminReportRow = z.object({ id: z.string().uuid(), target: AdminCompetitorRow, reason: z.enum(['name','photo','other']),
  count: z.number().int(), createdAt: z.string() });
export const ResolveReport = z.object({ resolution: z.enum(['dismissed','actioned']), reason: z.string().trim().min(3).max(500) });
```
Close, cancel, rollover, competitor actions and live-tournament PATCH bodies use the existing `AdminReason` (`{reason}`).

### 3.2 Edits to existing contracts
- `enums.ts`: `ConsentKind` adds `'community'`; `FEATURE_FLAGS` adds `'leagues','tournaments','leaderboard'`.
- `api.ts`: `UserSettings` adds `country: z.string().regex(/^[A-Z]{2}$/).nullable().optional()`; `RemoteConfig.features` defaults gain the three flags (false).
- `profile.ts`: `PublicProfileView`, `MyJourney`, `AdminCardRow` add `avatar: Avatar`; `PublicProfileView.level` is computed from `public_lifetime`. `levelFor` unchanged.
- `events.ts`: `onboarding_step.step` adds `'profile'` before `'download'`.

### 3.3 Endpoints (app)

`requireUser` applies unless noted. Competition endpoints answer `403 feature_off` when their flag is off (`leagues` → `/v1/leagues/*`, `tournaments` → `/v1/tournaments/*`, `leaderboard` → `/v1/leaderboard`); `/v1/me/community` checks the flag of the switch being turned on.

| Method & path | Body → response | Errors |
|---|---|---|
| GET `/v1/me/profile` | → `MeProfile`. Side effect: when opted into leagues, calls `ensurePlacement` (which may return `closing`). | — |
| PATCH `/v1/me/profile` | `UpdateProfileRequest` → `MeProfile` | 403 `account_required`, 400 `invalid_name`, 409 `name_locked`, 400 `validation` |
| PUT `/v1/me/avatar/photo` | raw `image/jpeg|png|webp` ≤ 3 MB → `Avatar` | 403 `account_required`, 409 `photo_locked`, 413 `photo_too_large`, 415 `photo_type`, 422 `photo_unreadable`, 429 `rate_limited` (10 uploads per rolling hour, counted in `avatar_photos`) |
| DELETE `/v1/me/avatar/photo` | → `Avatar` (preset if set, else initial) | — |
| GET `/v1/me/avatar/photo/:size` | own **active** photo (96/256), regardless of visibility; never `removed`; per-size ETag | 404 |
| POST `/v1/me/attestation` | `AttestRequest` → `CommunitySettings` (sets `adult_attested_at`, audit `user.attest_adult`) | 403 `account_required` |
| GET `/v1/me/community` | → `CommunitySettings` | — |
| PUT `/v1/me/community` | `CommunityUpdate` → `CommunitySettings`. One transaction: members upsert, attestation, `recomputeCommunityConsent`, draft `public_profiles` + `competitorHandle`, leave on off. | 403 `account_required`, 403 `community_banned`, 400 `attestation_required`, 400 `name_required`, 400 `invalid_name`, 409 `name_locked`, 403 `feature_off` |
| PUT `/v1/me/consents` (existing) | `kind:'community'`: withdraw = leave everything; grant = refused | 403 `use_community_settings` |
| GET `/v1/me/badges` | → `Badge[]` (newest first) | — |
| GET `/v1/leagues/current` | → `LeagueCurrent` (rows from snapshots; cached 60 s per group in namespace `community`; `me`, blocks and `myLivePoints` applied per caller after the cached read) | 403 `feature_off` |
| GET `/v1/leagues/history` | → `LeagueHistoryItem[]` (last 12 weeks) | — |
| GET `/v1/tournaments` | → `Tournament[]` (published; live + upcoming + ended in the last 30 days) | — |
| GET `/v1/tournaments/:id` | → `Tournament` | 404 |
| POST `/v1/tournaments/:id/join` | `JoinTournamentRequest` → `Tournament` | 403 `account_required`, 403 `community_banned`, 409 `tournament_not_open`, 400 `ack_required`, 400 `attestation_required`, 400 `name_required` |
| DELETE `/v1/tournaments/:id/join` | → `Tournament` (sets `left_at`, recomputes consent) | — |
| GET `/v1/tournaments/:id/standings?cursor=` | → `TournamentStandings` (snapshot ranks, pages of 100 by `(snapshot_rank, handle)`) | 404 |
| GET `/v1/leaderboard?scope=global|country` | → `LeaderboardView` (top 100 + me from `leaderboard_snapshot`; cached 120 s) | 409 `country_unknown`, 409 `country_too_small` |
| POST `/v1/community/reports` | `ReportRequest` → 204 (idempotent while open; 20 per rolling 24 h in DB) | 404, 429 `rate_limited` |
| GET/POST `/v1/community/blocks`, DELETE `/v1/community/blocks/:handle` | `BlockRequest` → `BlockedUser[]` / 204 | 404 |
| GET `/v1/public/avatars/:photoId/:size.webp` | **public**. Served only when: photo `active`; owner `status='active'` and not deletion-requested; `adult_attested_at is not null`; owner actually visible = (`leagues` or `leaderboard` or an active tournament entry, and not banned) **or** (card published and not moderated). `Cache-Control: public, max-age=300, stale-while-revalidate=60`; ETag = that size's sha. | 404 |
| GET `/u/assets/avatars/:id.webp` | **public**. Preset art (embedded like `brand-assets.ts`), immutable | 404 |

**Public projection** (shared `publicCompetitor(row, caller)`): `name` null when `name_hidden_at`; `avatar` = photo (public URLs) only when the photo would pass the public route rule, else preset/initial; `level` from `public_lifetime`.

**Visibility filter** (every public list, applied at read time on top of snapshots): `users.status='active'`, not deletion-requested; `community_members` with the relevant switch true and `banned_at is null`; league/tournament `left_at is null`; and not blocked in either direction with the caller.

**Ranking** (`rankStandings`): standard competition ranking on points (ties share a rank: 1, 1, 3); display order inside a tie is handle ascending; 0 points → rank null. The level board ranks by `public_lifetime` the same way. Ranks are computed in the nightly snapshot, not per request.

### 3.4 Endpoints (admin, prefix `/admin/competitions`)
Guards: `read = requireAdmin(['marketing','support'])`, `marketing = requireAdmin(['marketing'])`, `support = requireAdmin(['support'])`, `superOnly = requireAdmin([])` (super_admin always passes). Every write runs in `db.transaction`, calls `audit()`, and bumps `community` (plus `profile` for moderation).

| Endpoint | Guard | Audit action |
|---|---|---|
| GET `/tournaments`, GET `/tournaments/:id` | read | — |
| POST `/tournaments` (`AdminTournamentCreate`) | marketing | `tournament.create` |
| PATCH `/tournaments/:id`: draft = any field; published and not started = any field except slug; live = `lastDay` later only, `reason` required | marketing | `tournament.update` |
| POST `/tournaments/:id/publish` | marketing | `tournament.publish` |
| POST `/tournaments/:id/close` (`AdminReason`): sets `ends_at` to the next Cairo midnight (today counts), the job closes it after | marketing | `tournament.close` |
| POST `/tournaments/:id/cancel` (`AdminReason`): no badges, entries recompute consent | marketing | `tournament.cancel` |
| GET `/tournaments/:id/standings?limit=50` (snapshot, `AdminStandingRow`) | read | — |
| GET `/tournaments/:id/stats` (suppressed) | read | — |
| GET / PUT `/leagues/settings` (`LeagueSettings`; applies from the next week to start) | read / marketing | `leagues.settings` |
| GET `/leagues/stats`, GET `/leagues/groups/:id` | read | — |
| POST `/leagues/rollover` (`AdminReason`): runs the job body now | superOnly | `leagues.rollover` |
| GET `/leaderboard?scope=&country=` (snapshot) | read | — |
| GET `/competitors?filter=reported|hidden|banned|recent_photo&q=` | read | — |
| GET `/competitors/:userId` | read | — |
| GET `/competitors/:userId/photos/:photoId/:size` (any status within 7 days; `Cache-Control: private, no-store`) | support | — |
| POST `/competitors/:userId/:action` (`CompetitorAction`, `AdminReason`) | support | `competitor.hide_name` etc. |
| GET `/reports?status=open`, POST `/reports/:id/resolve` (`ResolveReport`) | read / support | `report.resolve` |
| GET `/badges`: catalogue + suppressed counts | read | — |

Admin error codes: `tournament_dates` (400), `slug_taken` (409), `tournament_not_editable` (409), `tournament_closed` (409), `settings_invalid` (400), `nothing_to_restore` (409), `reason_required` (400). `INVALIDATES['/admin/competitions'] = ['community','profile']`. `CacheNamespace` adds `'community'`.

### 3.5 Pure domain (`services/api/src/domain/community.ts`, unit-tested)
- `weekWindow(now, tz='Africa/Cairo') → {startsOn, startsAt, endsAt}` (DST-safe via `localToday`/`addDays`).
- `cairoMidnight(day) → Date`; `isCairoMidnight(date)`.
- `rankStandings(rows: {userId, handle, points}[]) → {userId, rank|null, order}[]`: competition ranking, handle order inside ties, 0 → null.
- `effectiveZones(size, settings, division) → {promote, demote}` in this order:
  1. `size < 5` → promote 0, demote 0;
  2. else `promote = min(settings.promote, floor(size/3))`, `demote = min(settings.demote, floor(size/3))`;
  3. then division 6 → promote 0; division 1 → demote 0 (these override everything).
- `outcomeFor(rank, size, points, zones)`: `up` when `rank ≤ promote` and `points > 0` (everyone tied at the boundary rank is included); `down` when `rank > size - demote` (ties at the boundary all stay up/stay — the kinder side); else `stay`. Members who left: no outcome.
- `leagueBadge(rank, size, points, outcome)`: `league_first` (rank 1, size ≥ 5, points > 0) > `league_top3` (rank ≤ 3, size ≥ 5, points > 0) > `league_promoted` (outcome up, points > 0). Ties share the badge.
- `tournamentBadge(rank, n, points, minPoints)`: `tournament_podium` (rank ≤ 3, n ≥ 10, points ≥ minPoints) > `tournament_top10` (rank ≤ ceil(0.1 n), n ≥ 10, points ≥ minPoints) > `tournament_finisher` (points ≥ minPoints). Ties share.
- `validateTournament(input, now)`: Cairo-midnight alignment, `startsAt < endsAt`, `joinUntil ≤ endsAt`, ≤ 90 days, slug regex → `tournament_dates`.
- `canonicalName(input)` (trim, collapse spaces, NFC), `nameProblem(name, reserved)` (bidi/zero-width/reserved/brand/profanity), `competitorHandle(name, rand)`.

---

## 4. Jobs

### 4.1 `services/api/src/jobs/community.ts` (script `job:community`)
`runJob(env, 'yaqeen-community', '7 * * * *', () => withJobLock(pool, 'community', run))`, hourly, no Redis. Each step is resumable; no step holds one giant transaction.
1. **Ensure week rows.** The current and next `league_weeks` rows exist. When the current week has `settings is null`, fill it from `app_config 'leagues'`.
2. **Close due weeks, one group at a time.** For the oldest week with `status='open' and ends_at <= now`:
   - loop: in its own transaction, claim one group with `update league_groups set closed_at=now() where id = (select id from league_groups where starts_on=$1 and closed_at is null order by id limit 1 for update skip locked) returning *`;
   - compute finals from `points_earned_daily` for days `starts_on..starts_on+6` (members with `left_at is null`; zones from `league_weeks.settings`), write `final_points`, `final_rank`, `outcome`;
   - update `community_members.division` (±1, clamped 1..6) for members with an outcome;
   - insert `user_badges` on conflict do nothing (league tier + `division:<n>` on first reach);
   - **place continuing members** (opted in, not banned, not left) into the next week at their new division (packing algorithm of §4.2, under the same advisory locks);
   - when no unclosed group is left, mark the week `closed` and set the next week's `settings` if null.
   - A crash mid-close resumes from the remaining unclosed groups.
3. **Nightly snapshot** (once per Cairo day; skipped if `community_snapshot_days` has today), in batches:
   - open league groups: `snapshot_points` = earned days `starts_on..today-1`, `snapshot_rank` by `rankStandings`;
   - live and just-ended tournaments: same over window days `< today`;
   - `user_point_totals.public_lifetime = lifetime_earned`, `public_day = today`;
   - rebuild `leaderboard_snapshot` for scope `global` and for each country with ≥ 20 `leaderboard_country` participants;
   - insert `community_snapshot_days(today)`.
4. **Close due tournaments in batches.** For every `published` tournament with `ends_at <= now and closed_at is null`: set `finalizing_at` if null; compute ranks over all entries (deterministic: window days are before `ends_at`, and late qada lands after it); write `final_points`/`final_rank` for entries with `final_points is null` in batches of 1,000; award badges (`on conflict do nothing`); then set `closed_at` and call `recomputeCommunityConsent(source 'system')` for its entrants in batches. Cancelled tournaments: no badges, consent recomputed.
5. **Expire.** Resolved reports older than 180 days are deleted.

The job **never touches `points_ledger`** (DB test asserts the row count is unchanged).

### 4.2 Placement (`leagues.service.ensurePlacement`, request path)
Runs when the user is opted in and not banned:
1. Upsert the current week row (so the first deploy works before the job runs) and fill `settings` if null.
2. If any **earlier** week is still `open` with `ends_at <= now`, return `closing` and do not place.
3. If the user already has a row this week: clear `left_at` if set (rejoin), done.
4. Else take `pg_advisory_xact_lock(hashtext('league:'||starts_on||':'||division))`, join the first group of that division with `size < groupSize`, or create one; insert `league_members` (idempotent on PK); `size = size + 1`.

Packing (also used by the close step) fills groups to `groupSize` before opening another, so each division has at most one partial group; groups under 5 neither promote nor demote and award no first/top3 badges.

### 4.3 Deploy and monitoring
- `deploy/azure/main.bicep` `jobs` array: `{ name: 'yaqeen-community', command: ['node','dist/jobs/community.js'], cron: '7 * * * *' }`, **not** behind `redisOn`.
- `deploy/k8s/jobs.yaml`: CronJob with `concurrencyPolicy: Forbid`.
- `services/api/src/lib/metrics.ts`: gauges `yaqeen_league_weeks_overdue` (open weeks past `ends_at` + 2 h) and `yaqeen_tournaments_overdue` (published past `ends_at` + 2 h, not closed), computed from DB at scrape (cached 60 s), plus `yaqeen_community_snapshot_age_hours`.
- `deploy/k8s/monitoring/alerts.yaml`: `YaqeenLeagueWeekNotClosed`, `YaqeenTournamentNotClosed`, `YaqeenCommunitySnapshotStale` (> 26 h); the existing `YaqeenJobFailed` covers the job.
- Document all of it in `docs/OPERATIONS.md`, including `select yq_rebuild_points_rollups();`.
- `sharp` container smoke test: `services/api/scripts/sharp-smoke.mjs` decodes and re-encodes a fixture inside the `node:22-alpine` image built with `pnpm deploy`; a CI step runs it.

### 4.4 Purge job (`purge-deleted.ts`)
The user row is a tombstone, so cascades never fire. **At tombstone time** delete, per user: `avatar_photos`, `community_members`, `community_blocks` (both columns), `league_members`, `tournament_entries`, `user_badges`, `community_reports` (as reporter and as target), `leaderboard_snapshot`, `points_earned_daily`, `user_point_totals`; null `country`, `avatar_*`, `name_hidden_*`, `photo_locked_at`, `adult_attested_at`. A DB test enumerates every table with a user FK added in 0017 and fails if any is missing from the purge. **Daily**: delete `avatar_photos` with status `replaced`/`removed` older than 7 days.

---

## 5. Avatar and photo pipeline
1. **Presets (no network).** Source of truth `packages/brand/avatars/avatars.json` (`{id, gender, ar, en}` ×16). App: `apps/mobile/assets/avatars/<id>.webp` (already in pubspec). Dart `kAvatarPresets` mirrors the JSON (parity test). API: preset WebPs embedded by `services/api/scripts/gen-avatar-assets.mjs` into `src/web/avatar-assets.ts`, served at `/u/assets/avatars/<id>.webp`. Admin: copies in `apps/admin/public/avatars/`.
2. **Picking.** `core/platform/photo_picker.dart`: `PhotoPicker { bool get available; Future<PickedPhoto?> pick(PhotoSource) }`, `PickedPhoto{bytes, mime}`, `NoopPhotoPicker` default; `PluginPhotoPicker` (`image_picker`, BSD, free) with `maxWidth/maxHeight 1024, imageQuality 85, requestFullMetadata: false`, JPEG; overridden in `main.dart`. iOS usage strings localised via `InfoPlist.strings`; Android uses the system Photo Picker (no permission).
3. **Local first.** Bytes written to `<appDocs>/profile/avatar_local.jpg`, shown at once. Guests: the photo stays on the device until linking.
4. **Upload (signed-in)**: `ApiClient.putBytes('/v1/me/avatar/photo', …)` direct (not Outbox). Failure → keep the file, `pendingUpload` in KV, retry on resume/connectivity. Success → store the returned `Avatar`, fetch `GET /v1/me/avatar/photo/256` via `getBytes` into `<appDocs>/profile/avatar_<id>.webp`, delete the local jpg.
5. **Server processing** (`avatar.service.uploadPhoto`): magic bytes match the declared mime; ≤ 3 MB (encapsulated plugin with a content-type parser and route `bodyLimit`); DB rate limit 10/hour; `sharp(buf, {limitInputPixels: 40_000_000, failOn: 'error'}).rotate()`, ≥ 128 px, `.resize(256,256,{fit:'cover',position:'attention'}).webp({quality:80})` and the same at 96; `withMetadata()` is never called (test asserts `metadata().exif === undefined`); per-size sha256. Previous active → `replaced`. Bump `community` + `profile` caches. `sharp` (Apache-2.0) prebuilt for linuxmusl.
6. **Storage.** ≈ 30 KB per user in Postgres `bytea`. `avatarUrl()` is the single seam for a future CDN (`AVATAR_STORAGE`, documented, not built; a paid CDN needs owner approval).
7. **Serving.** Public URLs (`/v1/public/avatars/…`) only in public projections, under the rule in §3.3. The caller's own `MeProfile.avatar` carries the authed paths. Admin uses the admin photo route through a Next route-handler proxy.
8. **CSP.** No `img-src` CSP exists today on the admin or `/u/<handle>`; if one is added, it must include the API host. Noted in SECURITY_PRIVACY.md.
9. **Moderation.** `hide_photo` → `removed`, the public URL 404s within 5 min (max-age 300). The owner's app sees `photoHidden: true` on the next profile fetch, deletes its cached file and shows `pfAvatarHidden`.

---

## 6. Mobile screens

All screens follow DESIGN_SYSTEM: a `YqCanvas` with a `YqStage` (one moment), up to three `YqOrb`s that work in place, then groups/timelines; content clears the dock via `YqInsets.bottom`; ≥ 44-pt targets; survives 1.3× text; implicit animations only for value changes; reduce-motion jumps to the end state.

### 6.0 Shared identity core (contracts stream)
- **Domain**: `features/profile/domain/avatar.dart` (`sealed AvatarRef` = `InitialAvatar` | `PresetAvatar(id)` | `PhotoAvatar({id, url, smallUrl, localPath})`; `isAuthedPath` when url starts with `/v1/me/`), `avatar_presets.dart`, `level.dart` (`CardLevel`, `cardLevels`, `levelFor` moved from `features/card/domain/public_card.dart`, re-exported there), `me_profile.dart` (`MeProfile`, `CommunitySettings`, `LeagueSummary`, `LeagueLastWeek`, `MeProfile.guest`).
- **Data**: `ProfileRepository({api, store, outbox, docsDir})`, KV `profile.me.v1`:
  - `cached()`, `refresh()`;
  - `saveName`, `saveAvatar`: local first, then replace any queued `PATCH /v1/me/profile` in the Outbox; guests local only and mark KV `profile.dirty.v1 {name, avatar, photo}`;
  - `uploadPhoto`, `removePhoto`;
  - `joinCommunity(CommunityUpdate) → Result<CommunitySettings, CommunityFailure>`: **direct** `PUT /v1/me/community`; offline → `CommunityFailure.offline`; maps every `COMMUNITY_ERROR_CODES` value; on success `consents.adopt(community, granted)`;
  - `leaveCommunity({leagues?, leaderboard?, leaderboardCountry?})`: Outbox `PUT /v1/me/community` with falses, local state updated at once;
  - `attest()`: direct `POST /v1/me/attestation`;
  - `pushAfterSignIn()`: after linking, `refresh()` first, then push **only dirty** fields (server values win otherwise), upload a local photo only if `photo` is dirty, then clear dirty;
  - `wipe()`: KV `profile.*`, `community.*` and the profile dir.
- **Controller**: `meProfileProvider` (`AsyncNotifier`): cache or guest value immediately, background refresh when `canEarnPoints`; `setName`, `setAvatar`, `pickPhoto`, `removePhoto`, `join`, `leave`, `attest`, `refresh`. `levelUpProvider` exposes `pending` (cached level < refreshed level, tracked by KV `profile.lastSeenLevel`) and `markSeen()`; whichever screen shows the moment first consumes it.
- **Widgets**: `YqAvatar`, `YqLevelAvatar`, `YqSkeletonAvatarRows` (`core/widgets/yq_avatar.dart`) — `YqAvatar` loads authed paths through `ApiClient.getBytes` (memory-cached), public URLs with `Image.network(cacheWidth)`, assets and files directly; skeleton circle until the first frame; fallback initial in ink on `YqColors.ice`; white rim. `YqLevelAvatar` wraps it in `YqRing(color: lapis, track: lapis100 .5)`, `achieved` → gold ring + one-shot 600 ms glint (skipped under reduce-motion), optional level numeral badge at bottom-end. `YqRing` gains `Color? color`, `bool glint`. `MeAvatar`. `YqTab.avatar` (lapis rim when active, white otherwise; gold disc removed).
- **Icons** `YqIcons`: `memorise`, `recite`, `hifz`, `trophy`, `badge`, `league`, `podium`, `camera`, `photo`, `edit`, `flag`, `sync`, `lock`, `block` (24-grid line icons, no ornament).
- **Stubs** (contracts creates, the owning stream fills): every new screen class registered in the router; `features/community/presentation/week_result_sheet.dart` with `Future<void> maybeShowWeekResult(BuildContext, WidgetRef)` (no-op); `features/quran/data/session_store.dart` with `QuranSessionStore.kvKey = 'quran.session.v1'` and `static Future<void> wipe(KvStore)`.

### 6.1 Profile tab `/profile` (rebuilt; `21 · Profile`)
**Stage** (`YqStage`, not gold):
- `YqStageBar(large: true, title: t.tabProfile, actions: [GlassIconButton(settings) → /profile/settings])`.
- **Moment:** `YqLevelAvatar(size: 120, stroke: 4, achieved: top level or a pending level-up)` with a 32-pt glass edit badge (`YqIcons.edit`, «تغيير الصورة») → Avatar sheet. Tapping the avatar opens the same sheet. When `levelUpProvider.pending` and Home has not consumed it, the glint plays and a quiet toast «بلغت مستوى {name}» shows, then `markSeen()`.
- **Name** `YqMoment.display(size: 28)` in ink → Edit-name sheet. Hidden → «عضو يقين» muted + lock glyph.
- **Caption** (muted 13): «المستوى {n} · {levelName}» + « · @{handle}».
- **Guest:** ring at 0; «مستواك ورحلتك يُحفظان حين تسجّل الدخول»; ink pill «سجّل الدخول لحفظ نقاطك» → `showSignInSheet`.
- **Pending sync:** muted line with `YqIcons.sync`.

**Orbs** (three, ink and lapis):
1. **Level**: lapis ring + ink numeral; «{n} للمستوى التالي» / «أعلى مستوى»; tap → level ladder sheet (six rows, current lapis, gold dot on reached, note «المستوى يُحسب من كل النقاط التي كسبتها، ولا ينقص حين تستبدلها.»).
2. **Points** (rewards flag + signed in; else a **Language** orb): «الرصيد»; tap flips to «هذا الأسبوع» (`weekPoints`, self only); long-press → `/profile/ledger`.
3. **League** (flag `leagues`): division name, «{rank} من {size}» (snapshot; «—» before the first snapshot) → `/profile/leagues`; not joined: «الدوري» / «انضم», lapis outline disc. Flag off: **Downloads** orb.
- Loading: `YqSkeleton(YqSkeletonOrbs(count: 3))`. The orb set is decided from flags and session only, so it never swaps.

**Body**: (1) «الشارات» strip (the only gold block), «الكل» → `/profile/badges`, empty «تظهر شاراتك هنا حين تكسبها.»; (2) restyled Journey; (3) «المنافسة» group (rows per flag: «الدوري الأسبوعي», «البطولات», «لوحة المستويات», «الظهور في المنافسات»); (4) «بطاقة يقين» row; (5) rewards group (`gold: false`). Everything else moves to `/profile/settings`.

**States**: cold-start stage skeleton; error with cache → toast, without → `YqErrorState`; offline → `YqOfflineBanner`; pull-to-refresh invalidates profile, journey, challenge summary, downloads bytes. Motion: avatar cross-fade, eased rings, `CountUp`, one-shot glint, reduce-motion safe.

### 6.2 Settings `/profile/settings`
Compact stage + back «الإعدادات». Groups: account («اسمك», «صورتك», «الظهور في المنافسات» → `/profile/community`); app (Language & mushaf, Prayer, Privacy, Downloads); About/Terms/Privacy/Contact; Export, Delete (ink row; `YqColors.error` only on the destructive confirm), Sign out. Existing behaviours unchanged.

### 6.3 Avatar sheet
- «صورتك»; `YqSegmented` «الكل · رجال · نساء»; 4-column grid of `YqAvatar(64)` in 72-pt `GlassTap`s (semantics from preset ar/en); selected = 2-pt lapis ring + check.
- «التقاط صورة», «من الألبوم» (only when the picker is available); «إزالة الصورة» when a photo is set; «الحرف الأول من اسمك».
- Note «لا يرى صورتك غيرك إلا في بطاقتك أو في المنافسات التي تنضم إليها.»; guest note «تبقى صورتك على هذا الجهاز حتى تسجّل الدخول.»; when a photo is set, the user is visible, and `attestedAdult` is false: «يرى الآخرون صورة من المجموعة حتى تؤكد عمرك.» with the attestation switch (calls `attest()`).
- Hidden by support: «أخفى فريق الدعم صورتك. اختر صورة من المجموعة.» (photo actions disabled).
- Upload: shimmering lapis ring on the stage avatar; toasts «تعذّر رفع الصورة. حاول مرة أخرى.» / «الصورة كبيرة جداً. اختر صورة أصغر.» / «رفعت صوراً كثيرة. حاول بعد ساعة.» (429).

### 6.4 Edit-name sheet
«اسمك»; maxLength 40; hint «الاسم الذي يراه الآخرون»; helper «من 1 إلى 40 حرفاً»; invalid «اكتب اسماً من 1 إلى 40 حرفاً بلا روابط أو رموز.»; locked «أخفى فريق الدعم هذا الاسم. راسلنا لمراجعته.»; save «حفظ» (local first, Outbox PATCH; a server `invalid_name` on replay reverts to the server name with a toast).

### 6.5 Badges `/profile/badges`
Compact stage «{n}» / «شارة»; sections «الدوري», «البطولات», «المسيرة»; 3-column grid of earned medals only (gold rim, `badgeLabel()`, muted date). Skeleton circles, empty, error.

### 6.6 Weekly league `/profile/leagues`
- **Stage**: «الدوري الأسبوعي», subtitle «ينتهي بعد {days} أيام» / «ينتهي الليلة»; moment eyebrow = division name; value = my snapshot rank (or «—»); caption «{points} نقطة هذا الأسبوع» (`myLivePoints`, self only).
- **Body**: lazy rows — rank (Jost muted; «—» when null), `YqLevelAvatar(36, stroke 2)`, name or @handle, snapshot points («—» at 0); own row tinted `lapis .06`, labelled «أنت»; zone separators «يصعدون إلى {next}» and «يبدأون الأسبوع القادم في {prev}» (muted; absent when the zone is 0); «يُحدَّث الترتيب كل ليلة.»; long-press another row → report sheet; «الأسابيع السابقة»; sincerity + privacy lines; «شروط المنافسات»; «مغادرة الدوري» → confirm «ستختفي من ترتيب هذا الأسبوع فوراً، ويمكنك العودة متى شئت.» / «غادر» (queued).
- **States**: `off` → explainer + «انضم»; guest → «سجّل الدخول لتنضم إلى المنافسات»; `closing` → «نحسب نتائج الأسبوع… عُد بعد قليل»; banned «أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.»; loading = stage skeleton + `YqSkeletonAvatarRows(rows: 8)`; offline = KV `community.league.v1` + banner; error = retry.
- **Join sheet**: «انضم إلى الدوري الأسبوعي»; body «كل أسبوع تُوضع مع نحو 30 مشاركاً في قسمك. الأعلى نقاطاً يصعدون، ويبدأ الأقل في القسم السابق.»; «الاسم الظاهر» prefilled with the first name; the required attestation switch «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري» (hidden when already attested); privacy line; «شروط المنافسات»; «انضم» (disabled until valid) / «ليس الآن». Direct call; offline → «تحتاج اتصالاً للانضمام»; typed errors shown inline.
- **Week result sheet** (`maybeShowWeekResult`): once per `lastWeek.startsOn` (KV `community.seenWeek`), from `meProfile.league.lastWeek`: «انتهى الأسبوع»; «صعدت إلى {division}» / «تبقى في {division}» / «تبدأ هذا الأسبوع في {division}»; gold badge if earned. Called by Home after the first frame and by LeagueScreen.

### 6.7 Tournaments `/profile/tournaments`, `/profile/tournaments/:id`
- **List**: «جارية · قادمة · انتهت»; LiquidGlass cards: title, long-date window, «تنتهي بعد {days} أيام» / «تبدأ بعد {days} أيام» / «انتهت», «{n} مشارك», «أنت مشارك». Empty «لا بطولات الآن. نُعلن عنها في مواسم مثل رمضان وذي الحجة.»
- **Detail**: stage moment = my rank or «انضم»; caption «{points} نقطة في البطولة» (self live); body; «الشارة: {label}»; paged snapshot standings; «يُحدَّث الترتيب كل ليلة.»; «انضم إلى البطولة» → sheet with «أوافق على ظهور اسمي وصورتي ومستواي ونقاطي في هذه البطولة.» + attestation switch (both required); «مغادرة البطولة» (queued); «انتهى الانضمام» after `joinUntil`. States as §6.6.

### 6.8 Level leaderboard `/profile/leaderboard`
- `YqSegmented` «العالم · {countryName}» (names from `cities.json`); rows: avatar + level ring + level name, no points; «ترتيبك {rank}» pinned at the bottom (or «يظهر ترتيبك بعد التحديث الليلي» before the first snapshot).
- Not joined: «أظهرني في اللوحة» / «تظهر باسمك وصورتك ومستواك فقط.» (+ attestation).
- Country tab not joined: «أظهرني في لوحة بلدي» / «تظهر باسمك وصورتك ومستواك فقط، وتظهر في لوحة بلدك.»
- No country: «اختر مدينتك في إعدادات الصلاة لترى ترتيب بلدك.»; `country_too_small`: «لوحة بلدك تظهر حين يشارك فيها 20 شخصاً على الأقل.»

### 6.9 Community settings `/profile/community` «الظهور في المنافسات»
Switches «الدوري الأسبوعي», «لوحة المستويات», «لوحة بلدي» (each hidden when its flag is off; turning on = direct join with attestation; off = queued leave); active tournament entries with leave; the name row; «المحظورون» list with «إلغاء الحظر»; privacy, sincerity and «شروط المنافسات» lines; banned state.

### 6.10 Report sheet
«إبلاغ عن الاسم أو الصورة»; «اسم غير لائق», «صورة غير لائقة», «سبب آخر»; then «حظر {name}» («لن تراه ولن يراك في المنافسات.»); toasts «شكراً، سيراجعه فريق الدعم.», «تم الحظر.», 429 «بلغت حدّ البلاغات اليوم.».

### 6.11 Card `/profile/card` (touch-up)
`_CardPreview` draws `YqLevelAvatar(88, stroke 3)` from `meProfileProvider`; the editor's name prefills from the profile; when a photo is set and not attested, the attestation switch («لإظهار صورتك في البطاقة») appears. `ledgerProvider` moves to `features/rewards/presentation/ledger_providers.dart`. `/u/<handle>` draws the avatar inside its (public) level ring.

---

## 7. Home profile chip, level ring, and one-time moments (§5.9 amendment)
- **Placement:** start of the `_Header` row: `[ProfileChip] · [greeting/name/Hijri (Expanded)] · search · bell`. No new band; the hero stays the one moment.
- **Chip:** `YqLevelAvatar(size: 48, stroke: 2.5, showLevel: true)`; lapis ring; gold only during the level-up glint or at level 6; tap → light haptic + `context.go('/profile')`; semantics «{name}، المستوى {n} · {levelName}، {percent}%». Guest: no ring, «{name}، افتح ملفّك».
- **Data:** `meProfileProvider` only; Home never waits on the network; skeleton circle only with no value at all.
- **One-time moments after the first frame** (from cached data, at most one per open, sheet first): `maybeShowWeekResult(context, ref)`, else when `levelUpProvider.pending`, the chip glints and a quiet toast «بلغت مستوى {name}» shows, then `markSeen()`.
- **Challenge card fix:** when `canEarnPoints` and the challenge summary is loading with no value, `YqSkeleton(YqSkeletonBox(height: 72, radius: YqRadii.card))` instead of the join CTA.
- Goldens `home_{ar,en}.png` regenerated (on Linux CI, §14).

---

## 8. Onboarding profile step `05·ج «ملفّك»` (`/onboarding/profile`)
- **Order:** `onboardingRoutes = [welcome, language, prayer, consent, goal, routine, profile, download]`. Stepper total 6; «الخطوة {n} من 6»; «0{n} / 06»; eyebrow colour `YqColors.muted`. `_advance(context, ref, route)` replaces every hard-coded `_saveStep(ref, n)`.
- **Resume by route name.** `AppSettings.onboardingRoute` (String?, new) is written by `_advance`. `nextAfterSplash` prefers it; when null (settings saved before this release), the legacy `onboardingStep` index is read through the frozen v1 list `[welcome, language, prayer, consent, goal, routine, download]`, so an old step 6 still resumes at download.
- **UI** (`_Step(step: 6, …)`): live preview `YqLevelAvatar(112, stroke 4, progress 0)` + name + «بداية الطريق»; «صورتك» (photo tile first when available, 16 presets, filter, skeleton circles while decoding); «اسمك» (40 max, prefilled with the **first name** from Google/Apple; helper «يظهر في المنافسات وبطاقتك فقط إن اخترت ذلك.»); glass card «المستويات والمنافسات» (three lines from §12.4); switch «انضم إلى الدوري الأسبوعي» (default **off**) with detail «يرى المشاركون اسمك وصورتك ومستواك ونقاط الأسبوع فقط.»; when the switch is on, the attestation switch appears and is required; green note «لا يرى أحد صلواتك ولا أذكارك ولا مهامك. تغادر متى شئت.»; «شروط المنافسات» link.
  - Guest switch tap → `showSignInSheet(title: «سجّل الدخول لتنضم إلى الدوري»)`; on only if it returns true and `canEarnPoints`.
  - Flag `leagues` off: switch and weekly line hidden.
- **CTA «متابعة»:** `setName` → `setAvatar`/photo → if the switch is on, `join(CommunityUpdate(leagues: true, displayName, attestAdult: true, source: onboarding))` (direct; on failure show the inline error/offline copy and let the user continue with the switch off) → `_advance` to download.
- **Skip** keeps defaults. **Guests** stay local; `SessionController._afterSignIn` calls `pushAfterSignIn()`; `deleteAccount` / `_forgetAccountCaches` call `profileRepository.wipe()`, `consents.adopt(community, false)`, and `deleteAccount` also calls `QuranSessionStore.wipe()` (sign-out keeps it, like other on-device Quran data).

---

## 9. Quran experience: «صفحة واحدة» with guided sessions

The printed Madani page in `ReaderScreen` (`/quran/read/:page`) is the only Quran surface (15 fitted lines, curl, print boundaries, spread, night, lock). Four modes «قراءة · استماع · تحفيظ · تسميع» are layers over a shared `Passage`; switching mode never pushes a route. An optional `QuranSession` (`wird|khatma|hifz|review|free`) adds goals, auto-ticks and kill-safe resume.

### 9.1 Rules
- **Counting:** `WirdRules` (≥ 20 s visible, one tick per day), `TaskKey.wird`, `TaskKey.listen` unchanged. The wird timer pauses only when a full-screen `PageRoute` covers the reader (RouteAware); modal/partial sheets (`PopupRoute`, `ModalBottomSheetRoute`) do not pause it; it counts only in the foreground with the screen on.
- **Privacy:** passage, session, reveals and raw recite results are device-only (KV `quran.session.v1`): never in backup, export, profile, competitions, admin, analytics or ads; wiped on account deletion by `session_controller.deleteAccount` → `QuranSessionStore.wipe()`; kept on sign-out. The **grade outcome** lives in hifz state (`HifzController.rate` / `memoriseToday`), which is already a backup kind — that is unchanged and intended.
- **Tokens:** playing ayah lapis wash ≈ 8% + 2-pt rail (`MushafColors.playing` / `playingRail`); margin `passageRail`; «تنبيه» muted dotted underline; gold only for a met goal / completed portion; the dock is `LiquidGlass` blur 0; the mini player has no live blur.
- **Content:** no new religious text; tafsir shows its attribution or `[نص التفسير من المصدر المرخّص]`.
- **Degrading:** no timings → follow only at surah boundaries and use the «كرّرت» counter; recite flag off/model missing → no recite segment, tests use memorise «words» + self-check; no audio offline → «تنزيل السورة» on the `DownloadQueue`, or «تخطَّ إلى التكرار».

### 9.2 Journeys
1. **Read → listen.** «استماع» → `ListenController.open(surah, ayah: firstOfPage)`; same surah already playing → seek only. The page follows the audio (curl, or cross-fade under reduce-motion), announces «صفحة {page}»; in a spread it turns only when the ayah leaves both pages; never while a sheet is open or locked. Chrome collapses to a 3-pt hairline + play glyph after 4 s.
2. **Manual look-ahead**: following pauses 8 s; chip «عُد إلى موضع التلاوة».
3. **Leave the reader**: `MiniPlayer` above the dock (surah, step label, `YqRing` progress around play/pause, close = pause + dismiss); tap → `/quran/read/<pageOf(ref)>?mode=listen`; hidden while the reader is on top and during reciter samples. The shell adds its height to the `MediaQuery` bottom padding (the same way the dock is counted), so `YqInsets.bottom` clears it without editing `yq_layout.dart`.
4. **Expanded player** `PlayerSheet` (orbit scrubber, `RepeatSheet`, speed, sleep, «تغيير القارئ», jump picker, tafsir line).
5. **Wird session** (`SessionStartSheet`: «ابدأ وردك», «{pages} صفحات من ص {page} · نحو {minutes} د», «مع التلاوة»); session line «{done} / {goal}»; end card with gold only when the goal is met.
6. **Khatma by ear** «استمع إلى الحصّة».
7. **Memorise any passage** («احفظ من هنا» → `PassagePickerSheet`, or «إلى هنا»); strip «الآيات / كلمة وكلمة», «إظهار الكل», «إخفاء الكل», «×{n} / 10», «استماع ×3».
8. **Recite where I am** (`Passage.ofPage(page)`, pauses listen first; notes muted «تنبيه»; «{ayat} آيات · {notes} ملاحظات»; tap a note plays that ayah once).
9. **Guided hifz** `?session=hifz&surah&from&to`: «استماع ×3» → «تكرار ×10» (echo, or counter) → «اختبار»; idempotent `HifzController.completeStep(i)`; `GradeSheet` pre-selects `suggestGrade` («اقتراح: {grade}»), the user confirms, then `memoriseToday()` with one gold glint.
10. **Due review** opens at the test stage; on «انتهيت» or leaving → grade sheet → `HifzController.rate`.
11. **Index**: long-press surah → modes sheet; listen orb shows playing surah + ring; «أكمل جلستك · ص {page}».
12. **Stale sessions** dropped after midnight, a plan edit, or when the portion is no longer today's; «استبدال التشغيل الحالي؟» before taking over another surah's audio.

### 9.3 Components
`QuranModeDock` (≤ 640 pt, four flag-gated segments, lapis thumb on the dock spring, labels collapse to icons when 1.3× text would overflow 360 pt, no segmented control when only «قراءة» remains, pinned in hifz/review sessions, else auto-hides after 4 s); strips (read, listen, memorise, recite); stage dots; session line; sheets (`PlayerSheet`, `RepeatSheet`, `SessionStartSheet`, `PassagePickerSheet`, `GradeSheet`, index modes sheet, `SessionEndCard`); `YqSkeletonMushafPage`; overlays painted outside the `MushafPager` GPU snapshot; lock ring = `YqRing`.

### 9.4 Routes (in `lib/app/routes/quran_routes.dart`, owned by the quran stream)
- `/quran/read/:page?mode=listen|memorise|recite&surah=&from=&to=&session=wird|khatma|hifz|review&portion=&player=open`.
- `/quran/listen/:surah[?ayah&to]` and `/quran/recite/:surah[?from&to&hifz]` are **redirects** into the reader at `pageOf(surah:ayah)` when `QuranData` is loaded, else the surah's start page from the bundled surah→page table (synchronous); `listen` adds `player=open`.
- `pushListen` stays exported from `features/listen/presentation/now_playing_screen.dart` and opens the reader.
- The flag-off `ReaderScreen`-inside-`ReciteScreen` fallback is removed; back uses `canPop`, else `/quran`.

### 9.5 Code changes
As in revision 1: `ListenController.open(..., {int? times})` honours `times`; same-surah open seeks; `roundsDone`/`loopEnded`; `playPassage`, `playAyahThenPause`; `DownloadsController.downloadSurah` on the `DownloadQueue`; `recite_controller.dart`; `hifz_guide.dart`, `grade_suggestion.dart`; separate `playing` paint, `marks`, `passage`; ayah sheet «استمع من هنا / احفظ من هنا / سمّع من هنا · إلى هنا»; raw colours → tokens; Home entry points via `session/quran_entry.dart` (`startWirdSession`, `openQuranListen`, `quranResumeProvider`).

---

## 10. Shimmer and skeleton sweep
Rule: never a bare spinner; loading is a shaped skeleton inside **one** `YqSkeleton`; determinate progress is a `YqRing`. Exception: pull-to-refresh keeps Material's `RefreshIndicator` pull cue (`core/widgets/yq_stage.dart`, `features/home/home_screen.dart`) — the content stays on screen while it runs, so it is not a loading state; the guard allows it in those two files only.

| # | Location | Fix | Stream |
|---|---|---|---|
| 1 | `core/widgets/yq_button.dart:48` (`loading`, 11 call sites) | label stays and shimmers, fixed size, semantics «جارٍ التنفيذ», static at 60% under reduce-motion | skeletons |
| 2 | `rewards/presentation/redeem_screen.dart:225` | `YqSkeleton(Column[circle(64), line(.5)])` + text | skeletons |
| 3 | `content/presentation/pack_row.dart:82` | `YqRing(value, 22, 2.4)` | skeletons |
| 4 | `card/presentation/encode_screen.dart:212` | wrap in `YqSkeleton` | skeletons |
| 5 | `listen/presentation/now_playing_screen.dart:223` | `YqRing` | quran |
| 6 | `listen/presentation/reciters_screen.dart:351` | `YqRing(18)` | quran |
| 7 | `quran/presentation/reader_screen.dart:1198` lock | `YqRing` | quran |
| 8 | `reader_screen.dart:374/819` | `YqSkeletonMushafPage` | quran |
| 9 | `quran_index_screen.dart:580` | `YqSkeletonRows(4, leading 40)` | quran |
| 10 | `khatma_screen.dart:49/57/237/321` | stage circle 140 + lines; rows; box 120; rows | quran |
| 11 | `hifz_screen.dart:392` | `YqSkeletonText(3)` | quran |
| 12 | `ayah_results.dart:48` | `YqSkeletonRows(3, leading 0)` + count line | quran |
| 13 | recite mic while availability unknown | shimmer disc | quran |
| 14 | `mushaf_download.dart:58` | skeleton line | quran |
| 15 | mini player / listen strip while loading | skeleton pill | quran |
| 16 | `profile_screen.dart:570` downloads | `YqSkeletonRows` | profile |
| 17 | `journey_widgets.dart:332` | wrap in `YqSkeleton` | profile |
| 18 | Profile stage, orbs, badges, downloads orb | §6.1 | profile |
| 19 | `home_screen.dart:557` | §7 | home-onboarding |
| 20 | `onboarding_screens.dart:1081` | `YqSkeletonBox(44, chip)` | home-onboarding |
| 21 | every new competition screen | `YqSkeletonAvatarRows` + stage skeleton | competitions |
| 22 | admin `(dash)/loading.tsx`, `competitions/loading.tsx`, `Suspense` | `Skeleton*` in `ui.tsx` | admin |
| 23 | guard `test/core/no_spinner_test.dart` | fails on the three spinner names outside `core/widgets/yq_states.dart` | skeletons |

---

## 11. Admin
- **«المسابقات»** at `/competitions` (sidebar after `/rewards`, `trophy` icon); `NAV_ACCESS['/competitions'] = ['super_admin','marketing','support']`.
- **Tabs** (`?tab=`):
  1. **«البطولات»**: table (title, window `longDate` with Hijri, status badge from `TOURNAMENT_STATUS`, participants); `/competitions/tournaments/new` and `/[id]` controlled client forms with **date pickers** (Cairo days: «اليوم الأول», «اليوم الأخير», «آخر يوم للانضمام»; the API stores Cairo midnights); hint «نص تسويقي فقط — لا آيات ولا أحاديث ولا أدعية»; presets «رمضان {hijriYear}», «العشر من ذي الحجة {hijriYear}» from the Hijri service (Egypt offset); intents save/publish; «إغلاق مبكر» and «إلغاء» with reason; live edits need a reason. Detail: Kpis (suppressed «—» under 20), `Bar`, top-50 snapshot standings (rank, `Avatar`, name/@handle, level name, points) with a «إجراء» `<details>` (support/super only), awarded badges after close.
  2. **«الدوري الأسبوعي»**: settings form (group size 10–50, promote, demote, six names; «تُطبَّق التغييرات من الأسبوع القادم»; shows the settings in force this week); stats; «تشغيل التدوير الآن» (super, reason); read-only group page.
  3. **«لوحة المستويات»**: global/country (snapshot), top 100 with SVG level ring; level distribution (suppressed).
  4. **«الإشراف»**: filters «مُبلَّغ عنه · مخفي · موقوف · صور حديثة»; rows with flags («أكّد العمر» yes/no), photo history thumbnails loaded through the admin photo proxy (any status within 7 days); actions «إخفاء الاسم» (note: «يُغيَّر المعرّف أيضاً ما لم تكن البطاقة منشورة»), «إظهار الاسم», «إخفاء الصورة», «استعادة الصورة», «إيقاف من المنافسات», «إلغاء الإيقاف», report «تجاهل / تم الإجراء»; each needs a reason («يُسجَّل في سجل التدقيق»).
  5. **«الشارات»**: read-only catalogue with suppressed counts (gold only here and podium ranks 1–3).
- **Photo proxy**: `app/api/competitors/[userId]/photos/[photoId]/[size]/route.ts` forwards to the admin API route with the admin session and returns `Cache-Control: private, no-store`.
- **`/users/[id]`** «المسابقات» card with the same actions and the Notice «لا تظهر هنا أي بيانات عبادة — النقاط فقط».
- **`/cards`** avatar thumbnails. **`/settings`** `FEATURE_LABEL` for the three flags.
- **Roles**: super_admin everything; marketing tournaments + league settings; support moderation + reports + photo route; content_editor and religious_reviewer get 403 on `/competitions`.
- **E2E**: `prepare.mjs` seeds one live tournament, a week/group with snapshot values, an opted-in attested member (preset `m03`) with ledger rows, one open report, a member with a support-removed photo. `admin.spec.ts`: `/competitions` in `SECTIONS`; standings show the member and points, no worship words; hide photo writes `competitor.hide_photo`; marketing sees no moderation forms; tournament create → publish → close; league settings save; `content_editor` gets 403; stats under 20 show «—»; axe passes. `cards.spec.ts`: `/u/<handle>` draws the avatar ring; a hidden photo URL 404s.

---

## 12. APP_SPEC text (added or replaced by the contracts stream)
The exact Arabic copy below is normative and uses Western digits. Placeholders in `{}`.

### 12.1 §5.24 `21 · Profile` — `/profile` (replace)
Purpose, layout, guest and states as in §6.1. Rules: gold only for earned badges, level-reached dots and the level-up glint; never shows which prayers or azkar; avatar and name saved locally first; delete is a two-step confirm; sign-out keeps on-device Quran data. Acceptance: no orb swap while loading; the stage skeleton only on a cold start without cache; avatar change works offline; a hidden photo falls back with «أخفى فريق الدعم صورتك. اختر صورة من المجموعة.»; the level-up moment shows once (Home or Profile).

### 12.2 §5.24·ب `21·ج · Settings` — `/profile/settings` (new)
As §6.2; avatar sheet copy §6.3; name sheet copy §6.4.

### 12.3 §5.26 amendments
Replace "No leaderboard" with: «Leagues, tournaments and the level leaderboard are opt-in (§5.31). Levels are computed from lifetime earned points: task, qada, bonus, milestone, grant and positive admin adjustments, excluding reversals. Public level rings use the nightly snapshot.» The card preview and `/u/<handle>` draw the avatar inside the level ring; a photo shows publicly only after the age attestation.

### 12.4 §5.7·ج `05·ج · Your profile` — `/onboarding/profile` (new)
Title «ملفّك في يقين», sub «اختر صورة واسماً. مستواك يكبر مع نقاطك.», lines «مستواك يرتفع مع نقاط التحدي، عبر 6 مستويات.», «دوري أسبوعي في مجموعات من نحو 30: الأعلى يصعد قسماً.», «بطولات موسمية مثل رمضان وذي الحجة، وجوائزها شارات.», switch and notes from §8, CTA «متابعة», skip «تخطٍّ». Rules: the league switch is off by default; guests must sign in; joining needs the attestation and a connection; guests' choices stay on the device until linking; resume by route name; Back goes to routine. §5.4–5.7·ب steppers read «الخطوة {n} من 6». §5.1 gains `/onboarding/profile`.

### 12.5 §5.9 amendment (Home)
Profile chip at the start of the header; semantics «{name}، المستوى {n} · {levelName}، {percent}%»; gold only during the glint or at «منارة»; one-time week result / level-up moment after the first frame.

### 12.6 §5.31 `25 · Community` (new)
- **Common rules**: opt-in, off by default, signed-in only; joining needs the attestation «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري» and a connection («تحتاج اتصالاً للانضمام»); leaving works offline. Public standings update **once a night** («يُحدَّث الترتيب كل ليلة.»); ties share a rank. Block and report on every list. Terms link «شروط المنافسات».
- **5.31.1 Weekly league** (flag `leagues`): six divisions برونز، فضة، ذهب، زمرّد، ياقوت، ألماس (admin may rename; changes apply from the next week); groups of about 30; Saturday 00:00 to Saturday 00:00 Cairo; points earned that week (task, qada, bonus, milestone; qada counts in the week it is claimed; a late claim never changes closed results); top 5 up, bottom 5 down, each capped at a third of the group; groups under 5 neither promote nor demote; division 6 never promotes, division 1 never demotes; up needs points above 0; leaving keeps your division with no result. Badges «المركز الأول في المجموعة», «بين الثلاثة الأوائل», «صعود إلى {division}», «بلوغ قسم {division}». Copy: «الدوري الأسبوعي», «ينتهي بعد {days} أيام», «ينتهي الليلة», «{points} نقطة هذا الأسبوع», «{rank} من {size}», «يصعدون إلى {division}», «يبدأون الأسبوع القادم في {division}», «أنت», «الأسابيع السابقة», «مغادرة الدوري», «ستختفي من ترتيب هذا الأسبوع فوراً، ويمكنك العودة متى شئت.», «غادر», «انتهى الأسبوع», «صعدت إلى {division}», «تبقى في {division}», «تبدأ هذا الأسبوع في {division}», «نحسب نتائج الأسبوع… عُد بعد قليل».
- **5.31.2 Tournaments** (flag `tournaments`): admin-created windows of whole Cairo days; ranked by points earned in the window; join until the last join day; leave any time. One badge per joiner at close: «منصّة {title}» (ranks 1–3, at least 10 joiners), «أعلى 10% · {title}», «إتمام {title}» (each needs at least `minPoints`). Copy: «البطولات», «جارية», «قادمة», «انتهت», «تبدأ بعد {days} أيام», «تنتهي بعد {days} أيام», «{n} مشارك», «انضم إلى البطولة», «أنت مشارك», «مغادرة البطولة», «انتهى الانضمام», «الشارة: {label}», «{points} نقطة في البطولة», «أوافق على ظهور اسمي وصورتي ومستواي ونقاطي في هذه البطولة.», «لا بطولات الآن. نُعلن عنها في مواسم مثل رمضان وذي الحجة.»
- **5.31.3 Level board** (flag `leaderboard`): global, plus a country board that is its own switch and exists only with at least 20 participants; level ring only, no points. Copy: «لوحة المستويات», «العالم», «ترتيبك {rank}», «يظهر ترتيبك بعد التحديث الليلي», «أظهرني في اللوحة», «تظهر باسمك وصورتك ومستواك فقط.», «أظهرني في لوحة بلدي», «تظهر باسمك وصورتك ومستواك فقط، وتظهر في لوحة بلدك.», «اختر مدينتك في إعدادات الصلاة لترى ترتيب بلدك.», «لوحة بلدك تظهر حين يشارك فيها 20 شخصاً على الأقل.»
- **5.31.4 Badges**: «الشارات», «{n} يوماً متتالية», «بلوغ مستوى {level}», «تظهر شاراتك هنا حين تكسبها.»
- **5.31.5 Visibility and safety** `/profile/community`: «الظهور في المنافسات», «لوحة بلدي», «المحظورون», «إلغاء الحظر», privacy line, sincerity line, report «إبلاغ عن الاسم أو الصورة» («اسم غير لائق», «صورة غير لائقة», «سبب آخر», «شكراً، سيراجعه فريق الدعم.», «بلغت حدّ البلاغات اليوم.»), block «حظر {name}», «لن تراه ولن يراك في المنافسات.», «تم الحظر.», banned «أُوقفت مشاركتك في المنافسات. راسلنا لمراجعتها.», name fallback «عضو يقين».
- **Acceptance (all)**: off by default; guests cannot join; the attestation is required; leaving removes the user at once; nothing public is live (a new point never moves a public list before the nightly snapshot); no worship detail; no ledger rows written by competitions; results in-app, never by push; offline shows the last cached view with the banner; blocked users disappear for both; withdrawing `community` from the privacy screen leaves everything.

### 12.7 §5.11 / §5.12 / §5.13 / §5.25 / §6.14 amendments
- §5.11: mode dock with four layers; pinned only in guided sessions; follow-audio rules (synced only, 8 s guard, spread rule, announcement); the wird timer pauses under covering full-screen routes only.
- §5.12: recite is a reader layer; `/quran/recite/*` redirects. §5.13: player sheet + app-wide mini player; `/quran/listen/*` redirects with `player=open`.
- §5.25: guided hifz (listen ×3, repeat ×10, test), auto-ticks, review opens at test. §6.14: suggested grade; the user confirms; the grade lives in hifz state (backed up), raw session data stays on the device.
- «جلسة» acceptance: kill-safe resume; stale sessions dropped; «استبدال التشغيل الحالي؟»; device-only; wiped on account deletion, kept on sign-out.
- Copy: «قراءة», «استماع», «تحفيظ», «تسميع», «عُد إلى موضع التلاوة», «صفحة {page}», «كرّرت», «من هنا», «إلى هنا», «استمع من هنا», «احفظ من هنا», «سمّع من هنا», «لا تلاوة على الجهاز», «تنزيل السورة», «تخطَّ إلى التكرار», «ابدأ وردك», «{pages} صفحات من ص {page} · نحو {minutes} د», «مع التلاوة», «أتممت جلستك», «التالي: {step}», «مراجعة مستحقّة», «أكمل جلستك · ص {page}», «{ayat} آيات · {notes} ملاحظات», «اقتراح: {grade}», «تأكيد», «ابدأ الحلقة», «أكمل الحلقة», «راجع», «استمع إلى الحصّة», «استبدال التشغيل الحالي؟», «استبدال», «إظهار الكل», «إخفاء الكل», «الآيات», «كلمة وكلمة», «افتح في المصحف», «استماع ×3», «تكرار ×10», «اختبار», «تنبيه», «انتهيت», back label «رجوع».

### 12.8 §2 / §6 loading rule
«No bare spinners. Loading is a shaped skeleton under one shimmer; determinate progress is a `YqRing`; buttons keep their label and shimmer it.» Enforced by `no_spinner_test.dart`. Pull-to-refresh is the one exception (see §10): its `RefreshIndicator` cue is allowed in `yq_stage.dart` and `home_screen.dart` only.

### 12.9 §7.1 / §7.2 / §8 / §9 and other docs
- §7.1/§7.2 rows for «07 · المسابقات»; §8 lists §3.3/§3.4; §9 lists §2. DATA_MODEL.md, API.md, SECURITY_PRIVACY.md (photo processing, snapshots, visibility, attestation, blocks, export/erasure, retention, CSP note) updated.
- DESIGN_SYSTEM §3/§4 rows (Home chip; Profile; League/Tournament/Leaderboard; Reader layers; `YqAvatar`, `YqLevelAvatar`, `QuranModeDock`, `MiniPlayer`, `YqSkeletonMushafPage`, `YqSkeletonAvatarRows`; dock «avatar, lapis rim when active»); DESIGN.md dock prose.
- `docs/STORE_LISTING.md`: App Store privacy answers add Photos or Videos (user content, linked, not tracking), Name, Other User Content; Google Data safety adds Photos, Name, "Other user-generated content" (collected, shared with other users only by user choice, deletable); UGC moderation statement (report, block, filter, terms).

---

## 13. Test plan

**Contracts / foundation**: zod round-trips; shared fixtures parsed by zod and Dart; `kAvatarPresets` ↔ `avatars.json`; `levelFor`, `DIVISIONS`, `BADGE_KINDS`, `COMMUNITY_ERROR_CODES` Dart ↔ contracts parity (fixtures generated from contracts by a script and checked for drift); `YqLevelAvatar` widget tests; `ProfileRepository` (local-first, Outbox replace, guest no network, join direct + offline failure + typed errors, leave queued, `pushAfterSignIn` pushes only dirty fields and server wins otherwise, `wipe`); migration on a clean DB and a seeded DB; trigger = `yq_rebuild_points_rollups()` recompute; onboarding legacy index mapping.

**API unit** (`community.test.ts`): `weekWindow` over Egypt DST; competition-rank ties; zones order (size < 5, caps, division 1/6 overrides); `outcomeFor` with ties at boundaries; badge tiers incl. ties and `minPoints`; `validateTournament` midnight alignment; `nameProblem` (bidi, zero-width, reserved, brand, profanity in ar/en); `competitorHandle`.

**API DB** (`community.db.test.ts`, `avatar.db.test.ts`, `community.privacy.db.test.ts`, `community.scale.db.test.ts`):
- snapshot lag: a ledger insert does not change league/tournament/leaderboard responses or public level rings until the snapshot step runs;
- generic consent route: withdraw leaves all; grant → `use_community_settings`;
- `consent_events` written on every path (community PUT, join, leave, tournament close, cancel, ban, erasure) with the right `source` and `attested_adult`;
- handle rotation on `hide_name` (card unpublished) and no rotation when the card is published;
- country board: < 20 → `country_too_small`; country switch separate;
- blocks hide both ways; block in export; purge;
- attestation required on every join; unattested photo not public (public route 404, projection falls back to preset);
- own photo route serves active only; public route visibility matrix (no card + no competitions → 404); admin photo route serves removed within 7 days, role-guarded; per-size ETag;
- placement at 00:01 before the job → `closing`, not placed; after the close step → placed at the new division; concurrent placements fill 30 then open a new group;
- tournament window: non-midnight input rejected; window days exact;
- ties at a promote boundary all promote; a solo group never promotes;
- guest merge mid-week keeps week points and gives the right level; rebuild equals trigger;
- late qada after close does not change finals;
- settings snapshot: changing settings mid-week does not change this week's zones;
- DB rate limits: 11th photo in an hour → 429; 21st report in 24 h → 429;
- close resumes after a simulated crash between groups; tournament batch close resumes; jobs run twice are idempotent; ledger row count unchanged;
- erasure clears blocks, snapshots, country; purge removes every table (enumerated); erasure cancel leaves the user out;
- EXIF stripped; 413/415/422/409 codes;
- `restore_photo` ignores user-removed photos;
- admin routes audit and enforce roles; feature flags → `feature_off`;
- scale: 50k seeded members, `EXPLAIN` of leaderboard top-100 + me and tournament standings page uses the snapshot indexes (no seq scan on ledger or daily);
- sharp container smoke test (CI).

**Admin and e2e**: §11.

**Mobile**: Profile (guest, signed-in, skeleton/no orb swap, offline, avatar sheet incl. attestation and 429 toast, name validation/lock, settings rows, gold only in badges strip, level-up moment once); Competitions (repository + typed failures, league states, «—» for 0/null, snapshot line, week result once, join needs attestation and connection, leave queued and hidden at once, tournament ack, paging, leaderboard country states, block + report, RTL, Western digits); Home + onboarding (chip from cache, tap, semantics, challenge skeleton, week result sheet on Home after the first frame, level-up toast once, onboarding resume by route and legacy index, guest local, guest switch → sign-in, signed-in join is direct with source onboarding, skip, back, `deleteAccount` wipes profile, community consent and `quran.session.v1`); Quran (unit + widget list from revision 1, plus: partial sheets do not pause the wird timer, redirects work before `QuranData` loads); Skeletons (`no_spinner_test`, `YqButton` loading).

**Goldens** are generated on the Linux CI runner (`.github/workflows/goldens.yml`), never on Windows/macOS.

**Before "done"** (every stream): `pnpm typecheck && pnpm test` (with `TEST_DATABASE_URL`), `pnpm --filter @yaqeen/admin build`, `pnpm --filter @yaqeen/e2e e2e`, `cd apps/mobile && flutter gen-l10n && flutter analyze --no-fatal-infos && flutter test`. Each stream reports exactly what it verified.

---

## 14. Streams and file ownership

Ownership is disjoint. To avoid conflicts in shared files:
- **Router.** The contracts stream registers every new route once in `lib/app/router.dart`, delegating to per-feature lists it creates and then hands over: `lib/app/routes/profile_routes.dart` (profile stream: existing `/profile` subroutes moved there + settings, badges), `lib/app/routes/community_routes.dart` (competitions: leagues, tournaments, tournaments/:id, leaderboard, community), `lib/app/routes/quran_routes.dart` (quran: existing `/quran` subroutes moved there unchanged), and `GoRoute(path: 'profile')` under `/onboarding` pointing at the `ProfileStep` stub. After contracts merges, **nobody edits `router.dart`**.
- **ARB.** The contracts stream adds **every** key named in this design (all prefixes) to `app_ar.arb` and `app_en.arb` with the final copy from §12 and the stream briefs. Streams then only change values of their own-prefix keys; if a stream truly needs a new key, it appends it inside its prefix block and resolves any merge conflict with `node tools/l10n/merge_arb.mjs` (union of keys, stable order; written by contracts).
- **Goldens** regenerated only via the Linux CI workflow, by whichever stream changes their look.

**Handoffs** (contracts runs first, then ownership passes):
1. Extract `_ContinueReading` → `features/home/widgets/continue_reading.dart` (`ContinueReading`), no behaviour change. Then `home_screen.dart` → home-onboarding; `continue_reading.dart` → quran.
2. `shell.dart` line ~85 → `YqTab.avatar(avatar: const MeAvatar(size: 24), …)`. Then `shell.dart` → quran.
3. Move the two Profile tests from `onboarding_profile_test.dart` into `test/features/profile_screen_test.dart`. Then each passes to its stream.
4. Stub screens/functions (§6.0) pass to their owners.

**ARB prefixes**: contracts `av`, `div`, `badge`, `lvl`; profile `pf`; competitions `cm`; home-onboarding `hm`, `ob` + existing `stepOf`, `stepEyebrow`; quran `qs` + existing `listenBack`, `readerMemorise`; skeletons `sk`.

Stream order: `contracts` first; then `api`, `mobile-profile`, `mobile-competitions`, `mobile-home-onboarding` and `mobile-quran` in parallel; `admin` after `api`; `mobile-skeletons` last.

---

## 15. Critique resolution (revision 2)
All 32 blocking items are accepted; none rejected.

| Item | Resolution |
|---|---|
| 1 Live points | Nightly snapshots (§1.1, §2, §4.1 step 3); no `last_earned_at`; public level ring from `public_lifetime`; tests §13 |
| 2 Generic consent route | §1.3 (withdraw = leave; grant → `use_community_settings`) |
| 3 Consent on every path | `recomputeCommunityConsent` + new sources (§1.3) |
| 4 Handle leaks name | rotation on `hide_name`, `competitorHandle`, first-name prefill, competitions use `users.display_name` (§1.3, §1.5) |
| 5 Country board | separate switch, K ≥ 20, disclosure copy (§1.3, §6.8) |
| 6 UGC | blocks, name filter, terms section (§1.5) |
| 7 Minors | attestation switch, `adult_attested_at`, `consent_events.attested_adult`, public photo gated (§1.3) |
| 8 Support photo view | admin photo route + proxy (§3.4, §11) |
| 9 Own photo | authed paths in `MeProfile`, active only, stricter public rule, per-size ETag (§3.3, §5) |
| 10 Policy/store docs | `site-pages.ts` → api; `STORE_LISTING.md` → contracts (§1.5, §12.9) |
| 11 Export/restore/cancel | §1.3, §1.5 |
| 12 Quran contradictions | §9.1; `deleteAccount` calls `QuranSessionStore.wipe()` (home-onboarding) |
| 13 Rollover race | §4.2 `closing`, batch placement at close, week upsert |
| 14 Tournament windows | Cairo-midnight alignment, date pickers (§2, §3.5, §11) |
| 15 Ties | competition ranking; boundary ties share outcome/badge (§1.4, §3.5) |
| 16 Small groups | rule order, size ≥ 5, thresholds, packing, leaving keeps division (§3.5, §4.2, §1.3) |
| 17 Guest merge | move daily rows, `yq_rebuild_points_rollups()` (§1.6, §2) |
| 18 Qada | §1.6, §12.6 |
| 19 Settings mid-week | `league_weeks.settings` (§2) |
| 20 Contracts compile | `LevelInfoSchema`, spelled-out admin schemas, Base/refined split, reasons, meta fields (§3.1) |
| 21 Migration | 0014 pattern, ALTER for circular FK, one 0017 with all new objects (§2) |
| 22 Rate limits | counted in DB (§1.5, §3.3) |
| 23 Erasure | §1.3, §4.4 enumerated purge test |
| 24 Moments | Home calls `maybeShowWeekResult` + level-up (§7) |
| 25 Join via Outbox | join direct, leave queued (§1.1 rule 6, §6.0) |
| 26 pushAfterSignIn | dirty flags (§6.0) |
| 27 Resume shift | `onboardingRoute` + frozen v1 list (§8) |
| 28 Scale | snapshots + indexes + 50k plan test (§2, §13) |
| 29 Giant transaction | per-group claim, batched tournaments (§4.1) |
| 30 Monitoring | gauges + alerts (§4.3) |
| 31 Shared files | route lists + all ARB keys by contracts, merge script, Linux goldens, shell padding (§14, §9.2) |
| 32 Tests | §13 |
| D notes | wird under sheets (§9.1); redirect fallback (§9.4); no mini-player blur (§9.1); sharp smoke (§4.3); CSP (§5); «ذهب» monochrome (§1.1) |

---

## 16. «تلاواتي» — members' own recorded recitations (addendum, owner decisions 2026-11-13)

Backend, AI check, admin queue and web card built by the `profile-recitations` stream; the mobile screens (verse picker, recorder, profile track cards, listener, reactions and comments) are built on these contracts by the mobile stream (APP_SPEC §5.24 «تلاواتي», §5.26, §5.31.6).

### 16.1 Owner decisions (final)
- A profile track is the user's **own voice**: they choose verses (surah + ayah range) and record themselves. No catalogue or famous-reciter picks, no other audio. **Max 30 s**, **up to 3** on a profile.
- **Moderated by AI voice recognition**, automatically and at extremely low cost: a self-hosted, Quran-tuned speech model checks that the recording recites the chosen verses. Borderline cases go to a human queue.
- Others can **react** (fixed set: «ما شاء الله» · «بارك الله فيك» · «أحسنت») **and comment** (text).
- Audience: Yaqeen members in the app, and optionally the owner's public web card `/u/<handle>`. Opt-in per recording; **private by default**.
- **Hybrid with on-device ASR:** the app runs a small Quran Whisper on the phone for live word-following and an instant pre-check; the server never trusts it. **Server verification runs only for members/public recordings** (on upload, or when a private one is switched to members/public). Private recordings never reach the AI check (`private_ready`, owner-only playback). Switching back to private keeps an approved result.
- **User-generated content, not Yaqeen's religious content.** CLAUDE.md rules 4 and 9 govern content Yaqeen publishes (azkar, duas, daily task, splash verse, Quran text/audio/tafsir we ship) and are unaffected: a user's own recitation is theirs (recorded in `docs/SECURITY_PRIVACY.md` › Voice recordings and the `/privacy` page). Rule 1: nothing about recordings reaches analytics or ad platforms. Rule 2 (spirit): admins see only recordings in the moderation queue (flagged or reported), never a user's recordings.

### 16.2 Contracts (`packages/contracts/src/recordings.ts`)
Limits `RECORDING_MAX_MS` 30 000 (+ 250 ms encoder tolerance), `RECORDING_MAX_BYTES` 200 000, `RECORDING_FORMAT` (AAC-LC .m4a, mono, 16 kHz, ≈ 32 kbps — the app records exactly this; the server checks `ftyp`, `mp4a`, `esds` and the length three ways — `mdhd`, `stts` timing, `stsz` frame count — against the longest, refusing a file whose lengths disagree or with a second sound track), `PROFILE_RECORDINGS_MAX` 3, `RECORDING_UPLOADS_PER_DAY` 10 (uploads + share-verifications per Cairo day; survives deletes), `COMMENT_MAX` 280. `RecordingStatus` processing · private_ready · approved · needs_review · rejected · removed; `RejectReason` not_matching · unclear · silence · too_long · removed_by_moderator; `RecordingVisibility` private · members · public; `REACTION_KINDS`; `Recording` (owner), `PublicRecording` (owner = the community's `PublicCompetitor`, points/rank null), `RecordingComment`, `RECORDING_ERROR_CODES` (incl. `own_recording`), `RECITATION_MATCH` thresholds, `AsrVerifyResponse`, admin queue shapes, `verseRef()` and `SURAH_NAMES` (generated). Dart mirrors: `apps/mobile/lib/features/recordings/domain/recording_models.dart` (fixtures `apps/mobile/test/fixtures/recordings`, constants generated by `tools/contracts/gen_recordings_fixtures.mjs`). Flag `recordings`, off by default.

### 16.3 Gates
Sharing (members/public), reacting, commenting and reporting need: signed in and not a guest (`account_required`), the 18+ attestation (`attestation_required`), the community opt-in — consent `community` with a handle (`community_required`) — and not banned (`community_banned`). Listening and reading comments need a signed-in account — a guest token (minted without signing in) or an inactive account gets `403 account_required`. Blocks (the community block table) hide both ways: views 404, actions `403 blocked`. A member's recordings disappear from members' views **and from the web card** when the owner leaves the community, is banned, loses the attestation or is deletion-requested (the card uses the same owner gate); their comments on others' recordings disappear the same way (nothing public after leaving) and come back only if they rejoin.

### 16.4 The AI check
- **Service** `services/asr`: Python 3.12, FastAPI, faster-whisper (CTranslate2 int8, CPU, greedy, `language=ar`, Silero VAD, word timestamps). Model `tarteel-ai/whisper-base-ar-quran` (**Apache-2.0**, revision `5c3c53f…`), converted at image build. `POST /verify` with the audio and `X-ASR-Token` → `{durationMs, speechMs, transcript, words}`; > 31 s refused; stateless, no audio/transcript logs; internal ingress; Azure Container App `yaqeen-asr`, min 0 / max 1 replicas, 1 vCPU / 2 GiB (scale to zero — a 30 s clip costs a few vCPU-seconds, inside the monthly free grant for thousands of recordings).
- **Matcher** `services/api/src/domain/recitation-match.ts`: a faithful port of the app's `RecitationAligner` (normalisation, dagger-alef rule, word Levenshtein, one-edit tolerance for 4+ letter words, ties prefer «not heard»), plus the heard-word index for karaoke timings. Expected words come from `services/api/data/quran-words.txt` (normalised keys generated from the app's bundled mushaf text; never displayed). **Verdict:** speech < 15 % → reject `silence`; nothing heard → reject `unclear`; coverage < 0.35 → reject `not_matching`; coverage ≥ 0.75 and speech ≥ 40 % and extra words ≤ 50 % → approve; else `needs_review`. Shared vectors `packages/contracts/fixtures/recitation-match/*.json` (generated from the mushaf text by `services/api/scripts/build-recitation-fixtures.ts`) run in the API test and in `apps/mobile/test/features/recitation_match_fixtures_test.dart` — both sides agree on every mark.
- **Orchestration:** after an upload or a share, the API verifies in the background (concurrency 1 per process, one retry after 30 s); the recording then stays `processing` and the sweep in the hourly community job (`job:community`, step 6) makes the third attempt on `processing` older than 10 min and sends it to review only after 3 failed attempts — a short outage or a cold start never sends every shared recording to the human queue. The sweep spends at most 3 minutes on AI calls per run (the rest wait for the next run); the admin «rollover» request makes none. The service's `413 too_long` (decoded audio > 31 s while the file claimed less) and `422` are final: rejected `too_long` / `unclear`, never retried. Without `ASR_URL` shared recordings go to `needs_review` — never auto-approved. The transcript and the device's `clientScore`/`clientWords` are kept only while the recording waits for a reviewer.

### 16.5 Comments, reactions, reports
Reactions: others react — one per viewer, idempotent, changeable, removable; the owner's own is refused (`403 own_recording`). Comments (pure `domain/comments.ts`, zero cost, no third party): Arabic/English normalisation (tashkeel, alef/ya/ta-marbuta/hamza seats, tatweel, repeated letters, leetspeak, spread-out letters), a seed word list (`services/api/data/comment-blocklist.txt`), links (any `label.tld` written without spaces, the spelled-out dot for common TLDs, «.»/«。»/«۔» dots, fullwidth forms via NFKC), phone numbers (in any Unicode digit set) and @mentions of non-members refused, every invisible format character (`\p{Cf}`) dropped first, ≥ 2 characters, ≤ 280; 5 per minute and 50 per day per author (counted under the author's row lock). The recording's owner may delete any comment on it and switch comments off. Reports (20 per reporter per 24 h): 3 distinct reporters hide a comment, or hold an approved recording out of every view, until support decides.

### 16.6 Web card
`/u/<handle>` gains «تلاواتي» for public + approved recordings: a play button with an SVG progress ring, a slow hairline ring while playing (off under `prefers-reduced-motion`), read-only reaction counts with a CTA to react in the app, and the verse reference «سورة … · الآيات …» (Western digits). The server holds no displayable Quran text, so the verses themselves are not shown. The player is a same-origin script (`/u/assets/recitations.js`, CSP `script-src 'self'`); audio from the same-origin path `/u/<handle>/r/<id>.m4a` (relative, so `media-src 'self'` and CORP `same-origin` hold on whichever host serves the card; byte ranges), served only while public + approved on a published, unmoderated card of a shareable owner, and only while `publicCards` is on (the kill switch that 404s `/u/:handle` takes the audio down too).

### 16.7 Admin «التلاوات»
Queue only: `needs_review`, held or reported recordings, reported or hidden comments, and what was removed in the last 7 days (to restore). Each item: the audio (proxy, only while queued), the verse reference, the AI score, speech share, transcript snippet, the device's score (for information), reports and reasons. Actions — `religious_reviewer`: approve, reject (reason); `support`: dismiss reports, remove, restore, and the same on comments. Every decision is audited in the same transaction. E2E: `e2e/tests/recitations.spec.ts`.

### 16.8 Data, export, erasure
Migration `0018_recordings`: `recordings`, `recording_reactions`, `recording_comments`, `recording_reports`, `recording_daily` (docs/DATA_MODEL.md). Export: recordings (metadata + audio base64), reactions, comments and reports made. Erasure: all of it deleted at the request (not after the grace period) and again at tombstone time. Policy version bumped to 2026-11-14.
