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

## Product analytics (internal)

The admin overview uses server-side aggregates (DAU/MAU from `users.last_seen_at`, habit percentages across participants). No third-party product analytics SDK is required for v1. If one is added, it falls under the same consent bucket and the same closed-list rule for worship data.

## MMP (open decision)

An MMP (AppsFlyer/Adjust) would de-duplicate installs across Google/Meta/TikTok, but is another data processor and cross-border transfer. Decide before launch (ROADMAP).
