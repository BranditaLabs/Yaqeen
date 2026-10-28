# Notifications

Two systems, deliberately separate.

## 1. Local (on the device) — worship reminders

Adhan per prayer, optional pre-prayer reminder, morning azkar (after Fajr), evening azkar (after Asr), and the
user's **routine**: Quran wird, hifz review (on due days) and a dhikr session, each at the time chosen on the
onboarding routine step (APP_SPEC §5.7·ب) — *after a prayer* (+15 min) or *at a set time* (`SlotTime` in the
planner; resolved per day from that day's prayer times). The routine is device-only and is never sent to the API.

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

## 3. Sounds — «أصوات يقين»

Synthesised in `packages/brand/sounds/generate_sounds.py` (no samples, no licences) to the rules premium system
sounds follow: **short (0.5–1.7 s), clean, at most two elements**, pitched where phone speakers are clear, a pure
decay, a small polished space, levelled by true peak (−1 dBTP prayer … −8 dBTP offers).

- **The voice**: a soft FM tone whose brightness blooms at the touch and melts away in ~80 ms (harmonic 1:1 ratio,
  so never a bell, and not an imitation of any instrument).
- **The signature is the name**: يَ‑قين is two syllables, short then long — a short tone rising a fifth (A → E)
  into a long one. Every sound is the signature, part of it, or turned around.
- Owner's halal line: soft tones are fine; no instrument timbres, no bells, no melodies; three tones at most.
  The adhan is never synthesised; it stays a licensed recording (`ADHAN_SOUNDS`).

| Sound | Plays for | What it is |
| --- | --- | --- |
| `yq_prayer` | prayer time when the alert is «تنبيه» | the full signature «يَ‑قين», short → long |
| `yq_prayer_soon` | N minutes before a prayer | the first syllable alone, held |
| `yq_azkar` | morning/evening azkar, dhikr routine | three light counts on the second note |
| `yq_quran` | wird, wird missing, Friday al-Kahf, khatma | the signature an octave lower, softer, unhurried |
| `yq_hifz` | hifz review due | the signature turned around: coming home |
| `yq_suhoor` | suhoor | both notes at once, softly bloomed, quiet for the night |
| `yq_iftar` | iftar | the signature, then its octave: opening up |
| `yq_challenge` | challenge + reward pushes | the signature an octave up, quick and bright |
| `yq_offers` | store offer pushes | one soft tone (the quietest sound) |

Wiring: `NotificationSound` (`notification_planner.dart`) maps each `ReminderKind` to a sound. Android has **one
reminders channel per sound** (a channel's sound is fixed once created; ids = resource names; push channels keep
`challenge`/`offers`). iOS plays `<name>.caf` from the app bundle root (files in `ios/Runner/Sounds`, registered in
the Runner target). The API picks channel + sound per campaign kind (`pushSound` in `integrations/fcm.ts`).
`res/raw/keep.xml` stops R8 from stripping the files. In-app UI sounds (`ui_bead`, `ui_bead_round`,
`ui_complete`) are in `assets/sounds/`, ready for the azkar «صوت نقرة خفيف» setting.

To change a sound: edit the generator, run `python3 packages/brand/sounds/generate_sounds.py`, and **bump the
Android channel id** if the app has shipped (installed channels keep their old sound).
