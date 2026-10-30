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
| `purchase` | Paid store order that used a Yaqeen reward code — **server-side** from the Shopify webhook, see below | `value`, `currency` |

**Never** an ad event: reading, listening, prayer, azkar, duas, hifz, Qibla, any per-task completion.

## Mapping per platform

| Ours | Firebase / Google Ads | Meta | TikTok |
| --- | --- | --- | --- |
| `sign_up` | `sign_up` | `CompleteRegistration` | `CompleteRegistration` |
| `onboarding_complete` | `tutorial_complete` | `CompleteTutorial` | custom |
| `challenge_join` | custom | `SubmitApplication` or custom | custom |
| `reward_redeem` | custom | custom | custom |
| `purchase` | `purchase` | `Purchase` | `CompletePayment` |

Implement each as an `AdSink` and register it in `adSinksProvider` (app events). `purchase` is
sent by the API, not the app.

## Server-side purchase

When Shopify's `orders/paid` webhook carries a Yaqeen code (`YQ-XXXX-XXXX`), the API reports the
order as a purchase to Meta (Conversions API), GA4 (Measurement Protocol) and TikTok (Events API),
in the background after answering Shopify. Code: `services/api/src/domain/conversions.ts`
(payloads), `src/integrations/conversions.ts` (HTTP), `src/services/conversions.service.ts` (gating).

**Gates** — all must hold, otherwise nothing is sent:

1. admin flag `serverConversions` (الإعدادات › الميزات) is on — **off by default**;
2. `CONVERSIONS_ID_SALT` is set, and the platform's credentials are set (each platform is independent);
3. the order is attributed to the owner of its earliest-issued Yaqeen code, and that user is a signed-in
   (not guest), active account whose **current** `ads_measurement` consent is granted when the
   webhook arrives (withdrawn or never given → nothing);
4. the order has a numeric id and a valid total.

**Payload — the complete list of fields** (a test fails if any other key appears):

| | Meta CAPI | GA4 MP | TikTok Events API |
| --- | --- | --- | --- |
| Event | `Purchase` | `purchase` | `CompletePayment` |
| Time | `event_time` (order `processed_at`, else now) | `timestamp_micros` | `event_time` |
| Dedupe id = Shopify order id | `event_id` | `transaction_id` | `event_id` |
| Value + currency | `custom_data.value`, `.currency` | `params.value`, `.currency` | `properties.value`, `.currency` |
| Pseudonymous id | `user_data.external_id` | `client_id` | `user.external_id` |
| Fixed | `action_source: website`, `event_source_url` = `STORE_URL` | `consent: {ad_user_data: GRANTED, ad_personalization: DENIED}` | `event_source: web`, `event_source_id` = pixel, `page.url` = `STORE_URL` |

- **Value** is the order's `total_price` (what the customer paid after the Yaqeen discount, incl.
  shipping/tax) in the order's `currency` (EGP) — the revenue the campaign brought, which is what ROAS
  optimisation needs. Not the discount amount.
- **Pseudonymous id** = SHA-256(`CONVERSIONS_ID_SALT` : platform : user id), hex. Secret salt, so it
  can't be recomputed from a user id; different per platform, so platforms can't join on it; never
  the raw id.
- **Never sent**: email, phone, name, IP, user agent, address, click ids (`fbp`/`fbc`/`ttclid`),
  line items, the discount code, and anything about worship. The Shopify order carries most of these;
  only the fields above are read from it.
- **Once per order and platform**: `conversion_sends(order_id, platform, status, attempts, sent_at)`
  — no user id, no amount. A replayed webhook skips what was sent and retries only a `failed` send
  (at most 3 attempts). Each HTTP send has a 5 s timeout and one retry on network error / 429 / 5xx.
- Failures never reach Shopify (it always gets its 200): they are counted in
  `yaqeen_conversions_total{platform,outcome}` and reported to Sentry (scrubbed, no payload).
- Verify a setup with `META_TEST_EVENT_CODE` / `TIKTOK_TEST_EVENT_CODE` (Test events tabs) or GA4
  DebugView; remove the test codes afterwards.

**Double counting**: if the store also runs a platform's own Shopify app/pixel (Facebook & Instagram,
Google & YouTube, TikTok), that app already reports every store purchase, including these. Either keep
only one source per platform, or make sure both use the same order id as the event id so the
platform dedupes (an owner decision before turning the flag on).

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
