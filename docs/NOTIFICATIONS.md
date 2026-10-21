# Notifications

Two systems, deliberately separate.

## 1. Local (on the device) — worship reminders

Adhan per prayer, optional pre-prayer reminder, morning azkar (after Fajr), evening azkar (after Asr), daily wird.

- Planned by `NotificationPlanner.plan()` (`apps/mobile/lib/core/notifications/notification_planner.dart`), pure and unit-tested.
- Prayer times computed on-device from location (no server round-trip, works offline).
- **iOS keeps at most 64 pending notifications** → we schedule the next 60 and re-plan on every app open and background refresh (`replanBefore`).
- **iOS custom sounds ≤ 30 s** → bundle adhan clips as `.caf` ≤ 30 s; full adhan plays only in-app.
- **Android 12+ exact alarms** need `SCHEDULE_EXACT_ALARM` (or `USE_EXACT_ALARM` for alarm-clock-style apps); fall back to inexact if refused.
- **Android 13+** needs the `POST_NOTIFICATIONS` runtime permission. Ask after onboarding explains why.
- Stable ids per (date, kind, prayer), so re-planning replaces instead of duplicating.

## 2. Remote (FCM) — campaigns

Challenge nudges, reward reminders, store offers. Created in the admin (Campaigns), sent by the dispatcher job every 10 minutes.

Guardrails (`services/api/src/domain/guardrails.ts`, unit-tested), evaluated **per user in their own timezone**:

| Rule | Value |
| --- | --- |
| Consent | `offers` → `store_offers`; `rewards`/`challenge` → `challenge_rewards` |
| Quiet hours | 22:00 – 07:00 |
| Around prayer | no sends from 20 min before to 30 min after each prayer |
| Jumu'ah | Friday 11:30 – 13:30 |
| Daily cap | 1 × offers, 1 × rewards, 2 × challenge per user per 24 h |
| Copy lint | title ≤ 40 chars, body ≤ 110, no "آخر فرصة" urgency, no "!!" |

Schedules: `now` (one pass, blocked users skipped), `smart` (blocked-by-time users retried each run until 22:00), `scheduled` (at a time).

Deep links: `yaqeen://<target>` → `routeForDeepLink()` in the app.

Channels: Android `yaqeen_updates` (campaigns, normal priority) must be separate from the adhan channel so users can mute marketing without muting adhan.
