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

## 3. Sounds — «أصوات يقين»: the logo, as sound

The mark is an abstracted «ن» (two wings + a gold diamond) and the splash animates it: wings spread, the diamond
settles, a glint crosses. Every notification performs that same gesture, synthesised in
`packages/brand/sounds/generate_sounds.py` (no samples, no licences):

- **«الجناحان» wings**: a warm resonance coloured like the ghunnah of «ن», starting as one point in the centre
  and opening to full stereo width (mono-safe: < 2 dB loss on a single phone speaker).
- **«الماسة» diamond**: a crystal point in the centre that strikes D and lifts a **neutral third** (350 cents),
  an Arabic-mode colour no Western notification uses. Harmonic partials only, never a bell.
- **«اللمعة» glint**: a thin shimmer crossing right → left, the Arabic reading direction.

Owner's halal line: soft tones are fine; no instrument timbres, no bells, no melodies; three tones at most.
Matched loudness (≈ −17 LUFS prayer … −22 LUFS offers, true peak ≤ −1 dBTP), all under 3 s. The adhan is never
synthesised; it stays a licensed recording (`ADHAN_SOUNDS`).

| Sound | Plays for | The gesture |
| --- | --- | --- |
| `yq_prayer` | prayer time when the alert is «تنبيه» | the whole mark: wings open, diamond strikes and lifts, glint |
| `yq_prayer_soon` | N minutes before a prayer | wings begin to open, one diamond strike |
| `yq_azkar` | morning/evening azkar, dhikr routine | three diamond counts moving out from the centre, right to left |
| `yq_quran` | wird, wird missing, Friday al-Kahf, khatma | the ghunnah alone, low and slow, a soft light at the end |
| `yq_hifz` | hifz review due | the lift reversed as the wings fold in: something returning |
| `yq_suhoor` | suhoor | dark, wide wings out of the night, a far glint like the last star |
| `yq_iftar` | iftar | wings open fast, the diamond climbs: home, lift, octave |
| `yq_challenge` | challenge + reward pushes | gold first: glint, then the lift an octave up |
| `yq_offers` | store offer pushes | the diamond alone, muted, wings closed (the quietest sound) |

Wiring: `NotificationSound` (`notification_planner.dart`) maps each `ReminderKind` to a sound. Android has **one
reminders channel per sound** (a channel's sound is fixed once created; ids = resource names; push channels keep
`challenge`/`offers`). iOS plays `<name>.caf` from the app bundle root (files in `ios/Runner/Sounds`, registered in
the Runner target). The API picks channel + sound per campaign kind (`pushSound` in `integrations/fcm.ts`).
`res/raw/keep.xml` stops R8 from stripping the files. In-app UI sounds (`ui_bead`, `ui_bead_round`,
`ui_complete`) are in `assets/sounds/`, ready for the azkar «صوت نقرة خفيف» setting.

To change a sound: edit the generator, run `python3 packages/brand/sounds/generate_sounds.py`, and **bump the
Android channel id** if the app has shipped (installed channels keep their old sound).
