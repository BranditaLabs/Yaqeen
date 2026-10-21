# API reference

Base URL: `API_URL` (local `http://localhost:4000`). JSON only. Schemas: `packages/contracts/src/api.ts`.

**Errors** are always `{ "error": { "code": "snake_case", "message": "…", "details"?: … } }`. Clients branch on `code`, never on `message`.

**Auth:** app routes use `Authorization: Bearer <accessToken>` (15 min). Admin routes use the admin token (different secret + audience). Rate limits: 300 req/min/IP globally; sign-in 20/min; admin login 5 per 5 min; redeem 5/min.

## Public — app

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET | `/health` · `/ready` | — | Liveness · readiness (DB + Redis) |
| POST | `/v1/auth/sign-in` | — | `{provider: google\|apple\|guest, idToken?, displayName?, locale}` → session |
| POST | `/v1/auth/refresh` | — | `{refreshToken}` → new session; old token revoked |
| POST | `/v1/auth/sign-out` | user | Revokes all refresh tokens |
| GET | `/v1/config` | — | Remote config (features, min versions, maintenance, splash verse, Hijri offset). Cached 5 min |
| GET | `/v1/calendar/hijri?year&month&offset` | — | Gregorian month → Hijri days (UAQ + Egypt adjustment + personal offset) |
| GET | `/v1/content?type&since` | — | Published duas/azkar only; `since` for incremental sync |
| GET | `/v1/daily-task?date` | — | مهمة اليوم |
| GET | `/v1/me` | user | Profile + settings |
| PATCH | `/v1/me/settings` | user | Partial `UserSettings` |
| GET · PUT | `/v1/me/consents` | user | 4 buckets; PUT records an immutable consent event |
| POST | `/v1/me/devices` | user | Register/refresh FCM token |
| GET | `/v1/me/ledger` · `/v1/me/redemptions` | user | Points history · issued codes |
| GET | `/v1/me/export` | user | PDPL data access — everything held about the user |
| DELETE | `/v1/me` | user | PDPL erasure request (202, 14-day grace) |
| POST | `/v1/challenge/enroll` | user (not guest) | Starts day 1 today |
| GET | `/v1/challenge/summary` | user | Day number, streak, balance, today, task values |
| GET | `/v1/challenge/days?from&to` | user | ≤ 92 days; status per day for the merged calendar |
| POST | `/v1/challenge/tasks/:task/complete` | user | `{date, clientEventId}` → `{awarded, milestoneAwarded, day}`; idempotent; qada within the admin-set window |
| POST | `/v1/challenge/bonuses/:kind/claim` | user | Today only; eligibility computed server-side from the Hijri date |
| GET | `/v1/rewards` | user | Catalogue with `available` for the caller's balance |
| POST | `/v1/rewards/:id/redeem` | user | Debits points, creates a single-use Shopify code; refunds on Shopify failure |

## Admin

Roles: `super_admin` (always allowed), `content_editor`, `religious_reviewer`, `marketing`, `support`.

| Method | Path | Roles |
| --- | --- | --- |
| POST | `/admin/auth/login` | — (email + password + TOTP) |
| GET | `/admin/auth/me` | any |
| GET | `/admin/overview` | any — aggregates only |
| GET | `/admin/users` · `/admin/users/:id` | support, marketing — masked email, no worship history |
| POST | `/admin/users/:id/points` | support — reason required, ≤ 5,000, audited |
| POST | `/admin/users/:id/status` | support — reason required, audited |
| GET | `/admin/content` | content_editor, religious_reviewer |
| POST · PUT | `/admin/content` · `/admin/content/:id` | content_editor — edits return the item to draft |
| POST | `/admin/content/:id/submit` | content_editor |
| POST | `/admin/content/:id/review` | religious_reviewer — not on your own edit |
| GET · PUT | `/admin/content/daily-tasks` | read: editor/reviewer · write: content_editor |
| GET | `/admin/campaigns` · `/admin/campaigns/stats` | marketing |
| POST | `/admin/campaigns/preview` | marketing — reach estimate + copy lint |
| POST | `/admin/campaigns` | marketing — copy lint must pass |
| POST | `/admin/campaigns/:id/cancel` | marketing |
| GET | `/admin/rewards/program` | marketing, support — settings, all six tasks, bonuses, milestones, totals by reason |
| PUT | `/admin/rewards/program` | super_admin — `{settings, tasks[6]}`; active task points must equal `dailyTotal`; qada cap ≤ daily total |
| PUT | `/admin/rewards/milestones` | super_admin — replaces the list of automatic streak bonuses |
| PUT | `/admin/rewards/bonus-rules/:kind` | super_admin |
| GET | `/admin/rewards/grants` | marketing, support |
| POST | `/admin/rewards/grants/preview` · `/admin/rewards/grants` | super_admin — gift points to a segment; one ledger row per user, idempotent |
| GET · POST · PUT | `/admin/rewards` · `/admin/rewards/:id` | read: marketing, support · write: marketing — cost, value, validity, monthly cap, per-user monthly limit, collections |
| GET | `/admin/rewards/redemptions` | marketing, support |
| GET | `/admin/settings/config` | any |
| PATCH | `/admin/settings/config` | super_admin |
| POST | `/admin/settings/hijri/preview` · `/admin/settings/hijri` | religious_reviewer — save blocked if the preview has warnings |
| GET | `/admin/settings/audit` | super_admin |
| GET · POST · PATCH | `/admin/settings/team` · `/admin/settings/team/:id` | super_admin — new admin's TOTP secret is returned once |

## Common error codes

`validation_failed` · `unauthorized` · `invalid_token` · `role_not_allowed` · `account_required` · `account_suspended` · `not_enrolled` · `future_date` · `before_enrollment` · `outside_qada_window` · `already_completed` · `task_inactive` · `insufficient_points` · `reward_cap_reached` · `user_reward_limit_reached` · `shopify_not_configured` · `shopify_rejected` · `bonus_not_eligible` · `bonus_already_claimed` · `cannot_review_own_edit` · `not_pending_review` · `invalid_total` · `duplicate_task` · `use_program_endpoint` · `hijri_invalid_sequence` · `copy_issues`
