# Store kit — App Store & Google Play

Everything the two consoles ask for, written from what the **current build** does. Re-check the
privacy answers whenever a data flow changes (Firebase push, ad SDKs, a new consent) — the
answers below say which ones change.

> Not legal advice: the privacy policy and terms (served at `/privacy` and `/terms`) still carry
> bracketed facts only the owner can give, and counsel reviews them before launch.

## URLs (all on the cards host, `PUBLIC_PROFILE_BASE_URL`, e.g. the vanity domain)

| Console field | URL |
| --- | --- |
| Privacy policy (both stores, required) | `<site>/privacy` (Arabic; `?lang=en` for English) |
| Terms / EULA | `<site>/terms` |
| Support URL (App Store, required) | `<site>/support` |
| Marketing URL (App Store) | `<site>/` |
| Account deletion URL (Google Play, required) | `<site>/delete-account` |
| Website (Play) | `<site>/` |

Set `SUPPORT_EMAIL` on the API first — until then the pages show `[support email]`.

## Listing copy

### Arabic (primary)

- **Name (≤ 30):** يقين — مصحف وصلاة وأذكار
- **App Store subtitle (≤ 30):** طمأنينة يومية تبدأ من هنا
- **Play short description (≤ 80):** مصحف دون اتصال، مواقيت وأذان، أذكار، رمضان، ورحلة يومية تُكافأ عليها.
- **App Store promotional text (≤ 170):** رفيقك في يومك: صلاتك في وقتها، وِردك من المصحف، أذكارك، ورحلة 365 يوماً تُكافأ عليها بنقاط تستبدلها في متجر يقين — وخصوصيتك محفوظة.
- **Description:**

  يقين رفيقك اليومي للطمأنينة.

  • المصحف كاملاً دون اتصال، مع وِرد يومي وعلامات وخطة حفظ ومراجعة، واستماع لقرّاء مرخّصين.
  • مواقيت الصلاة لمدينتك تُحسب على هاتفك، مع تنبيه الأذان والقبلة — دون إنترنت.
  • أذكار الصباح والمساء والأدعية بمصادرها، يراجعها مختصّ قبل النشر.
  • رحلة 365 يوماً: مهام يومية بسيطة تجمع بها نقاطاً تستبدلها بهدايا وخصومات في متجر يقين.
  • رمضان: إمساكية لمدينتك، عدّ تنازلي للإفطار والسحور، وختمة وتراويح.
  • ودجت للشاشة الرئيسية: الصلاة القادمة مع عدّ تنازلي، والتاريخ الهجري، ووِرد اليوم.
  • بطاقة يقين العامة وميداليات يقين: شارك رحلتك دون أي تفاصيل عبادة.

  عبادتك بينك وبين ربك: مواقيتك وموقعك وقراءتك وحفظك تبقى على جهازك، ولا نرسل أي نشاط عبادة إلى منصّات الإعلان أبداً. كل موافقة منفصلة ويمكنك إلغاؤها في أي وقت.

- **App Store keywords (≤ 100, comma-separated, no spaces):** قرآن,مصحف,صلاة,أذان,قبلة,أذكار,أدعية,رمضان,إمساكية,حفظ,ورد,تسبيح

### English

- **Name:** Yaqeen — Quran, Prayer & Azkar
- **Subtitle:** Daily calm starts here
- **Play short description:** The mushaf offline, prayer times & adhan, azkar, Ramadan, and a rewarding daily journey.
- **Promotional text:** A companion for your day: prayer on time, your Quran wird, your azkar and a 365-day journey that earns points for the Yaqeen store — with your privacy kept.
- **Description:** the Arabic bullets, in the English of `<site>/?lang=en`.
- **Keywords:** quran,mushaf,prayer,adhan,qibla,azkar,dua,ramadan,imsakiyya,hifz,wird,tasbeeh

### Categories & rating

