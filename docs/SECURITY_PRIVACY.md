# Security & privacy

> Not legal advice. Have an Egyptian data-protection lawyer review this before launch.

## Egypt PDPL (Law 151/2020)

Enforcement is expected from about **1 November 2026** — confirm the current status and deadlines with counsel. What the codebase already does, and what still needs action:

| Requirement | In code | Still to do |
| --- | --- | --- |
| Explicit, specific, revocable consent, in Arabic | 4 separate buckets; every change stored in `consent_events` with source + policy version | Final Arabic consent copy reviewed by counsel |
| Right of access | `GET /v1/me/export` | Human-readable export format (optional) |
| Right of erasure | `DELETE /v1/me` → `deletion_requested` (sessions end, card unpublished, tags off) | `job:purge` anonymises after 30 days: identities, sessions, devices, consents, worship records, activity and the public card (handle freed) are deleted, tags unlinked and kept off; the ledger stays on an anonymous tombstone |
| Data minimisation | Prayer times and location computed on-device; Hifz progress on-device only | — |
| Licence / registration with the Personal Data Protection Centre | — | Apply for the controller/processor licence |
| Cross-border transfer | — | Choose hosting region; get transfer authorisation if data leaves Egypt (Firebase, Shopify and ad SDKs are all transfers) |
| DPO | — | Appoint a data protection officer |
| Breach notification (72 h) | Audit log + structured logs | Incident runbook |

## Sensitive data: worship activity

Task completions reveal religious practice. Rules:

1. **Never sent to ad platforms.** The only events ad SDKs can receive are the closed list in `packages/contracts/src/events.ts` (mirrored in `apps/mobile/lib/core/analytics/analytics.dart`), and only with `ads_measurement` consent. Adding an event needs a privacy review.
2. **Admins see aggregates only.** `/admin/overview` returns percentages. The user detail view shows the points ledger and redemptions, not which prayers or azkar a person did.
3. **Guests earn no points**, so no worship data is stored for anonymous users.
4. **Public cards (بطاقة يقين) never show worship.** A card is unpublished until the user publishes it and shows only the fields they switch on: level (from lifetime points), streak length, challenge day, streak-milestone badges, member-since, a dated journey timeline (joined, challenge start/day 30–365, levels reached, badges). Never prayers, azkar, pages or tasks. Guests can't publish; an erasure request or a suspension hides it at once; support can hide an abusive card (audited). The page is `noindex`, has no scripts or trackers, and keeps only an open counter. Physical tags (medals/cards) carry a random permanent code, not the user's identity: an activated code activates for one account only, a lost one is switched off by the owner (never re-assigned to a finder), an erasure request switches off all of the user's tags, and each keeps only a scan counter. Codes can't be probed — unknown, taken and switched-off all answer `not_found`, and activation is rate-limited. Admin moderation of cards (hide, restore, release a handle) and every batch / tag action is audited with a reason; the programme's numbers are daily counters only (`card_daily_stats`) — no visitor, user or handle is recorded.

5. **Product analytics («تحسين التطبيق») never carries worship.** Opt-in bucket `product_analytics` (off by default). Closed list `PRODUCT_EVENTS` (contracts) with closed values: onboarding steps, the three non-worship tab roots, card/medal/rewards/store actions, settings changes. Worship tabs and screens are never tracked. Events go to our API only, keyed by a random per-install id (rotated when consent is withdrawn) and stored **without** the account id; 180-day retention; admins see aggregates with counts under 20 withheld. Server-side forwarding to PostHog EU sends the same events with no IP, no GeoIP and no person profiles.
6. **Server-side purchase conversions carry no personal or worship data.** When a Yaqeen reward code is used on a paid store order, the API may send a `purchase` to Meta / GA4 / TikTok — only with the admin flag `serverConversions` on, and only for a signed-in buyer whose **current** `ads_measurement` consent is granted (guests and withdrawn consent: nothing). The payload is the event name, time, Shopify order id, order total + currency and a salted, per-platform SHA-256 of the user id — never email, phone, name, IP, user agent, address, items, the code, or anything about worship. `conversion_sends` keeps only order id + platform + status for dedupe. Details: docs/ANALYTICS_EVENTS.md › Server-side purchase.
7. **Error reports carry no personal or worship data.** Sentry (app, API, jobs, admin): no user, cookies, request bodies, query strings or private headers; URLs reduced to route templates; app reports drop navigation, tap and HTTP breadcrumbs and never attach screenshots or view hierarchies. Metrics are labelled by route template and status only.

### Processors

| Processor | Purpose | Data | Region |
| --- | --- | --- | --- |
| Sentry | Errors and crashes | stack traces, device/OS, app version — scrubbed as above | choose the EU (Frankfurt) data region |
| PostHog | Product analytics (consented) | closed-list events keyed by a random install id | EU cloud (`eu.i.posthog.com`) |
| Meta (Conversions API) | Ad measurement — store purchases with a Yaqeen code (`ads_measurement` consent) | event, time, order id, total + currency, salted hashed id | US / global (cross-border transfer) |
| Google (GA4 Measurement Protocol) | same | same; `ad_personalization` denied | US / global (cross-border transfer) |
| TikTok (Events API) | same | same | Singapore / US / global (cross-border transfer) |

All are listed in the privacy policy and can be switched off by removing their DSN / key (no app release needed for PostHog or the conversions: the app talks only to our API; the conversions also stop at once with the `serverConversions` flag).

## Ads & tracking

- iOS: show the ATT prompt only after the user turned on `ads_measurement` in our own consent screen. Without ATT, SDKs run in limited mode.
- Google Ads via Firebase Analytics, Meta App Events, TikTok Business SDK: initialise with tracking **off**, enable in `Analytics.onConsentChanged(true)`.
- Event params are allowlisted (`value`, `currency`, `reward_id`, `day`).
- The only server-to-ad-platform flow is the consented `purchase` conversion above; it has no API a client can call and sends only `AD_EVENTS.purchase`.

## Application security

- App tokens and admin tokens use different secrets **and** audiences; an app token can't reach `/admin`.
- Admin: scrypt passwords, mandatory TOTP, 8-hour sessions in httpOnly `SameSite=Strict` cookies, never readable by browser JS. Put the dashboard behind SSO/VPN or an IP allowlist too.
- TOTP secrets are sealed at rest with AES-256-GCM under `ADMIN_SECRETS_KEY` (32 bytes from the secret manager / KMS; required in production). Secrets from before the key are sealed on the admin's next good login. Losing the key means every admin re-enrols 2FA — back it up with the other production secrets.
- Every admin write is audited in the same DB transaction as the change.
- Point balances can't race: per-user advisory locks around awards and redemptions; unique `(user, ref_key)` on the ledger.
- Logs redact `authorization`, `x-admin-session`, `idToken`, `password`, `totp`.
- Helmet headers, CORS allowlist, global and per-route rate limits.
