# Security & privacy

> Not legal advice. Have an Egyptian data-protection lawyer review this before launch.

## Egypt PDPL (Law 151/2020)

Enforcement is expected from about **1 November 2026** — confirm the current status and deadlines with counsel. What the codebase already does, and what still needs action:

| Requirement | In code | Still to do |
| --- | --- | --- |
| Explicit, specific, revocable consent, in Arabic | Separate buckets (reminders, challenge, offers, ads, product analytics, cloud backup); every change stored in `consent_events` with source + policy version | Final Arabic consent copy reviewed by counsel |
| Right of access | `GET /v1/me/export` | Human-readable export format (optional) |
| Right of erasure | `DELETE /v1/me` → `deletion_requested` (sessions end, card unpublished, tags off) | `job:purge` anonymises after 30 days: identities, sessions, devices, consents, worship records, activity, the cloud backup and the public card (handle freed) are deleted, tags unlinked and kept off; the ledger stays on an anonymous tombstone |
| Data minimisation | Prayer times and location computed on-device; reading, notes, khatma, hifz, azkar counts, routine and the Ramadan log are device first — copied to the server only with the opt-in `cloud_backup` (rule 8) | — |
| Licence / registration with the Personal Data Protection Centre | — | Apply for the controller/processor licence |
| Cross-border transfer | — | Choose hosting region; get transfer authorisation if data leaves Egypt (Firebase, Shopify and ad SDKs are all transfers) |
| DPO | — | Appoint a data protection officer |
| Breach notification (72 h) | Audit log + structured logs | Incident runbook |

## Sensitive data: worship activity

Task completions reveal religious practice. Rules:

1. **Never sent to ad platforms.** The only events ad SDKs can receive are the closed list in `packages/contracts/src/events.ts` (mirrored in `apps/mobile/lib/core/analytics/analytics.dart`), and only with `ads_measurement` consent. Adding an event needs a privacy review.
2. **Admins see aggregates only.** `/admin/overview` returns percentages. The user detail view shows the points ledger and redemptions, not which prayers or azkar a person did.
3. **Guests earn no points**, so no worship data is stored for anonymous users.
4. **Public cards (بطاقة يقين) never show worship.** A card is unpublished until the user publishes it and shows only the fields they switch on: level (from lifetime points), streak length, challenge day, streak-milestone badges, member-since, a dated journey timeline (joined, challenge start/day 30–365, levels reached, badges). Never prayers, azkar, pages or tasks. Guests can't publish; an erasure request or a suspension hides it at once; support can hide an abusive card (audited). The page is `noindex`, has no scripts or trackers, and keeps only an open counter. Physical tags (medals/cards) carry a random permanent code, not the user's identity: an activated code activates for one account only, a lost one is switched off by the owner (never re-assigned to a finder), an erasure request switches off all of the user's tags, and each keeps only a scan counter. Codes can't be probed — unknown, taken and switched-off all answer `not_found`, and activation is rate-limited. **NFC:** the app reads a chip only when the user taps «قرّب الميدالية من الهاتف» (never at start-up) and accepts only our own link — https (or exactly the configured site), path exactly `/t/<code>`, no query, fragment or user info; anything else is refused and nothing activates without the user's tap on «تفعيل». **Staff encoding** gives the phone no admin credentials: marketing opens an encoding session for one batch in admin (audited), whose token is a scoped capability — 32 random bytes, shown once as a QR/link, stored only as SHA-256, valid 2 hours, revocable at once (audited), useless once the batch is voided; it can only list that batch's working codes and mark them written. Unknown, expired and revoked tokens get the same 404, the endpoints are rate-limited per IP, the token is redacted from request logs, and the app keeps it only while the encoding screen is open. Because the session shows a batch's unclaimed codes, open it only on staff phones and revoke it when done. Admin moderation of cards (hide, restore, release a handle) and every batch / tag action is audited with a reason; the programme's numbers are daily counters only (`card_daily_stats`) — no visitor, user or handle is recorded.