- App Store: primary **Lifestyle**, secondary **Reference**. Age rating: 4+ (no objectionable content; the public card is user-generated → answer "yes" to *user-generated content* only if cards become visible inside the app — today they open in the browser).
- Google Play: **Lifestyle**. IARC questionnaire: no violence, no gambling (points have no cash value and can't be bought), user interaction = no (cards are external web pages), shares location = **no** (computed on the device; only the city name you pick is synced).

### Screenshots (6.7″ / 6.5″ iPhone, Play phone; Arabic set first, then English)

1. Home — the living sky with the next prayer and the day timeline
2. Quran reader (paper theme)
3. Prayer times + Qibla orb
4. Azkar counter
5. 365 challenge + rewards
6. Ramadan imsakiyya (when the season is on)
7. Home-screen widget on a home screen
8. Yaqeen card (public page)

Golden screenshots in `apps/mobile/test/goldens/` are the reference framing.

### Review notes (App Store "App Review Information")

- Guest mode works without signing in (tap «المتابعة كضيف»). Sign in with Apple is offered next to Google.
- Points have no cash value and are never sold; rewards are single-use discount codes for our own Shopify store.
- Features behind admin switches (recitation check, Ramadan, bonuses) may be off during review.
- Worship data stays on the device or, for the challenge, on our server only to award points; it is never sent to ad platforms.

## App Store — App Privacy ("nutrition label")

Answer for the build being submitted. The ad SDKs (Firebase Analytics for Google Ads, Meta App Events) are in the code but **active only in a build made with their values** (`FIREBASE_ANALYTICS`, `FACEBOOK_APP_ID` + `FACEBOOK_CLIENT_TOKEN` — docs/RELEASE_MOBILE.md). Without them Firebase is used **only for push** (Cloud Messaging, project `yaqeen-eg`) and this table is complete:

| Data type | Collected? | Linked to the user | Tracking | Purposes |
| --- | --- | --- | --- | --- |
| Contact info → Name, Email address | Yes (Google / Apple sign-in) | Yes | No | App functionality |
| Identifiers → User ID | Yes | Yes | No | App functionality |
| Sensitive info (religious practice: challenge task completions) | Yes | Yes | No | App functionality |
| Purchases → Purchase history (reward redemptions) | Yes | Yes | No | App functionality |
| Usage data → Product interaction | Yes, only with «تحسين التطبيق» | **No** (random install id) | No | Analytics |
| Identifiers → Device ID (push token) | Yes | Yes | No | App functionality |
| Diagnostics → Crash data, Performance data | Yes (Sentry, scrubbed) | No | No | App functionality |
| Location | **No** (computed on device; the city name picked is a setting) | — | — | — |
| User content | Yes, only if the user publishes a card (name, avatar, chosen fields) | Yes | No | App functionality |

**Build with ad SDK values** (Google and/or Meta, only with `ads_measurement`) — add:

| Data type | Collected? | Linked to the user | Tracking | Purposes |
| --- | --- | --- | --- | --- |
| Identifiers → Device ID (IDFA, only after ATT "Allow") | Yes | No | **Yes** | Third-party advertising |
| Usage data → Advertising data (ad events: sign-up, onboarding done, challenge join, streak 7/30, reward redeemed, store opened; app launches) | Yes | No | **Yes** | Third-party advertising, Analytics |
| Purchases → Purchase history (purchase value + currency) | Yes (server-side conversions) | No | **Yes** | Third-party advertising |

The app asks for ATT only after the in-app consent (already built), declares `NSUserTrackingUsageDescription`, and never sends a user id, contact info or worship data to an ad SDK. Both SDKs ship their own privacy manifests (tracking domains included).

## Google Play — Data safety

- Data encrypted in transit: **Yes** (HTTPS only).
- Users can request deletion: **Yes** — in the app (Profile → Delete account) and at `<site>/delete-account`.
- Optional collection: product interaction (consent), the public card (the user publishes it), the challenge (opt-in). Crash logs are required.

| Category → type | Collected | Shared | Optional | Purpose |
| --- | --- | --- | --- | --- |
| Personal info → Name, Email | Yes | No | Yes (guest mode) | Account management, App functionality |
| Personal info → User IDs | Yes | No | Yes (guest mode) | Account management |
| Personal info → Religious or political beliefs (challenge task completions) | Yes | No | Yes (challenge is opt-in) | App functionality |
| Financial info → Purchase history (redemptions) | Yes | No | Yes | App functionality |
| App activity → App interactions | Yes | No | Yes (consent) | Analytics |
| App info & performance → Crash logs, Diagnostics | Yes | No | No | App functionality, Analytics |
| Device or other IDs → push token (Firebase Cloud Messaging) | Yes | No | No | App functionality |
| Location | **No** | — | — | — |
| Device or other IDs → advertising ID | **Yes** in a build with ad SDK values (Google/Meta), else No | **Yes** (Google, Meta) | Yes (`ads_measurement`, off by default) | Advertising or marketing, Analytics |
| App activity → Other actions (the closed ad-event list; app launches) | Yes in a build with ad SDK values | **Yes** (Google, Meta) | Yes (`ads_measurement`) | Advertising or marketing, Analytics |
| Financial info → Purchase history (store order total + currency, with a salted pseudonymous id) | Yes, once the `serverConversions` flag is on | **Yes** (Meta, Google, TikTok — sent from our server) | Yes (`ads_measurement`) | Advertising or marketing, Analytics |

The manifest declares `com.google.android.gms.permission.AD_ID` (Firebase and Meta merge it in anyway): in Play Console › App content › **Advertising ID**, answer *Yes*, purposes *Advertising or marketing* and *Analytics*. If a release ships without ad SDK values, the permission is still declared but never used.

Service providers that process data on our behalf (Shopify, Sentry, PostHog EU, hosting) are not "sharing" under Play's definition.

## Before each submission

- [ ] `SUPPORT_EMAIL` set; privacy/terms brackets filled and reviewed by counsel; `LEGAL_VERSION` in `services/api/src/web/site-pages.ts` bumped when they change.
- [ ] The answers above still match the build and the server (ad SDK values set? Firebase Analytics on? `serverConversions` on? new consent?).
- [ ] Screenshots in both languages; the widget screenshot taken on a real home screen.
- [ ] App Group `group.com.yaqinbrand.yaqeen` enabled for both bundle ids and the widget's App Store profile name in `IOS_WIDGET_PROFILE_NAME` (see RELEASE_MOBILE.md).
