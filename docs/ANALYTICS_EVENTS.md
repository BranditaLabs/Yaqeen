# Analytics & ad events

## Ad platform events (closed list)

Sent to Google Ads (via Firebase), Meta and TikTok **only** with `ads_measurement` consent. Source of truth: `packages/contracts/src/events.ts`; Dart mirror `AdEvent` (a unit test checks they match).

| Event | When | Params |
| --- | --- | --- |
| `first_open` | First launch after install | — |
| `sign_up` | Account created (not guest) | — |
| `onboarding_complete` | Finished onboarding | — |
| `challenge_join` | Enrolled in the 365-day challenge | — |
| `streak_7` | 7-day streak reached | `day` |
| `streak_30` | 30-day streak reached | `day` |
| `reward_redeem` | Discount code issued | `reward_id` |
| `store_click` | Opened the store from the app | — |
| `purchase` | Order completed (from Shopify webhook → server-side, phase 2) | `value`, `currency` |

**Never** an ad event: reading, listening, prayer, azkar, duas, hifz, Qibla, any per-task completion.

## Mapping per platform

| Ours | Firebase / Google Ads | Meta | TikTok |
| --- | --- | --- | --- |
| `sign_up` | `sign_up` | `CompleteRegistration` | `CompleteRegistration` |
| `onboarding_complete` | `tutorial_complete` | `CompleteTutorial` | custom |
| `challenge_join` | custom | `SubmitApplication` or custom | custom |
| `reward_redeem` | custom | custom | custom |
| `purchase` | `purchase` | `Purchase` | `CompletePayment` |

Implement each as an `AdSink` and register it in `adSinksProvider`.

## Product analytics («تحسين التطبيق»)

Opt-in consent bucket `product_analytics` (off by default; onboarding consent step + Privacy screen).
Source of truth: `PRODUCT_EVENTS` in `packages/contracts/src/events.ts`; Dart mirror `ProductEvent`
(a test compares them). Every prop value is from a closed list.

| Event | Props | Where |
| --- | --- | --- |
| `app_open` | — | after the first frame |
| `onboarding_step` | `step`: welcome · language · prayer · consent · goal · routine · download | router (once per session) |
| `onboarding_complete` | — | last onboarding step |
| `sign_in` | `provider`: google · apple · guest | session controller |
| `tab_view` | `tab`: home · challenge · profile | router — **Quran and Prayer tabs are never tracked** |
| `card_published` / `card_shared` | `channel`: link · qr | «بطاقة يقين» |
| `medal_activated` | `via`: code · link | «ميدالياتي» |
| `redeem_view` / `reward_redeem` | — | rewards |
| `store_click` | `from`: profile · redeem · card · medal | store buttons |
| `notification_open` | `kind`: reminder · campaign · challenge | (reserved) |
| `settings_change` | `setting`: language · reminders · privacy · routine | settings |
| `update_prompt` | `action`: shown · update · later | (reserved) |

**Never** a product event: anything about reading, listening, prayer, azkar, duas, hifz, Qibla or tasks.

Pipeline: app queue (≤ 200, batches of 50, flushed every minute and on pause) → `POST /v1/me/events`
→ consent re-checked server-side → `product_events` (random install id, **no account id**, 180 days)
→ admin «التحليلات» (active installs, events, onboarding funnel, weekly retention, platforms,
versions; counts < 20 withheld) and, when `POSTHOG_KEY` is set, PostHog EU (no IP, no GeoIP, no
person profiles). Withdrawing consent deletes the queue and the install id on the device.

The admin overview keeps its server-side aggregates (DAU/MAU from `users.last_seen_at`, habit
percentages across participants) independently of this consent.

## MMP (open decision)

An MMP (AppsFlyer/Adjust) would de-duplicate installs across Google/Meta/TikTok, but is another data processor and cross-border transfer. Decide before launch (ROADMAP).