5. **Product analytics («تحسين التطبيق») never carries worship.** Opt-in bucket `product_analytics` (off by default). Closed list `PRODUCT_EVENTS` (contracts) with closed values: onboarding steps, the three non-worship tab roots, card/medal/rewards/store actions, settings changes. Worship tabs and screens are never tracked. Events go to our API only, keyed by a random per-install id (rotated when consent is withdrawn) and stored **without** the account id; 180-day retention; admins see aggregates with counts under 20 withheld. Server-side forwarding to PostHog EU sends the same events with no IP, no GeoIP and no person profiles.
6. **Server-side purchase conversions carry no personal or worship data.** When a Yaqeen reward code is used on a paid store order, the API may send a `purchase` to Meta / GA4 / TikTok — only with the admin flag `serverConversions` on, and only for a signed-in buyer whose **current** `ads_measurement` consent is granted (guests and withdrawn consent: nothing). The payload is the event name, time, Shopify order id, order total + currency and a salted, per-platform SHA-256 of the user id — never email, phone, name, IP, user agent, address, items, the code, or anything about worship. `conversion_sends` keeps only order id + platform + status for dedupe. Details: docs/ANALYTICS_EVENTS.md › Server-side purchase.
8. **Cloud backup («نسخ احتياطي سحابي») is opt-in, encrypted, and only for the user.** Personal progress is device first. It reaches the server only when a **signed-in** (Google/Apple, never guest) user turns on the `cloud_backup` consent in Privacy — off by default, never asked in onboarding, every change recorded in `consent_events`. Then the app keeps one document per kind (closed list `BACKUP_KINDS`: Quran reading — last page, bookmarks, today's wird, reading stats; notes and highlights; khatma + history; hifz plan/state; today's azkar counts + favourite duas; listen — chosen reciter, position, today's listening time; routine slots; Ramadan log; Home tasbeeh count) in `user_backups`. Never in it: downloaded audio or packs, caches, consents, push tokens, location or the city. Rules:
   - **Encrypted at rest**: each document is sealed with AES-256-GCM under `BACKUP_SECRETS_KEY` (32 bytes, a different key from `ADMIN_SECRETS_KEY`; required in production) before it reaches Postgres. Capped at 256 KB per kind.
   - **Only the user reads it**: `GET /v1/me/backup[/:kind]` and the user's own export (`GET /v1/me/export` includes it, opened). No admin route, admin export, aggregate, product-analytics event, ad sink or server-side conversion reads `user_backups` (a test checks the admin routes and the analytics/conversion code).
   - **Deleted** in the same transaction when the consent is withdrawn (the switch asks first: "this deletes the copy on our servers"), and by `job:purge` with the rest of an erased account. Signing out keeps the server copy with the account but turns the backup off on that phone. The phone's own data is never deleted by the backup.
   - **Merges, never overwrites blindly**: per-kind versions with optimistic concurrency (a stale write gets 409 `backup_conflict` and the app merges — union for bookmarks/notes/highlights/favourites/history, max for per-day counters, last-writer-wins for scalar state).
   - Losing `BACKUP_SECRETS_KEY` makes every stored backup unreadable (phones keep their data); back it up with the other production secrets, never rotate it without a re-seal migration.
9. **Error reports carry no personal or worship data.** Sentry (app, API, jobs, admin): no user, cookies, request bodies, query strings or private headers; URLs reduced to route templates; app reports drop navigation, tap and HTTP breadcrumbs and never attach screenshots or view hierarchies. Metrics are labelled by route template and status only.

### Processors

| Processor | Purpose | Data | Region |
| --- | --- | --- | --- |
| Sentry | Errors and crashes | stack traces, device/OS, app version — scrubbed as above | choose the EU (Frankfurt) data region |
| PostHog | Product analytics (consented) | closed-list events keyed by a random install id | EU cloud (`eu.i.posthog.com`) |
| Google (Firebase Analytics → Google Ads), in the app | Ad measurement (`ads_measurement`) | the ad events above, advertising id, device/app metadata | Google (US); cross-border transfer |
| Meta App Events, in the app | Ad measurement (`ads_measurement`) | the ad events above, app launches, advertising id | Meta (US/IE); cross-border transfer |
| Meta (Conversions API), from our server | Ad measurement — store purchases with a Yaqeen code (`ads_measurement` consent) | event, time, order id, total + currency, salted hashed id | US / global (cross-border transfer) |
| Google (GA4 Measurement Protocol), from our server | same | same; `ad_personalization` denied | US / global (cross-border transfer) |
| TikTok (Events API), from our server only — no TikTok SDK in the app | same | same | Singapore / US / global (cross-border transfer) |

All are listed in the privacy policy. Sentry and PostHog can be switched off by removing their DSN / key and the server-side conversions with the `serverConversions` flag (no app release needed: the app talks only to our API for those); an ad SDK is removed from a build by leaving out its build values.

## Ads & tracking

Code: `apps/mobile/lib/core/analytics/analytics.dart` (the gate) and `lib/core/analytics/sinks/` (one sink per SDK, each behind a tiny interface so tests never touch the SDK).

- **Server side.** The only server-to-ad-platform flow is the consented `purchase` conversion above (`services/api/src/services/conversions.service.ts`); no API lets a client send events to an ad platform.
- **The gate.** Sinks receive only `AdEvent` values (the closed list) with allowlisted params (`value`, `currency`, `reward_id`, `day`) plus an `att` control flag that is never forwarded. Nothing reaches a sink without `ads_measurement`. Every SDK call is time-boxed and its errors swallowed, so an SDK can't block or break a screen.
- **Registered only with build values.** An SDK whose ids aren't compiled in (`FIREBASE_ANALYTICS`, `FACEBOOK_APP_ID` + `FACEBOOK_CLIENT_TOKEN`) is not registered: its plugin is never called and the SDK never starts. Release builds without them ship no active ad SDK.
- **Off by default, natively.** Collection, automatic events and advertising ids are switched off in `AndroidManifest.xml` and `Info.plist`, so nothing is collected before the app decides.
- **Start-up.** Nothing ad-related runs before the first frame. After it, `Analytics.start()` aligns the SDKs with the stored consent — and does nothing at all until the consent screen has been answered.
- **iOS ATT.** The prompt appears only after the user turned on `ads_measurement` in our own consent screen (onboarding or Privacy). Without "Allow", no IDFA: Meta's advertiser-id collection stays off and Firebase reads no IDFA.
- **Withdrawal** (Privacy screen) turns every SDK off at once: Firebase collection off, consent mode denied, local analytics data and app-instance id reset; Meta advertiser id off and user data cleared; queued install events deleted.

| SDK | Package | Before consent | With `ads_measurement` it receives | Never |
| --- | --- | --- | --- | --- |
| Google Ads via Firebase Analytics (project `yaqeen-eg`) | `firebase_analytics` 12.6.1 (Firebase iOS SDK 12.19.3) | `firebase_analytics_collection_enabled=false` / `FIREBASE_ANALYTICS_COLLECTION_ENABLED=NO`; consent mode (analytics storage, ad storage, ad user data, ad personalisation) denied; automatic screen reporting off; Android ID (SSAID) and IDFV collection off | Ad events (`sign_up`, `tutorial_complete`, `purchase` with value + currency, and our custom names); consent mode granted for analytics storage, ad storage and ad user data; Firebase's own automatic events (`first_open`, `session_start`, `user_engagement`, `app_update`, `os_update`) and device/app metadata; the advertising id (AAID; IDFA only with ATT) | User id, user properties, screen views, ad personalisation, worship data |
| Meta App Events | `facebook_app_events` 0.31.0 (Facebook SDK 18.x) | `AutoInitEnabled=false` (iOS: SDK not configured at all; Android: the SDK's init provider still reads its config and creates a local anonymous id at process start, but the SDK refuses Graph API requests until it is initialised — and with no app id compiled in it doesn't start at all), `AutoLogAppEventsEnabled=false`, `AdvertiserIDCollectionEnabled=false` | App launch (`activateApp`, which Meta uses for install attribution) once per session, ad events (`fb_mobile_complete_registration`, `fb_mobile_tutorial_completion`, `fb_mobile_purchase` with value + currency, custom names); limited event and data usage on; advertiser id only with consent (and ATT on iOS) | User id, user data (email, phone…), automatic events, worship data |
| TikTok | — (no SDK in the app) | — | Nothing from the app. Purchase conversions go server-side through the TikTok Events API | — |

The `TikTokAdSink` class exists for a future official plugin but is not registered. The only community Flutter wrapper (`tiktok_events_sdk`) pulls its Android SDK from JitPack, ships two diverging iOS source trees, and by default shows its own ATT prompt and auto-tracks installs, launches and retention.

## Application security

- App tokens and admin tokens use different secrets **and** audiences; an app token can't reach `/admin`.
- Admin: scrypt passwords, mandatory TOTP, 8-hour sessions in httpOnly `SameSite=Strict` cookies, never readable by browser JS. Put the dashboard behind SSO/VPN or an IP allowlist too.
- TOTP secrets are sealed at rest with AES-256-GCM under `ADMIN_SECRETS_KEY` (32 bytes from the secret manager / KMS; required in production). Secrets from before the key are sealed on the admin's next good login. Losing the key means every admin re-enrols 2FA — back it up with the other production secrets.
- Users' opt-in cloud backups are sealed with AES-256-GCM under `BACKUP_SECRETS_KEY` (separate from the admin key; required in production) — see rule 8.
- Every admin write is audited in the same DB transaction as the change.
- Point balances can't race: per-user advisory locks around awards and redemptions; unique `(user, ref_key)` on the ledger.
- Logs redact `authorization`, `x-admin-session`, `idToken`, `password`, `totp`.
- Helmet headers, CORS allowlist, global and per-route rate limits.
