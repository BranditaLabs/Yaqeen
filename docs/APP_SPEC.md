# Yaqeen — Product & UI/UX Build Spec

> **Audience:** Claude Code (and any engineer) building the Yaqeen ecosystem in this repo.
> **Scope:** every screen and every function of the mobile app, the admin dashboard and the API they need —
> layout, states, interactions, data, analytics, notifications and acceptance criteria.
> **Version:** 1.0 · 21 Oct 2026 · Owner: Ahmed Hamdy

---

## 0. How to use this spec

1. Pick the next ticket in **§12 Build plan** (they are ordered by dependency).
2. Read the screen/function section it points to (§5, §6, §7) and the design artboard named there.
3. Build in the layers described in §3. Write tests for every rule marked **Rule**.
4. Tick the **Acceptance** checklist; update the status column in §5.1.

### Status legend

| Mark | Meaning |
| --- | --- |
| ✅ | Built and tested in this repo |
| 🟡 | Partly built (data layer or a first version exists) |
| ⬜ | Not built — design exists |

### Design references (open these while building)

| Canvas | What | Link |
| --- | --- | --- |
| **Yaqeen App Screens** | All 22 app screens in 4 rows + components + Brand board | https://claude.ai/artifact/LvDAGBRz8cJUtuYhFobpaP |
| **Yaqeen Admin Dashboard** | 6 dashboard screens + sidebar | https://claude.ai/artifact/4vwKKmE3ANMa1tLdNhyx8B |
| Brand guide | `packages/brand/README.md` (from *Yaqeen Brand Identity 2026*) | repo |
| App guide (Arabic PDF) | Screen-by-screen walkthrough | `Yaqeen-App-Guide-AR.pdf` (shared separately) |

Artboard names in this spec match the canvas frame titles, e.g. **`07 · Home`**.

---

## 1. Product

**Yaqeen (يقين)** — *“حيث تبدأ السكينة · Where Peace Begins”*. A calm, premium daily companion for Muslims in
Egypt first (then MENA): Quran (read, listen, recite-check, memorise), prayer times + Qibla + adhan, azkar and
duas, a merged Hijri calendar, and the **365 يوماً من اليقين** challenge whose points become discount codes in
the Yaqeen Shopify store (yaqin-brand.com — prayer rugs *السكينة الذهبية · القِبلة · عبق اليقين*, packages).

### 1.1 Users

| Persona | Needs |
| --- | --- |
| Daily reader (primary) | Open → continue reading in one tap; readable mushaf; no distractions |
| Prayer-focused | Exact local times, reliable adhan offline, Qibla |
| Habit builder | Small daily tasks, streaks, gentle reminders, make-ups (qada) without guilt |
| Memoriser | Daily new portion + spaced review |
| Store customer | Earn → redeem codes → buy |
| Team (admin) | Content review, campaigns, points economy, calendar, support |

### 1.2 Product principles

- **Sakina first:** no urgency, no guilt copy, no red badges for missed worship. Missed days are «قضاء», not failures.
- **One primary action per screen.**
- **Private by design:** prayer times, location, Hifz and reading history stay on the device.
- **Works offline** everywhere except redemption, sign-in and content sync.
- **Accessible:** 44 pt targets, Dynamic Type up to 200 % on non-mushaf text, VoiceOver/TalkBack labels in Arabic, reduced motion respected.

---

## 2. Design system

Source of truth: `packages/design-tokens/tokens.json` → Flutter `lib/core/theme/tokens.dart` · Admin `globals.css`.
**How screens are composed — the "living canvas" (living sky, sky headers, complications, the day
journey, motion and performance rules): [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md).** It applies to every
mobile screen; the token tables below are its vocabulary.

### 2.1 Colour

| Token | Hex | Use |
| --- | --- | --- |
| `midnight` / `ink` | `#0A1530` | Primary text, logo navy, primary buttons (dark pill) |
| `navy` | `#10214D` | Gradient middle, dark surfaces |
| `lapis` | `#1F3F94` | Accent: links, active tab, toggles on, progress |
| `royal` | `#2A52B8` | Hover/pressed lapis |
| `sky` | `#8FB0E0` | Soft accent, charts, ambient light |
| `gold` | `#C6A867` | Diamond, rewards, challenge, streak |
| `goldText` | `#7C6127` | Gold **text** on light (AA contrast) |
| `porcelain` | `#F3F6FB` | App background (splash `#F7F9FC`) |
| `muted` | `#56637F` | Secondary text |
| `line` | `#DCE4F2` | Hairlines |
| `success` / `error` | `#2E7A55` / `#B23A48` | Status only, never for worship outcomes |
| Tints | `slate700…gold100` (15) | Charts, chips, disabled states |
| Mushaf themes | paper `#FFFDF7`/`#1A1712` · white · night `#15161A`/`#E9E2D0` | Reading mode only |

**Brand gradient** `#0A1530 → #10214D (45 %) → #1F3F94`: app icon and rare premium surfaces. Content screens stay porcelain.

### 2.2 Typography

| Role | Family | Notes |
| --- | --- | --- |
| Arabic headlines | **ZEYADA Arabic 1** → fallback Amiri | Commercial — files pending (`packages/brand/fonts`) |
| Latin headlines | **Canela Text** → fallback Amiri/Georgia | Commercial — files pending |
| UI / body | Tajawal 400/500/700 | Bundled (OFL) |
| Numbers | Jost 300/400/500, tabular | Bundled; **Western digits** |
| Mushaf | Amiri Quran (until KFGQPC licensed) | Size user-controlled 22–34 |
| Duas/azkar | Amiri 700 | |

Scale (pt): display 30/1.4 · title-L 19 · title-M 15 · body-L 16/1.75 · body 14/1.7 · caption 12 · micro 11. Numerals: 38–50 light.

### 2.3 Space, radius, motion

- Space: 4 · 8 · 12 · 16 · 20 · 28; page gutter **20**; touch **44**.
- Radius: pill 999 · hero 30 · card 24 · tile 20 · chip 14.
- Motion: ease `cubic-bezier(.2,.7,.2,1)`; fast 200 · base 350 · slow 600 ms. Press = scale .985. Respect reduce-motion (jump to end state).

### 2.4 Components (Flutter, `lib/core/widgets`)

| Component | Status | Spec |
| --- | --- | --- |
| `LiquidGlass` | ✅ | White 58 % fill, blur σ12 (CSS 24 px), 1 px white rim, inner top highlight, soft navy shadow. `tone: clear|gold`. `YqGlassConfig.enableBlur=false` in tests. |
| `GlassTap` | ✅ | Press scale + haptic light; semantic label required when no text |
| `GlassIconButton` | ✅ | 44×44 circle glass, tooltip = a11y label |
| `YqIcon` | ✅ | 20 icons × 4 tones (`active, idle, gold, light`) on a 24 grid, 1.5 stroke, one gold accent |
| `YqLogo` | ✅ | `mark | stacked | horizontal | arabic` × `onLight | onDark`; min widths 24 / 96 |
| `FloatingTabBar` | ✅ | 350×66 floating glass pill, 5 tabs: الرئيسية · القرآن · الصلاة · التحدي · حسابي (avatar) |
| `YqSwitch`, `YqSegmented`, `YqProgressLine` | ✅ | Lapis on, porcelain track |
| `AmbientBackground` | ✅ | Porcelain lit by the **living sky** (tint + glow under the sun, follows the time of day; DESIGN_SYSTEM §2); `lights:` adds accents (`goldLights`) |
| `YqCanvas` / `YqStage` / `YqOrb` / `YqRing` / `YqTimeline` / `YqGroup` | ✅ | The living-canvas screen kit — every screen is stage → complications → journey (DESIGN_SYSTEM §3–4) |
| **Built** | ✅ | `YqButton`, `YqListRow`, `YqSection`, `YqGroup`, `YqEmptyState`, `YqErrorState`, `YqOfflineBanner`, sheets, `YqChip`, `YqStepper`, `YqCountdown`, `YqToast`, shaped skeletons (`YqSkeletonOrbs/Rows/Text`) and `OuterShadow` |

### 2.5 Universal screen states (every data screen must implement)

| State | Pattern |
| --- | --- |
| Loading | Skeleton of the real layout (glass blocks shimmer 1.2 s), never a bare spinner on first paint |
| Empty | `YqEmptyState`: icon (idle tone) + 1-line title + 1-line hint + optional action (texts given per screen) |
| Error | `YqErrorState`: «تعذّر التحميل. تحقق من الاتصال.» + «إعادة المحاولة» |
| Offline | Thin banner «أنت غير متصل · نعمل بما على جهازك» on screens that need network; local features silently work |
| Saved offline | Toast «حُفظ وسيُزامَن عند الاتصال» after an Outbox write while offline |

### 2.6 RTL & numbers rules

- `Directionality` RTL from locale `ar`; use `EdgeInsetsDirectional`, `AlignmentDirectional`.
- Back chevron points **right** in RTL. Page-turn swipe: left→right goes to **next** page (mushaf order).
- Mixed text: wrap Latin/number runs (`lang=en`) so punctuation stays correct (see the admin login fix).
- Dates: Gregorian `d MMMM` Arabic month names + Western digits; Hijri from API (§6.10).

---

## 3. Architecture recap (what exists — reuse it)

```
apps/mobile/lib
  app/            router.dart (StatefulShellRoute, 5 branches) · shell.dart
  core/
    config/env.dart                 API_BASE_URL, FLAVOR, STORE_URL (--dart-define)
    di/providers.dart               ALL dependencies (override in main/tests)
    network/api_client.dart         JSON client, bearer, 1 refresh on 401, ApiException/OfflineException
    offline/outbox.dart             persistent FIFO, clientEventId, flush rules
    storage/kv_store.dart           Prefs / Secure / Memory
    analytics/analytics.dart        AdEvent allowlist + consent gate + AdSink interface
    notifications/                  notification_planner.dart (pure), push_service.dart (deep links)
    theme/ widgets/                 design system
  features/<name>/{domain,data,presentation}   (READMEs inside each folder)
```

Rules already enforced by tests: outbox ordering/drop rules, analytics gate, deep-link map, planner iOS limit,
hifz intervals, challenge model parsing/optimistic updates, splash uses artwork only.

---

## 4. Navigation

### 4.1 Route map (go_router)

| Route | Screen | Artboard | Tab |
| --- | --- | --- | --- |
| `/splash` | Splash | 01 · Splash | — |
| `/onboarding/welcome` | Sign in | 02 · Sign in | — |
| `/onboarding/language` | Language & mushaf | 03 | — |
| `/onboarding/prayer` | Prayer setup | 04 | — |
| `/onboarding/consent` | Notifications & privacy | 04·ب | — |
| `/onboarding/goal` | Daily goal & challenge | 05 | — |
| `/onboarding/routine` | Daily routine «متى يناسبك؟» | 05·ب | — |
| `/onboarding/download` | Offline mushaf | 06 | — |
| `/home` | Home | 07 · Home | الرئيسية |
| `/home/azkar` · `/home/duas` · `/home/inbox` | Azkar · Duas · Inbox | 16 · 17 · 15·ب | الرئيسية |
| `/quran` | Quran index | 08 | القرآن |
| `/quran/read/:page` | Reading mode | 09 | (full-screen, no tab bar) |
| `/quran/recite/:surah` | Recitation check | 10 | (full-screen) |
| `/quran/listen/:surah` | Now playing | 11 | (full-screen) |
| `/quran/reciters` | Choose a reciter | 12 | |
| `/quran/hifz` | Hifz plan | 22 | القرآن |
| `/prayer` | Prayer times | 13 | الصلاة |
| `/prayer/qibla` | Qibla compass | 14 | (full-screen) |
| `/prayer/notifications` | Adhan & notifications | 15 | |
| `/challenge` | 365 challenge | 19 | التحدي |
| `/challenge/calendar` | Calendar of Yaqeen | 18 | |
| `/challenge/redeem` | Redeem reward | 20 | |
| `/profile` | Profile & settings | 21 | حسابي |

**Rules**
- First launch: `/splash → /onboarding/welcome …`. Later launches: `/splash → /home` (or the deep link).
- Splash holds ≥ 3.8 s on first launch, **1.2 s** on later launches (skip choreography after the first time each day).
- Full-screen routes hide the tab bar and use a top-level navigator.
- Back from a tab root does nothing (Android: exits app after confirmation-free double back within 2 s is **not** used — standard behaviour).

### 4.2 Deep links (`yaqeen://<target>`, also universal links `https://yaqin-brand.com/app/<target>`)

`home · quran · prayer · challenge · calendar · redeem · azkar · hifz · store` → routes above
(update `routeForDeepLink` when the sub-routes exist; it currently maps calendar/azkar/hifz to their tab roots).
Push payload: `data.link`, `data.campaignId` (opened → `POST /v1/me/campaigns/:id/opened`, §8.2 new).

---

## 5. App screens

### 5.1 Status board

| # | Screen | Route | Status | Still open (owner decisions, §13) |
| --- | --- | --- | --- | --- |
| 01 | Splash | `/splash` | ✅ | — |
| 02 | Sign in | `/onboarding/welcome` | ✅ | OAuth client ids (Google, Apple Services ID) |
| 03 | Language & mushaf | `/onboarding/language` | ✅ | Indo-Pak text licence (shown «قريباً») |
| 04 | Prayer setup | `/onboarding/prayer` | ✅ | — |
| 04·ب | Notifications & privacy | `/onboarding/consent` | ✅ | — |
| 05 | Daily goal & challenge | `/onboarding/goal` | ✅ | — |
| 05·ب | Daily routine | `/onboarding/routine` | ✅ | — |
| 06 | Offline mushaf | `/onboarding/download` | ✅ | tafsir pack licence (§10); the pack manager installs it once published |
| 07 | Home | `/home` | ✅ | — |
| 08 | Quran index | `/quran` | ✅ | — |
| 09 | Reading mode | `/quran/read/:page` | ✅ | KFGQPC page fonts licence (Amiri Quran until then) |
| 10 | Recitation check | `/quran/recite/:surah` | 🟡 beta flag | on-device ASR model passing the ship gate (§6.8) |
| 11 | Now playing | `/quran/listen/:surah` | ✅ | licensed recitations + timing files in the catalogue |
| 12 | Choose a reciter | `/quran/reciters` | ✅ | same |
| 13 | Prayer times | `/prayer` | ✅ | — |
| 14 | Qibla | `/prayer/qibla` | ✅ | — |
| 15 | Adhan & notifications | `/prayer/notifications` | ✅ | licensed adhan audio (flag `ADHAN_SOUNDS`) |
| 15·ب | Notification centre | `/home/inbox` | ✅ | — |
| 16 | Azkar counter | `/home/azkar` | ✅ | reviewed azkar published in the dashboard (seed is export-only) |
| 17 | Duas | `/home/duas` | ✅ | same |
| 18 | Calendar of Yaqeen | `/challenge/calendar` | ✅ | — |
| 19 | 365 challenge | `/challenge` | ✅ | — |
| 20 | Redeem reward | `/challenge/redeem` | ✅ | Shopify credentials |
| 21 | Profile & settings | `/profile` | ✅ | — |
| 21·ب | Yaqeen card (NFC/QR) | `/profile/card` | ✅ | §5.26 |
| 22 | Hifz plan | `/quran/hifz` | ✅ | — |
| 23 | Ramadan | `/prayer/ramadan` | ✅ flag `ramadan` | Ramadan bonus values (seeded off) |
| 24 | Khatma | `/quran/khatma` | ✅ | — |
| — | Home-screen widgets | Android / iOS | ✅ | App Group + widget profile in the Apple account |
| — | Website | `/`, `/privacy`, `/terms`, `/support`, `/delete-account` | ✅ | legal entity, DPO, support email, counsel review |

Each section below uses the same headings: **Purpose · Layout · Data · Interactions · States · Analytics &
notifications · Acceptance**. Arabic strings are the real UI copy (put them in the ARB files).

---

### 5.2 `01 · Splash` — `/splash` ✅

**Purpose** Brand moment while the app warms up (config, Hijri cache, notification re-plan).

**Layout** Porcelain `#F7F9FC` + white bloom at 45 % height, sky breath top, gold breath bottom. **Logo mark only**
(136 pt wide, optical centre 45 %), split into navy wings + gold diamond layers. Bottom: verse
«وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ٱلْيَقِينُ» (Amiri Quran 18, ٱلْيَقِينُ in `goldText`), caption «الحِجر · 99», 96×2 gold progress line.

**Motion (ms)** wings spread 300–1600 (blur→sharp, scaleX .84→1) · diamond settles 1250–2250 (easeOutBack) · glow 1850–3250 then breathes (4.5 s loop) · glint 2300–3800 · verse 2600–4000 · progress 2800–5200.

**Data** Verse text comes from remote config `splashVerse` (admin-editable, reviewer-approved); bundled default above.

**Interactions** None (no tap-to-skip on first launch; later launches auto-advance at 1.2 s).

**Work done during splash** (parallel, never blocks > hold time): load consents → `GET /v1/config` (cached) → maintenance/min-version check (§6.15) → refresh Hijri month cache → re-plan local notifications (§6.5) → flush Outbox.

**Acceptance**
- [x] Uses artwork only (no typeset name) — test exists.
- [ ] Native splash (`flutter_native_splash`) shows the same navy mark on `#F7F9FC`; no colour jump.
- [ ] Reduce-motion shows final frame instantly.
- [ ] Min-version / maintenance redirect happens from here.

---

### 5.3 `02 · Sign in` — `/onboarding/welcome` ✅

**Purpose** Welcome + choose how to continue.

**Layout**
1. Header 44 pt: horizontal navy lockup (h 34) · glass pill «English» (globe icon) — switches locale live.
2. Eyebrow «السلام عليكم» (goldText 12) → H1 «طمأنينةٌ يومية\nتبدأ من هنا» (34/1.35 bold) → body «اقرأ واستمع إلى القرآن، وحافظ على صلاتك وأذكارك، ورافقنا في رحلة 365 يوماً من اليقين.»
3. Three benefit rows (icon + text, hairline separators): «مصحف كامل مع تلاوات وتصحيح للقراءة» · «مواقيت دقيقة وقبلة وتنبيه للأذان» · «نقاط يومية تُستبدل بخصومات في متجر يقين» (gold icon).
4. Bottom stack: glass pill «المتابعة باستخدام Google» (G logo) · dark pill «المتابعة باستخدام Apple» (iOS always; Android too) · text button «المتابعة كضيف» · legal line «بالمتابعة فإنك توافق على الشروط و سياسة الخصوصية».
5. Entrance: sections rise 14 px with 0.1 / 0.3 / 0.5 s delays.

**Data** `AuthRepository.signIn(provider, idToken)` → `POST /v1/auth/sign-in`. Google via `google_sign_in`, Apple via `sign_in_with_apple` (Apple returns the name only on first sign-in → pass as `displayName`).

**Interactions**
- Provider button → native sheet → on success store tokens → `/onboarding/language`. Event `sign_up` (consent-gated; consent isn't given yet, so it's queued and sent only if `ads_measurement` is granted on 04·ب — **Rule**: queue, don't send).
- «كضيف» → `provider: guest` → same flow. Guests can use everything except earning/redeeming points (§6.1).
- Cancel in native sheet → stay, no error.

**States** Button spinner while signing in (disable all three). Error toast «تعذّر تسجيل الدخول، حاول مرة أخرى». Offline: Google/Apple disabled with hint «يلزم اتصال لتسجيل الدخول»; guest still works (offline guest session created on first sync).

**Acceptance**
- [ ] Apple button shown on iOS (App Store rule 4.8) and Android.
- [ ] Language pill switches all copy without restart.
- [ ] Guest path reaches Home with zero network.
- [ ] Tokens only in secure storage.

---

### 5.4 `03 · Language & mushaf` — `/onboarding/language` ✅

**Layout** Header: back · stepper «الخطوة 1 من 4» (4 dashes, lapis filled) · «تخطي». Eyebrow «01 / 04», H1 «لغتك ومصحفك», sub «يمكنك تغيير ذلك لاحقاً من الإعدادات.»
Sections (glass cards):
- **لغة التطبيق**: segmented «العربية | الإنجليزية».
- **رسم المصحف**: two radio cards — «الرسم العثماني · مصحف المدينة النبوية» / «الرسم الهندي · شائع في جنوب آسيا»; live preview line «بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ» in the chosen script.
- **حجم الخط**: S/M/L/XL slider (22/26/30/34) updating the preview.
CTA dark pill «متابعة».

**Data** Local settings (`settings.locale`, `quran.script`, `quran.fontSize`) + `PATCH /v1/me/settings {locale}` when online.

**Rules** «تخطي» keeps defaults (ar · uthmani · M). Indo-Pak script requires the second text asset (§6.6); if not licensed at launch, show it disabled with «قريباً».

**Acceptance** [ ] Preview updates instantly · [ ] Locale persists across restarts · [ ] Back returns to 02.

---

### 5.5 `04 · Prayer setup` — `/onboarding/prayer` ✅

**Layout** Stepper 2/4. H1 «مواقيت دقيقة لمكانك», sub «نستخدم موقعك لحساب الصلاة والقبلة فقط، ويُحفظ على جهازك.»
- **Location card**: «القاهرة، مصر» · «تم تحديد موقعك تلقائياً» · «تغيير» (opens city search sheet).
- **طريقة الحساب**: radio list — «الهيئة المصرية العامة للمساحة · الموصى بها لموقعك» (default in Egypt) · «رابطة العالم الإسلامي · الفجر 18° · العشاء 17°» · «أم القرى · المملكة العربية السعودية».
- **مذهب العصر**: segmented «الجمهور | الحنفي».
- **تنبيه الأذان** switch + detail «بصوت الحرم المكي · قبل الصلاة بـ 10 دقائق».
CTA «متابعة».

**Data / Rules**
- Request location **when-in-use** only, after the user sees this screen (never at app start). Denied → city search, no nagging.
- Recommend method by country: EG → Egyptian; SA → Umm al-Qura; others → MWL. Store `{lat,lng,city,country,tz,method,asr}` **on device**; send only `city`, `timezone`, `prayerMethod`, `asrSchool` to `PATCH /v1/me/settings` (timezone drives server "today").
- City search: bundled list of the ~1,500 largest MENA + world cities (offline JSON) + device geocoder.

**Acceptance** [ ] Works with location denied · [ ] Times on 13 match a reference (Egyptian General Authority) within 1 minute for Cairo/Alexandria/Aswan · [ ] Coordinates never sent to the API.

---

### 5.6 `04·ب · Notifications & privacy consent` — `/onboarding/consent` 🟡

**Layout** Stepper 3/4. Eyebrow «03 / 04», H1 «تنبيهات تهمّك\nوخصوصيتك محفوظة», sub «اختر ما يصلك. يمكنك تغيير ذلك في أي وقت من الإعدادات.»
Glass card with 5 switch rows (40 pt icon tile + title + 11 pt description):

| Bucket | Title | Description | Default |
| --- | --- | --- | --- |
| `worship_reminders` | تذكيرات العبادة | الأذان، الأذكار، الورد ومراجعة الحفظ. تعمل من هاتفك حتى دون إنترنت. | ON |
| `challenge_rewards` | التحدي والمكافآت | تقدمك في 365 يوماً، والأيام الفائتة، ورصيد يكفي لمكافأة. | ON |
| `store_offers` | عروض متجر يقين | خصومات وإصدارات جديدة، بحد أقصى رسالة واحدة يومياً. | **OFF** |
| `ads_measurement` | تحسين إعلانات يقين | قياس نجاح إعلاناتنا على جوجل وميتا وتيك توك: التحميل والتسجيل والاستبدال فقط. | **OFF** |
| `product_analytics` | تحسين التطبيق | إحصاءات استخدام مجهولة تساعدنا على تحسين يقين: الصفحات والخطوات فقط، بلا حسابك ولا أي عبادة. | **OFF** |

Green privacy note «عباداتك لا تُشارك أبداً مع أي منصة إعلانية: لا قراءة ولا صلاة ولا ذكر ولا حفظ. سياسة الخصوصية».
CTA «متابعة» + caption «سيطلب هاتفك بعدها إذن الإشعارات» (+ «، وعلى iPhone إذن التتبع» when ads is ON).

**Rules**
- Each toggle → `ConsentRepository.set(kind, value, ConsentSource.onboarding)` (local first, then `PUT /v1/me/consents`).
- After «متابعة»: if any of the first three ON → OS notification permission (Android 13+ `POST_NOTIFICATIONS`, iOS alert/sound/badge). If `ads_measurement` ON on iOS → ATT prompt **after** the OS notification prompt. ATT denied → ad SDKs stay in limited mode; consent stays true.
- Flush queued ad events (`first_open`, `sign_up`) only if `ads_measurement` ended ON.

**Acceptance** [ ] Defaults exactly as table · [ ] Every change creates a `consent_events` row with `source=onboarding` · [ ] Declining OS permission doesn't block the flow.

---

### 5.7 `05 · Daily goal & challenge` — `/onboarding/goal` ✅

**Layout** Stepper 4/5. H1 «وِردك اليومي», sub «قليلٌ دائم خيرٌ من كثيرٍ منقطع. اختر ما يناسب يومك.»
- Goal chips (single select): صفحة · **صفحتان** (default) · 4 صفحات · جزء.
- **Challenge card** (gold glass): eyebrow «تحدٍّ سنوي», title «365 يوماً من اليقين», switch «الانضمام إلى التحدي» (default ON), body «أكمل وردك وأذكارك وصلواتك كل يوم، واجمع النقاط لتستبدلها بخصومات حصرية في متجر يقين.», two stats «100 نقطة يومياً» · «1,000 نقطة = مكافأة» (values from remote config `points.dailyTotal` and the cheapest reward).
CTA «ابدأ رحلتي».

**Rules**
- Join ON + signed-in → `POST /v1/challenge/enroll` (event `challenge_join`). Join ON + guest → sheet «سجّل الدخول لتحفظ نقاطك» with Google/Apple, or «لاحقاً» (keeps guest, join later from 19).
- Wird goal → local settings. When to read is chosen on the next step (§5.7·ب).

**Acceptance** [ ] Numbers come from config, not hard-coded · [ ] Guest never calls enroll.

---

### 5.7·ب `05·ب · Daily routine` — `/onboarding/routine` ✅

**Purpose** The user anchors their habits to their day, so Home's «يومك» timeline and the reminders
follow their life, not a fixed clock.

**Layout** Stepper 5/5. H1 «متى يناسبك؟», sub «اختر وقتاً لكل عادة، وسنرتّب يومك على مواقيت الصلاة ونذكّرك في وقتها.»
One glass card per habit with chips «بعد الفجر · بعد الظهر · بعد العصر · بعد المغرب · بعد العشاء · وقت محدد · لا»
and today's real time as a preview («بعد الفجر · 5:48 ص»):
- **قراءة القرآن** (required; default 15 min after Fajr),
- **مراجعة الحفظ** (when the `hifz` flag is on; default off),
- **ورد الذكر** (default off).
CTA «رتّب يومي».

**Rules**
- Stored as `RoutineSlot` in local settings (`quranSlot`, `hifzSlot`, `dhikrSlot`): after a prayer + 15 min, a set
  time, or off. **Device-only — never in the settings patch sent to the API.** Editable later under «روتيني» in
  notification settings.
- The planner schedules the wird, hifz and dhikr reminders at the resolved daily time (quiet hours apply).
- Home's timeline shows each habit at its time; due from then until the next prayer; «تم» when today's wird goal is met.
- A legacy fixed wird time (older installs) migrates as «وقت محدد».

**Acceptance** [ ] Choice previews today's real time · [ ] Reminders and timeline follow the choice · [ ] Nothing
routine-related reaches the API.

---

### 5.8 `06 · Offline mushaf` — `/onboarding/download` ✅

**Layout** Eyebrow «تجهيز المصحف», H1 «القرآن معك\nحتى دون اتصال», sub «نحمّل النص والخطوط مرة واحدة، ونحدّثها تلقائياً كل أسبوع.» Big ring «72 %» + «31 من 43 م.ب».
Item list with status: «نص المصحف · رواية حفص · 6 MB ✓» · «خط المصحف العثماني · 18 MB ✓» · «التفسير الميسر · 19 MB · جارٍ التحميل…» · optional switch «تلاوة مشاري العفاسي · اختياري · عبر Wi-Fi فقط · 1.1 GB».
Footer verse «وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا». CTAs «ابدأ الآن» (enabled as soon as text+font are ready) · «في الخلفية» hint.

**Rules** Text + font are **bundled in the app binary** (no download needed for reading on day one); tafsir and audio download with resume (`background_downloader`), Wi-Fi-only for audio. «ابدأ الآن» → `/home`, downloads continue in background with a progress notification (Android) / silent (iOS).

**Acceptance** [ ] Reading works in airplane mode right after install · [ ] Interrupted download resumes · [ ] Storage shown in Profile › التنزيلات.

---

### 5.9 `07 · Home` — `/home` ✅ ("living canvas", DESIGN_SYSTEM.md)

**Purpose** Today at a glance as a living scene; one tap to the most likely next action.

**Layout** (scroll; the sky stage runs edge to edge under the status bar; content gutter 20; bottom 140 for the tab bar)
1. **Sky stage** — sky gradient that follows the time of day (living sky). Greeting by time («صباح الخير» before
   Dhuhr / «مساء الخير» after) · name · Hijri date + city (Gregorian until the Hijri cache has today) · search and
   bell (unread dot). Then «الصلاة القادمة» · prayer name large · «3:53 م · الأذان بعد» · live countdown · the
   day arc (the sun — a crescent at night — at its real position between the five prayer stations) · station names.
   Tap → `/prayer`.
2. **Complications** — three orbs: **Qibla** (the Kaaba orbits the ring and reaches the top when the phone faces it;
   gold glow + light haptic; bearing from north without a compass; tap → Qibla), **المسبحة** (33-bead misbaha:
   tap counts, hold resets; device-only count), **الورد اليومي** (liquid fill, pages/goal; tap → Quran).
3. **«يومك» timeline** — Fajr → morning azkar → Dhuhr → Asr → evening azkar → Maghrib → Isha, plus the user's
   **routine** stops (§5.7·ب) at their times. Past moments recede; the next prayer is tagged «التالية»; azkar glow
   «متاحة الآن» while open; routine stops «حان وقته» while due, «تم» when done. A «الآن» marker carries the
   continue-reading card (Friday: Al-Kahf suggestion). The challenge card (or the «ابدأ رحلة 365 يوماً» CTA) closes the day.
4. **Services** — الأذكار · الأدعية · التقويم · خطة الحفظ (القبلة when hifz is off).
5. Floating tab bar.

**Data**
| Block | Source |
| --- | --- |
| Name | `/v1/me` (cached) or «ضيف» |
| Hijri date | Calendar cache (§6.10) for today |
| Prayers, sky, arc | Local prayer engine (§6.4) |
| Routine | Local settings (`quranSlot`, `hifzSlot`, `dhikrSlot`) |
| Continue reading | Local `quran.lastRead {page, surah, juz}` |
| Wird | Local `wird.today {pagesRead, goal}` |
| Tasbeeh | Local `home.tasbeeh` |
| Streak / day / balance | `ChallengeSummary` (cached, optimistic) |
| Unread | Local inbox store (§6.5) |

**Rules**
- Countdown ticks every second only while visible; cards re-plan every 15–30 s; the compass runs only while visible.
- At adhan time the stage flips to «حان وقت صلاة العصر» for 20 minutes, then advances.
- Guest/not enrolled: the challenge card becomes «ابدأ رحلة 365 يوماً».

**States** Prayers and the timeline never load (local). No challenge data offline → last cached values, no error.

**Acceptance** [ ] Countdown correct across midnight and DST change (Egypt) · [ ] All taps route as listed ·
[ ] VoiceOver reads the stage as one element · [ ] Timeline order follows the real times incl. the routine.

---

### 5.10 `08 · Quran index` — `/quran` ✅

**Layout**
1. Title «القرآن الكريم» · glass buttons «الاستماع» (→ listen last surah) and «خطة الحفظ» (→ `/quran/hifz`).
2. Search field «ابحث عن سورة أو رقمها» with clear button «مسح البحث».
3. **Continue cards** (horizontal): «سورة الكهف · الصفحة 296 · آخر قراءة» · bookmarks like «سورة يس · الآية 58 · علامة محفوظة».
4. Segmented «طريقة التصفح»: **السور | الأجزاء | المحفوظات**.
   - السور: 114 rows — number medallion (no ornament: plain circle hairline) · name · «مكية/مدنية · N آية» · start page on the end side.
   - الأجزاء: 30 rows «الجزء N · يبدأ من البقرة 142» (+ hizb quarters on expand).
   - المحفوظات: bookmarks (page marks + ayah marks), newest first.
5. Empty search: «لا توجد نتائج» / «جرّب اسماً آخر أو رقم السورة». Empty bookmarks: «لا توجد علامات بعد» / «اضغط مطولاً على أي آية لحفظ علامة».

**Search rules** Normalise Arabic (strip tashkeel, unify أإآا, ة/ه, ى/ي), match surah name, number, or `surah:ayah` (e.g. «18:10» → page of that ayah). **Full-text ayah search ✅**: every ayah reduced once (off the UI thread) to a search key that reads Uthmani spelling the everyday way — alefs dropped, «وٰ» read as alef (صلوٰة ↔ صلاة، حيوٰة ↔ حياة) — so «الصلاة», «العالمين» or «الحي القيوم» find their ayat; all words must occur (any order), exact phrases first, then mushaf order. Results «في الآيات · N نتيجة» show the ayah with the match lit in the original text; tap → the reader on that page with the ayah lit (`/quran/read/<page>?ayah=s:a`). Arabic-only queries; offline; < 400 ms worst case for the whole mushaf.

**Saved tab** Filters الكل · العلامات · الملاحظات · التظليل; bookmarks carry their colour; every row opens the ayah lit.

**Data** Local SQLite `quran.db` (surahs, juz, hizb, page → ayah ranges); bookmarks in local DB (copied to the server only with the opt-in cloud backup — §6.13).

**Acceptance** [ ] Search < 50 ms on a mid device · [ ] Tap surah → `/quran/read/<startPage>` · [ ] Works offline from first launch.

---

### 5.11 `09 · Reading mode` — `/quran/read/:page` ✅

**Purpose** The heart of the app: a calm, faithful mushaf page.

**Layout**
- Full-bleed page in the chosen theme (paper/white/night). Page header (chrome): surah name · «الجزء N · الحزب N». Footer: page number «N من 604».
- Ayah text with end markers «﴿N﴾»; surah headers with the Basmala «بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ» (except At-Tawbah).
- **Chrome** (tap anywhere toggles, auto-hide after 4 s): top: exit «الخروج إلى الفهرس» · settings · lock «قفل اللمس أثناء القراءة» · page-mark toggle («حفظ علامة على الصفحة / إزالة علامة الصفحة»). Bottom glass bar: «الورد» progress · «استماع» · «تسميع» · page slider «التنقل بين الصفحات».
- First-open hint (once): «المس لإظهار الأدوات · اضغط مطولاً على الآية لخياراتها · اسحب لتقليب الصفحة».

**Ayah long-press** → highlight + glass sheet «خيارات الآية»: علامة (toggle, «محفوظة») · استماع (from this ayah) · تفسير (expands «التفسير الميسر» panel with the licensed text) · مشاركة (image card with ayah + reference, brand footer mark) · نسخ («تم النسخ»; copies text + «[سورة البقرة: 2]»).

**Settings sheet «إعدادات القراءة»** «لون الصفحة» (ورقي · أبيض · ليلي) · «حجم الخط» (S/M/L/XL) · «تباعد مريح بين الأسطر» · «إبقاء الشاشة مضاءة أثناء القراءة» · shortcuts «وضع الاستماع» / «وضع التسميع».

**Moving around** Tap the title pill → «انتقل إلى»: surah (filterable list), juz (30 chips), page number, or surah + ayah. The page header shows juz · hizb; inside the text a quiet hairline pill marks where a juz, hizb or hizb quarter starts («الجزء 3» · «الحزب 5» · «¼ الحزب 5»), and «سجدة» follows a prostration ayah.

**Layout & turning** A two-page spread (right/left, like the printed mushaf) when the screen is wide (tablet, or landscape ≥ 700 pt); chrome stays ≤ 640 pt wide, centred. Page turn «كالكتاب» (default: the page lifts from the spine with a soft shade, transform only; off with reduce-motion) or «انزلاق». The system bars hide with the chrome («إخفاء شريط الحالة أثناء القراءة», on by default). «الوضع الليلي تلقائياً بعد المغرب» switches to night pages from Maghrib to sunrise.

**Annotations (device only)** Ayah sheet adds تظليل (4 token colours or none), ملاحظة (private reflection ≤ 2,000 chars; a small note icon after the ayah opens it) and a colour for an ayah bookmark. Highlights tint the ayah on the page.

**Memorise mode** «حفظ» in the bottom bar: إخفاء الآيات, or إخفاء كلمة وترك كلمة (first word kept as a cue). Hidden text keeps its exact place (transparent ink over a dotted line), so revealing never moves the page; tap an ayah to show/hide it; banner with «إظهار الكل · إخفاء الكل» and exit. Long-press options pause while memorising.

**Reading stats** Each page view adds its time (≤ 5 min per view) and each counted page to a per-day log (120 days, device only): the khatma screen shows the week's pages, minutes, reading days and streak.

**Lock mode** Hides chrome, ignores taps/swipes; overlay pill «الشاشة مقفلة · اضغط مطولاً لإلغاء القفل» (1.2 s hold with ring «استمر بالضغط…»).

**Rules**
- **Rendering**: page-faithful layout (604 pages, Madani 15-line). Use a per-page glyph font (KFGQPC QCF) once licensed; until then, line-by-line text with Amiri Quran and page ranges from Tanzil metadata (§10). Never reflow ayah across pages.
- Swipe: RTL book order — dragging **left→right** goes to the next page. Pre-render ±2 pages.
- **Wird tracking**: a page counts as read after ≥ 20 s visible (configurable `wird.minSecondsPerPage`); updates `wird.today` and, when the goal is reached, ticks challenge task `wird` locally (Outbox `POST /v1/challenge/tasks/wird/complete`).
- `lastRead` saved on every page change.
- Wakelock only while this screen is visible and the setting is ON.

**A11y** Each ayah is a semantics node: «سورة الفاتحة، الآية 2. اضغط مطولاً للخيارات». Mushaf font size not affected by system text scale (own control); chrome text is.

**Acceptance** [ ] 60 fps page turns on a 2021 mid Android · [ ] Page/juz/hizb correct for all 604 pages (golden test vs metadata) · [ ] Wird tick happens once per day · [ ] Night theme meets AA.

---

### 5.12 `10 · Recitation check (تسميع)` — `/quran/recite/:surah` 🟡 (UI + aligner; ASR model pending) · flag `recite`

**Layout** Header: back · surah «الفاتحة» · «الجزء 1 · الصفحة 1» · segmented «قراءة | استماع | تسميع» (switches modes for the same position). Ayat shown progressively; hidden until recited when «إظهار الآيات» is OFF (memorisation test). Bottom: big mic button with live waveform and label «يستمع إليك» · «إيقاف التسميع» · «استمع إلى القارئ».
Result strip: «3 آيات صحيحة» (success tone) · «تنبيه واحد: الْعَالَمِينَ» (the word underlined in gold, tap → play the reciter for that ayah).

**Rules**
- **Beta behind remote flag `recite`**; label «تجريبي» on the tab. Copy must never say «خطأ في القرآن»; use «تنبيه».
- Engine (§6.8): on-device ASR (Arabic Quran-tuned model) → word alignment against the expected ayah text → mark `ok | warn | skipped`. Audio is **not uploaded** by default.
- Microphone permission requested on first tap with rationale sheet «نستمع لتلاوتك على جهازك فقط».
- Results feed Hifz review quality (§6.14) when started from the Hifz screen.

**Acceptance** [ ] Works offline after model download · [ ] No audio leaves the device · [ ] Flag OFF hides the tab everywhere.

---

### 5.13 `11 · Now playing` — `/quran/listen/:surah` ✅

**Layout** Back «رجوع إلى المصحف» · download button «تنزيل السورة». Eyebrow «يُشغَّل الآن», surah card «السورة 18 · مكية · 110 آيات» with name «الكهف» in display face, reciter «مشاري راشد العفاسي». Current ayah card (glass) with ayah text and number + collapsible tafsir line. Progress bar «4:12 / 23:40» (seek). Controls «التحكم في التشغيل»: repeat ayah · previous ayah · play/pause (64 dark pill) · next ayah · speed (0.75/1/1.25/1.5). Bottom chips «تغيير القارئ» (→ 12) · «مؤقت النوم» (sheet: 15/30/45/60 min, end of surah).

**Rules (§6.7)** `just_audio` + `audio_service`: background playback, lock-screen + notification controls, Bluetooth buttons, interruption handling (pause on call, resume after). Ayah sync from per-ayah timings (Quran Foundation verse timestamps, resolved per surah by `GET /v1/content/reciters/:id/surahs/:n` and kept on the device; a full download also saves `timings.json`); current ayah also highlighted if the reader is open. The tafsir line uses the same source as the reader (§6.6) and credits it. Streaming when online; downloaded files preferred. Repeat modes: ayah ×N, range A–B, surah. Listening ≥ 5 minutes in a day ticks challenge task `listen`.

**Acceptance** [ ] Continues with screen off · [ ] Highlight within 150 ms of ayah boundaries · [ ] Resumes position after app kill.

---

### 5.14 `12 · Choose a reciter` — `/quran/reciters` ✅

**Layout** Back «رجوع إلى المشغل», title «اختر القارئ», search «ابحث عن قارئ», filter chips «الكل | المحمّلة» + style «مرتّل | مجوّد». List rows: avatar initial · name · «مرتّل · حفص عن عاصم» · sample play («استمع لعينة من …» / «إيقاف العينة») · download state («محمّل · المس للحذف», ring «جارٍ التحميل · المس للإلغاء», or button «تحميل المصحف كاملاً للاستماع دون اتصال»). Selected row has lapis check. Footer note «التلاوات من Quran.com · Quran Foundation، والتحميل يتيح الاستماع دون اتصال.» (attribution, §10). Style chip «معلّم» appears only when the catalogue has a muallim recitation. The sample button plays an explicit `sampleUrl`, else Al-Fatiha through the same per-surah resolver.
Empty search: «لا يوجد قارئ بهذا الاسم» / «جرّب جزءاً من الاسم».

**Data** Curated catalogue `GET /v1/content/reciters` (table `reciters`: allowlist, order, Arabic names, `active`): `{id, nameAr, nameEn, style, riwaya, source: qf|own, qfId, hasTimings, baseUrl, timingUrl, sampleUrl, sizeBytes}`. `qf` rows point at a Quran Foundation chapter reciter; each surah resolves through `GET /v1/content/reciters/:id/surahs/:n` → `{url, sizeBytes, durationMs, timings: [[startMs, endMs]…]}` (cached in KV per reciter/surah so downloaded files keep ayah sync offline); a full download also writes `GET …/:id/timings` as `timings.json`. `own` rows (future self-hosted audio) keep `<baseUrl>/<sss>.mp3`. Launch list (QF id): العفاسي (7) · عبد الباسط مرتّل (2) / مجوّد (1) · الحصري (6) · المنشاوي (9) · السديس (3) · الشريم (10) · الشاطري (4) · الدوسري (97) · الرفاعي (5). المعيقلي is not a QF chapter reciter — hidden until we host it.

**Acceptance** [ ] Full download resumable, Wi-Fi only unless overridden · [ ] Deleting frees storage shown in Profile.

---

### 5.15 `13 · Prayer times` — `/prayer` ✅

**Layout** Title «مواقيت الصلاة», sub «الإثنين 19 أكتوبر · الهيئة المصرية العامة للمساحة», location chip «القاهرة». Qibla card «اتجاه القبلة 136° · من الشمال باتجاه الجنوب الشرقي · البوصلة معايرة» (→ 14, label «افتح بوصلة القبلة»). List «مواقيت اليوم»: الفجر 5:30 · الشروق 6:56 · الظهر 12:40 · **العصر 3:55 «بعد 1:24:10»** (next highlighted, glass lapis rim) · المغرب 6:22 · العشاء 7:40. Each row has a bell toggle («تنبيه الفجر مفعل» etc.); الشروق default off. Swipe horizontally for previous/next day. Footer link → 15.

**Rules** Computed on-device (§6.4). Jumu'ah: Friday Dhuhr row reads «الجمعة». Bell toggle = per-prayer mode shortcut (adhan ↔ off; long-press → mode sheet).

**Acceptance** [ ] Matches the reference within ±1 min · [ ] Correct after travel (location change prompt «هل انتقلت إلى الإسكندرية؟ تحديث المواقيت»).

---

### 5.16 `14 · Qibla` — `/prayer/qibla` ✅

**Layout** Full-screen light. Back. Location «القاهرة · ≈ 1,280 km» to Makkah. Big compass: dial with N marker, Kaaba pointer at bearing, needle = device heading. Readout «القبلة على 136° من الشمال · اتجاهك N°». Guidance text: «استدر يميناً» / «استدر يساراً» / «أنت في اتجاه القبلة» (± 3°, gold ring + one light haptic). Buttons «معايرة البوصلة» (figure-8 animation sheet) · «عرض بالكاميرا» (phase 2 AR).

**Rules** Bearing: great-circle from user lat/lng to Kaaba (21.4225, 39.8262). Heading: `flutter_compass` (true north using magnetic declination from `geomag` model). Accuracy low → banner «البوصلة تحتاج معايرة». No location → city search. A11y label «بوصلة القبلة، الفرق N درجة».

**Acceptance** [ ] Bearing for Cairo = 136° ±1 · [ ] Haptic once on alignment, not repeatedly.

---

### 5.17 `15 · Adhan & notifications` — `/prayer/notifications` ✅

**Sections**
1. **تنبيه كل صلاة** — 6 rows, each a 3-state chip «أذان | تنبيه | صامت» (tap cycles; a11y «الفجر، الوضع الحالي أذان. المس للتغيير»). Defaults: fajr/dhuhr/asr/maghrib adhan, isha notify, sunrise silent.
2. **صوت الأذان** — radio: «أذان الحرم المكي · الأذان كاملاً» · «أذان المسجد النبوي» · «أذان هادئ» · «التكبير فقط · مناسب للعمل»; preview button «معاينة/إيقاف المعاينة». Fajr uses the Fajr variant of the chosen voice.
3. **التذكير قبل الأذان** — chips بدون · 5 · 10 · 15 · 20 د.
4. **تذكيرات أخرى** — switches: «أذكار الصباح · بعد الفجر بـ 30 دقيقة» · «أذكار المساء · بعد العصر» · «سورة الكهف · كل جمعة · 10:00 ص» · «الورد اليومي · إذا لم يكتمل قبل العشاء» · «مراجعة الحفظ · عند استحقاق سورة للمراجعة».
5. **التحدي والمكافآت والعروض** — «تقدم التحدي · الاستمرارية والأيام الفائتة» · «المكافآت المتاحة · عندما يكفي رصيدك لمكافأة» · «عروض متجر يقين · رسالة واحدة يومياً على الأكثر · بموافقتك» (these three mirror consent buckets `challenge_rewards` / `store_offers`).
6. **الساعات الهادئة** — «من بعد العشاء حتى الفجر · الأذان مستثنى» `21:00–5:00` (time range picker).
Footer: «تعمل التنبيهات دون اتصال بالإنترنت، وتُحسب المواقيت على جهازك وفق طريقة …».

**Rules** Every change → re-plan (§6.5). Section 5 toggles write consents (`source: settings`). Turning a worship row ON when OS permission is denied → sheet with «افتح الإعدادات».

**Acceptance** [ ] Plan respects iOS 64-pending limit (existing planner test) · [ ] Quiet hours never silence adhan.

---

### 5.18 `15·ب · Notification centre` — `/home/inbox` ✅

**Layout** Back, title «الإشعارات», settings icon (→ 15), action «قراءة الكل». Filter chips «الكل | العبادات | التحدي | العروض». Grouped «اليوم / أمس». Rows: icon tile · title · body · time · unread dot. Examples: «العصر بعد 10 دقائق / استعد للصلاة · 3:55 م» · «باقي يومان على 14 يوماً متتالية / أكمل ورد اليوم لتحافظ على استمراريتك» · «رصيدك يكفي لخصم 50 ج.م / استبدل 1,000 نقطة …» · «يوم الإثنين: صيام +30 نقطة / مهمة إضافية في تقويم اليقين» · «مراجعة الحفظ / سورة الهمزة مستحقة للمراجعة اليوم».
Empty: «لا إشعارات هنا» / «ستظهر هنا تذكيراتك وعروض المتجر».

**Rules** Local store (last 30 days, max 200). Local notifications write their entry when delivered (or at scheduled time if the app was open); push entries from FCM `data` payload. Tap → deep link (§4.2) + mark read; campaign pushes → `POST /v1/me/campaigns/:id/opened`.

---

### 5.19 `16 · Azkar counter` — `/home/azkar` ✅

**Layout** Back, title «أذكار الصباح», settings «الإعدادات: الاهتزاز والصوت». Tabs «نوع الأذكار»: الصباح · المساء · بعد الصلاة · النوم. Position «الذكر 3 من 12». **Counter card** (big glass, the whole card is the tap target): zikr text in Amiri «سُبْحَانَ اللهِ وَبِحَمْدِهِ», virtue + source «… · رواه مسلم», ring counter «37 / 100». Hint «اضغط في أي مكان على البطاقة للعدّ». When done: «تقبّل الله · انتقل للذكر التالي» (auto-advance after 0.8 s). List «باقي الأذكار» with per-item progress «1 / 1», «3 / 3», «0 / 7».

**Rules** Each tap: +1, light haptic (setting), optional soft click. Progress persisted per day per set locally. Completing the morning set ticks task `morning_azkar`; evening → `evening_azkar` (Outbox `POST /v1/challenge/tasks/:task/complete`). Content from reviewed content sync (§6.11) with bundled defaults; **every text needs a source line**.

**Acceptance** [ ] 10 taps/second registered without drops · [ ] Progress survives app kill · [ ] Volume buttons count (Android, optional setting).

---

### 5.20 `17 · Duas` — `/home/duas` ✅

**Layout** Title «الأدعية». **دعاء اليوم** card (gold glass): text, source «رواه البخاري», actions favourite + «مشاركة الدعاء». «الأقسام» grid with counts («3 أدعية», «دعاءان»): الهم والحزن · السفر · الطعام · النوم · المسجد · المفضلة («N محفوظ» / «لا يوجد بعد»). Category screen: title + list of cards (occasion «عند دخول المسجد», text, source, favourite «إضافة إلى المفضلة / إزالة من المفضلة», share).

**Rules** Dua of the day = deterministic by local date from the reviewed pool (`content_items.kind = dua`, `featured`). Favourites local. Share creates an image card (porcelain, text, source, mark).

---

### 5.21 `18 · Calendar of Yaqeen` — `/challenge/calendar` 🟡 (API ready)

**Layout** Back «رجوع إلى التحدي», title «تقويم اليقين». Journey strip «رحلة 365 يوماً»: «اليوم 47 من 365» · streak 12 · «3,240 نقطة» · «بدأت 21 ربيع الأول 1448 · 3 Sep 2026 · تنتهي ≈ 2 Sep 2027». Month header «جمادى الأولى 1448» + Gregorian span, prev/next. 7-column grid (سبت … جمعة, week starts Saturday): each cell Hijri day big + Gregorian small, status dot: **مكتمل** (lapis fill) · **جزئي** (lapis ring) · **قضاء** (gold) · **فائت** (slate hairline — never red) · اليوم (outlined) · قادم · «خارج الرحلة» (faded). Special-day pips: الأيام البيض, الجمعة, الإثنين/الخميس.
Selected-day sheet: date line, task list (الورد · أذكار الصباح · الصلوات · أذكار المساء · استماع · مهمة اليوم) with ticks, bonus line e.g. «الأيام البيض · مهمة صيام إضافية +30», score «مكتمل · 100 / جزئي · N / قضاء · 80 / اليوم · 55 / 100». CTA: missed within window → «قضاء هذا اليوم الآن · يحافظ على رحلتك»; today → «أكمل مهام اليوم». Footer «الهجري من تقويم أم القرى عبر AlAdhan · تعديل ±1 يوم من الإعدادات».

**Data** `GET /v1/calendar/hijri?from=&to=` (Hijri) + `GET /v1/challenge/days?from=&to=` (statuses) — merge client-side, or add `GET /v1/challenge/calendar?month=` (§8.2); qada through `POST /v1/challenge/tasks/:task/complete` with `date` (server enforces window and 80 cap).

**Acceptance** [ ] Hijri month boundaries match admin offset · [ ] Qada CTA hidden outside `qadaWindowDays` · [ ] No red anywhere.

---

### 5.22 `19 · 365 challenge` — `/challenge` 🟡 (v1 built)

**Layout** Title «365 يوم من اليقين» · calendar button. Hero (gold glass): «اليوم 47 من 365» ring · «3,240 نقطة» · stats «12 يوماً متتالياً» · «2 أيام قضاء». **مهام اليوم** «55 من 100» progress, task rows with points: «الورد اليومي · صفحتان +20» · «أذكار الصباح +10» · «الصلوات الخمس · خاص بك +25» · «أذكار المساء +…» · «استمع إلى سورة +…» (+ today's bonus task). Next milestone line (from `nextMilestone`). **مكافأة متجر يقين** card: «خصم 50 ج.م على طلبك · 1,000 نقطة لكل مكافأة» → «استبدل».

**Rules**
- Task rows come from `GET /v1/challenge/summary` → `tasks[]` (admin-configured rules; never hard-code labels/points).
- Auto tasks (wird, azkar, listen) tick themselves; manual ones (prayers `five_prayers`) tick by tap with **Rule**: «خاص بك» — prayer ticks are self-reported, stored for points only, never shown to admins per user.
- Optimistic tick → Outbox; on server reject (`day_closed`, `qada_window_passed`) revert with gentle toast.
- Milestone reached → celebration sheet (gold diamond shimmer, no confetti) «بارك الله فيك · 30 يوماً من اليقين +200».

**Acceptance** [ ] Double tap never double-awards (ref_key) · [ ] Works offline; syncs later with correct `date` · [ ] Guest sees join CTA.

---

### 5.23 `20 · Redeem reward` — `/challenge/redeem` 🟡 (v1 built)

**Flow** `choose → confirm → loading → success`.
- **choose**: «رصيدك الحالي 3,240 نقطة», list «اختر مكافأة»: «خصم 50 ج.م · على أي طلب من المتجر · 1,000» · «خصم 15% على سجاد الصلاة · السكينة الذهبية · القِبلة · عبق اليقين · 2,500» · «شحن مجاني · لطلب واحد داخل مصر». Status per row «متاح» or «ينقصك N». Note «النقاط تُكتسب من مهام التحدي اليومية. لكل كود استخدام واحد ولا يُستبدل نقداً.» CTA «استبدل».
- **confirm** sheet «تأكيد الاستبدال»: المكافأة · النقاط المخصومة «− 1,000» · الرصيد بعد الاستبدال · «تأكيد» / «إلغاء».
- **loading** «جارٍ إنشاء الكود…».
- **success** «بارك الله لك» · «هذا كود خصم 50 ج.م، صالح لاستخدام واحد في متجر يقين.» · code box with «نسخ/تم النسخ» · «يصلك الكود أيضاً على بريدك · صالح حتى [EXPIRY]» · «تسوّق الآن» (opens `STORE_URL/discount/<CODE>` so the code auto-applies) · «العودة إلى المكافآت».

**Rules** Online only. `POST /v1/rewards/:id/redeem` with idempotency key; errors mapped: `insufficient_points` «رصيدك لا يكفي بعد», `reward_out_of_stock` «نفدت هذه المكافأة», `user_reward_limit_reached` «وصلت للحد الشهري لهذه المكافأة», `shopify_unavailable` «المتجر غير متاح الآن، لم تُخصم نقاطك». Past codes listed in Profile › «أكوادي».

**Acceptance** [ ] Points never deducted when Shopify fails (existing API test) · [ ] Event `reward_redeem` sent only with ads consent.

---

### 5.24 `21 · Profile & settings` — `/profile` ✅

**Layout** Avatar initial «أ» · name «أحمد» · «مرتبط بحساب Google · مزامنة مفعّلة». Points card «رصيد النقاط 3,240» · «سجل النقاط» (ledger list: date, reason label, ±points) · «760 نقطة حتى المكافأة التالية». «مكافآت متجر يقين» row of reward cards + «زيارة المتجر». Settings list «الإعدادات»: «اللغة والمصحف · العربية · العثماني» · «مواقيت الصلاة والتنبيهات · الهيئة المصرية» · «الخصوصية والموافقات» (4 consent switches as on 04·ب) · «التنزيلات دون اتصال · 43 MB» · «أكوادي» · «عن يقين / الشروط / الخصوصية / تواصل معنا» · «تصدير بياناتي» · «حذف الحساب» · «تسجيل الخروج».

**Rules** Guest: header «ضيف» + «سجّل الدخول لحفظ نقاطك» (links guest → account, keeping points: `POST /v1/auth/link`, new §8.2). Delete account: 2-step confirm, `DELETE /v1/me` (PDPL, §6.17); local data wiped. Sign-out keeps on-device Quran data, wipes tokens and synced caches.

---

### 5.25 `22 · Hifz plan` — `/quran/hifz` ✅

**Layout** Back «رجوع إلى الفهرس», title «خطة الحفظ», «تعديل الخطة». Progress card: goal «جزء عمّ» · «N %» · «الختام ≈ date». **حفظ اليوم**: «سورة العاديات · الآيات 1–5», ayah text, steps checklist «استمع · 3 مرات» · «كرّر · 10 مرات» · «اختبر نفسك · بإخفاء الآيات», CTA «سمّع الآن لتثبيت الحفظ» (→ 10 with this range). **مراجعة اليوم**: due cards «سورة الهمزة · حُفظت قبل 9 أيام · آخر مراجعة قبل 4 أيام», tag «مستحقة اليوم / تحتاج تثبيت / غداً / بعد 3 أيام / بعد 14 يوماً»; rating «كيف كانت المراجعة؟» «صعبة · غداً | جيدة · N أيام | متقنة · N يوماً». Done: «اكتملت مراجعة اليوم». Heat strip «آخر 14 يوماً · 12 يوم حفظ ومراجعة».
Plan sheet «خطتي»: goals «جزء عمّ · 37 سورة · 564 آية» · «جزء تبارك · 11 سورة · 431 آية» · «سورة الكهف · 110 آيات» · «القرآن كاملاً · 6236 آية»; «مقدار الحفظ الجديد يومياً» stepper (N آيات يومياً) → finish estimate; «حفظ الخطة».

**Rules** Existing `ReviewScheduler` (first intervals 1 / 3 / 14 days by rating, then growing — §6.14). All hifz data **local only** (optional encrypted backup later). Due review → local notification (setting in 15).

---

### 5.26 `21·ب · Yaqeen card (بطاقة يقين)` — `/profile/card` ✅

An opt-in public card the user can put on an **NFC tag** or a **QR code**: their name, @handle, bio,
social links and — only if they switch it on — their Yaqeen level, streak, challenge day, streak
badges and member-since. It is also Yaqeen's front door for whoever scans it.

- **Public page** `GET /u/<handle>` (API-rendered, no scripts, `noindex`): glass card with a level ring
  around the initial, level chip, stats, gold badges, link pills, then an ink CTA «حمّل تطبيق يقين»
  (`/get-app` → Play / App Store) and «تسوّق من متجر يقين» (store, UTM `yaqeen_card/nfc/<handle>`).
  Themes **sky · gold · night**; Arabic/English by the visitor's browser. Missing/hidden cards show
  a friendly 404 that still invites to the app and the store.
- **Journey timeline** (switch «رحلتك», off by default): dated milestones, newest first — joined
  Yaqeen, started the 365-day journey, challenge days 30 · 100 · 200 · 300 · 365, each level reached
  (the day the running total of earned points crossed it), each streak badge. Neutral phrases only
  («اليوم 30 من رحلة 365», «وسام المواظبة · 7 أيام» — Arabic counted-noun agreement); never which
  prayers, azkar or tasks. The full private journey is on the **Profile tab** (`JourneySection`:
  level ring, lifetime points counting up, points to the next level, the rail; «الرحلة كاملة»).
- **Motion** (page): digits roll in, the level ring draws then a glint runs round it, badges spring,
  the timeline thread draws while its dots pop, links rise, the CTA has a slow sheen, sparkles
  twinkle; scroll-driven reveal where `animation-timeline` is supported. App: numbers count up, the
  rail draws itself, looks cross-fade. All of it off with reduced motion.
- **Levels** come from lifetime points (sum of positive ledger rows) — spending never lowers a level;
  names describe the journey: بداية الطريق · على الطريق · مواظب · ثابت · راسخ · منارة
  (0 · 500 · 2,000 · 5,000 · 12,000 · 25,000). No leaderboard, no change to points economics.
- **Physical tags — Yaqeen key medals and cards** (sold in the Yaqeen store; only the staff encoder
  below writes chips). Each piece carries a **permanent code** minted by marketing in admin batches (8 characters,
  no look-alikes, printed `XXXX-XXXX`): the NFC chip holds one NDEF URI record
  `<PUBLIC_PROFILE_BASE_URL>/t/<code>` and the same link is printed as a QR beside the code (the batch
  CSV gives code, printed code and URL per piece). `GET /t/<code>`: activated + card published → 302 to
  `/u/<current handle>` (handle changes never break a medal; scans counted, bots skipped); blank →
  «ميدالية يقين جديدة» page with the 3 activation steps, the code and «فعّلها في التطبيق»
  (`yaqeen://tag/<code>`) + «حمّل تطبيق يقين»; switched off / unknown / card hidden → the friendly 404.
  The buyer activates it once in the app (orb «ميدالياتي» → code field, the deep link pre-fills it, or
  **«قرّب الميدالية من الهاتف»**: the app reads the chip's NDEF URI record and accepts only our own
  link — https (or exactly the configured site), path exactly `/t/<code>`, no query, fragment or user
  info — then pre-fills the code; the user still taps «تفعيل». The button shows only when the phone has
  NFC and it is on; Android with NFC off shows «فعّل NFC من إعدادات الهاتف»; a stranger's tag gets a
  friendly «هذه ليست ميدالية يقين»);
  a code activates for one account only (≤ 10 per user, rate-limited, guests can't); a lost piece is
  switched off for good by its owner — never passed to a finder — and support can re-issue a returned
  one (audited). No `/t` universal link: scanners must always see the web card.
- **Admin runs the programme** (`/cards` «البطاقات العامة» + `/tags` «الميداليات والبطاقات»):
  - **Directory** of cards (public fields only: name, @handle, bio, published, opens, medals) with
    support actions, each audited with a reason: **moderate** (hidden; the owner can't republish —
    the app explains it), **restore**, **release handle** (moves the card to `yaqeen_xxxxxx`, frees
    the name — impersonation, trademarks).
  - **Settings** (marketing, `app_config.cards`): medal product link (the app's «get a medal»), the
    page's shop link (`/go/store`, UTM-tagged), the page CTA title/text in ar/en, extra reserved
    handles. Switches `features.publicCards` / `features.medalActivation` (Settings → المزايا) pause
    the pages + publishing, or activation, at once.
  - **Batches**: status ordered → received → on sale with a note; **void** a faulty run (every tag
    switched off, linked ones too); support can **link a blank tag to a customer** who can't activate.
  - **In-house encoding («ترميز بالهاتف»)** — so the owner can encode medals without the factory:
    on a batch row, marketing opens a **2-hour encoding session** (audited; revocable at once). Admin
    shows its link `yaqeen://encode/<token>` once, as a QR and as text. A staff phone opens it in the app
    (deep link only — no menu entry) on the **Encoding** screen: stage = batch + `YqRing` of encoded /
    working pieces + the next code; «قرّب شريحة فارغة من الهاتف» writes one NDEF URI record
    `<PUBLIC_PROFILE_BASE_URL>/t/<code>`, reads it back to verify (a factory-blank Android chip is
    formatted, then a second tap verifies), then reports it and moves to the next code. Optional
    «قفل الشريحة بعد الكتابة» (default **off**, permanent, with a warning). Pick any code in the list to
    re-encode it; «اختبار شريحة» reads a chip and says which code it carries. Errors say why: no NFC /
    NFC off, not NDEF (wrong chip type), locked, too small, write failed, didn't read back, no chip in
    time. When the session expires or is revoked the screen stops. The batch table shows «مُرمّزة x / y»
    and each tag its chip state (encoded, locked). The token is never stored by the app.
  - **Numbers** (aggregates only, `card_daily_stats`): card opens, medal scans, blank-medal page
    opens, «get the app» and «shop» clicks, publishes, activations per day + per-batch activation.
    No visitor, user or handle is stored; bots and link previews don't count.
- **App screen**: stage = live preview in the chosen look + live/hidden state; orbs = «ميدالياتي»
  (activate, list with scans, switch off, «اطلب ميدالية يقين من المتجر»), branded QR (share/copy), open count;
  editor = publish switch, name, handle (live availability, reserved names), bio (160), ≤ 8 links
  (https only), visibility switches with the note «عباداتك لا تظهر أبداً», look. Entry: Profile.
- **Privacy**: unpublished by default; never worship detail; guests can't publish; erasure request or
  suspension hides it at once; support can hide an abusive card (audited); only an open counter is
  kept. Deep links `yaqeen://card` → `/profile/card`, `yaqeen://tag/<code>` → `/profile/card?tag=<code>`,
  `yaqeen://encode/<token>` → `/encode/<token>` (staff encoder). NFC is read only on a tap, never at
  start-up; only our own `/t/<code>` links are accepted.
- **Acceptance** [x] nothing public until published · [x] only switched-on fields appear · [x] unsafe
  links never render · [x] journey shows only when switched on, newest first · [x] a blank medal explains activation; an activated one follows the handle; a switched-off one never resolves or re-activates · [x] holding a medal pre-fills only our own `/t/<code>` links and still asks to confirm · [x] staff encoding: session per batch, expiring + revocable + audited, token hashed at rest, writes + verifies + reports each chip, lock off by default · [x] works in ar/en.

### 5.27 `23 · Ramadan` — `/prayer/ramadan` ✅ · flag `ramadan`

**Purpose** The month's companion: when to stop eating and when to break the fast, and a private log of the month.

**When** Only while the admin flag is on **and** today's Hijri date (Umm al-Qura + Egypt offset + personal offset) is in Ramadan; in Sha'ban the screen and Home's band show «رمضان يقترب» with the days left once the calendar knows the first of Ramadan. Umm al-Qura's later Isha applies on Ramadan days only.

**Layout** Gold `YqStage`: «رمضان 1448», «اليوم N من رمضان · date»; the moment is the countdown to iftar (Fajr→Maghrib) or to the Fajr adhan (night), with «الإمساك HH:MM · الفجر HH:MM» (imsak = Fajr − 10 min, as printed on Egyptian imsakiyyas; never called the deadline). Orbs: today's fast (liquid fills Fajr→Maghrib; tap marks it), taraweeh (ring of nights), the khatma (ring of 30 juz; tap ticks the next). Then the imsakiyya (day · date · imsak · Fajr · Maghrib, today lifted, past days receded), the 30-juz khatma grid, a link to suhoor/iftar reminders, and «سجلّ رمضان يُحفظ على جهازك فقط». Home shows a gold band «رمضان · اليوم N» with the live countdown → this screen.

**Data** All on-device: prayer times from the engine, Ramadan days from the cached Hijri calendar, the log in `ramadan.log.<hijriYear>.v1`. Reminders: «السحور» N min before Fajr (15/30/45/60, default 45 — not muted by quiet hours) and «الإفطار قريب» N min before Maghrib (5/10/15/30, default 15), Ramadan days only, in Notification settings › رمضان.

**Bonuses** `ramadan_fast`, `taraweeh`, `ramadan_juz` — eligible only in Ramadan, seeded **disabled**; when the admin enables bonuses and one of these, ticking today's fast/taraweeh or a juz claims it (outbox, with the tick's date; a claim that syncs on a later day is refused `day_closed`). Un-ticking never takes points back. Voluntary-fast bonuses are never offered in Ramadan, on Eid al-Fitr or 10–13 Dhul-Hijjah.

**Acceptance**
- [x] Hidden with the flag off or outside Sha'ban/Ramadan; countdown rolls suhoor → fasting → evening; the last evening shows «العيد غداً».
- [x] Imsakiyya and log work offline; the log never leaves the device.
- [x] Reminders only on Ramadan days; ids never collide across days.

### 5.28 Home-screen widgets ✅

Android «NextPrayerWidget» and iOS «YaqeenWidget» (small, medium, lock-screen rectangular on iOS 16+): next prayer + time + live countdown, the Hijri (or Ramadan) line and place, today's wird progress; tap → Prayer. The app writes one snapshot after every re-plan (`yq.widget.v1`: a week of the five prayers, localised and formatted, Western digits) — the widgets never call the network and stay right for a week; then they show «افتح يقين لتحديث المواقيت». Android wakes itself at each prayer; iOS uses one timeline entry per prayer. Colours from tokens (generated `yq_tokens.xml` / `YqTokens.swift`), the mark from artwork. iOS needs the App Group `group.com.yaqinbrand.yaqeen` on both bundle ids.

### 5.29 Website ✅

Served by the API on the cards host: landing `/`, `/privacy`, `/terms`, `/support` (FAQ + contact), `/delete-account` (Play's deletion URL), `robots.txt` (cards and API excluded), `sitemap.xml`. Arabic first (`?lang=en`, or the browser's language), no scripts, works without the database. Legal text matches what the code does; owner-only facts stay bracketed until set. The app's privacy/terms/contact rows open these pages (`SITE_URL`). Store copy and privacy answers: `docs/STORE_LISTING.md`.

### 5.30 `24 · Khatma` — `/quran/khatma` ✅

**Purpose** Finish the mushaf on a plan, without guilt.

**Setup** «بحلول تاريخ» (7 · 15 · 30 · 60 days, or any date) or «صفحات يومياً» (2 · 4 · 5 · 10 · 20); start from the beginning or from the last page read; «اجعل حصّة الختمة وِردي اليومي» sets the wird goal to the daily portion (on by default). One plan at a time; edit keeps the pages already read.

**Screen** Gold stage: progress ring (% · «N من 604 صفحة»), due date and days left (or the projected finish at a fixed pace). «حصّة اليوم»: from the first unread page, today's target (what's left ÷ days left, today's pages included), a liquid orb of today's read/target, status «على الخطة · متقدّم N · متأخّر N — اقرأ أكثر قليلاً اليوم», «اقرأ الآن» → the reader on that page. «هذا الأسبوع»: seven bars, pages · minutes · reading days, streak. «ختمات سابقة». Edit / end plan (confirmed).

**Rules** A page counts once it has been visible ≥ 20 s (the wird rule), in any order; reading all 604 finishes the plan (toast «تمّت الختمة — تقبّل الله منك», moved to history). The routine's daily Quran reminder becomes «حصّتك من الختمة» while a plan runs (deep link `yaqeen://khatma`). The Quran index's khatma orb shows plan % and today's progress. Device only; stored as page ranges.

## 6. Cross-cutting functions

Each function: **what · where in code · rules · tests**. Pure logic goes in `domain/` (Dart) or
`services/api/src/domain` (TS) and needs unit tests.

### 6.1 Auth & session ✅ (OAuth credentials pending, §13)

- Providers `google | apple | guest` → `POST /v1/auth/sign-in {provider, idToken?, deviceId, displayName?}` → `{accessToken (15 min JWT), refreshToken (rotating, 60 d), user}`.
- `ApiClient` refreshes once on 401 (`POST /v1/auth/refresh`), then signs out locally on failure. Refresh reuse → server revokes the family (existing).
- **Guest**: a server user with `provider=guest` created on first online moment. Can tick tasks (kept locally + server) but **cannot redeem**; Profile and 05 prompt linking. **New** `POST /v1/auth/link {provider, idToken}` merges the guest into the real account (ledger rows re-pointed in one transaction, audited); if the identity already exists → keep the existing account, append guest points as `reason=grant, ref_key=merge:<guestId>`.
- Tokens in `SecureKvStore`; sign-out → `POST /v1/auth/sign-out`, wipe secure + synced caches.
- Tests: refresh-once, logout-on-refresh-fail, link merge (API, Postgres).

### 6.2 Onboarding persistence & settings ✅

- `OnboardingController` keeps step state; each step saves immediately (kill-safe). `onboarding.completedAt` set on 06 → event `onboarding_complete` (ad-gated).
- `SettingsRepository` = local source of truth (`KvStore`) + `PATCH /v1/me/settings` (Outbox when offline) for `locale, city, timezone, prayerMethod, asrSchool, hijriOffsetDays`.
- Device-only keys: `location{lat,lng}`, `quran.*`, `wird.*`, `adhan.*`, `reminders.*`, `quietHours`, `haptics`.

### 6.3 Consent ✅

- 5 buckets (table in 5.6). Local first; `PUT /v1/me/consents [{kind, granted, source}]` appends `consent_events` (who/when/source/app version) for PDPL.
- `Analytics` sends an `AdEvent` only when `ads_measurement` is granted; events before consent are queued for max 24 h then dropped (existing gate).
- Push marketing requires `store_offers` (offers) or `challenge_rewards` (challenge/rewards campaigns) — enforced server-side in the dispatcher (existing guardrails).

### 6.4 Prayer engine ✅

- Package `adhan_dart` (port of `adhan`) behind `PrayerTimesCalculator` interface in `features/prayer/domain`. Inputs: lat/lng, date, tz, method, asr, high-latitude rule (`twilightAngle` default), per-prayer minute adjustments (hidden advanced setting).
- Methods: Egyptian (default EG), MWL, Umm al-Qura (+30 min Isha in Ramadan per method), Karachi, ISNA, Dubai, Kuwait, Qatar, Singapore, Turkey.
- Output for any date offline; Home/13/15/notifications all read from it. Location change > 25 km → prompt to update.
- Tests: golden tables for Cairo, Alexandria, Aswan, Makkah, London (±1 min vs reference), Cairo DST transitions.

### 6.5 Notifications ✅ (re-plan on start, resume, settings, wird/hifz, and at local midnight while open; FCM credentials pending)

- **Local (worship)**: `NotificationPlanner` (pure, tested) produces the next N items; `LocalNotifier` implementation with `flutter_local_notifications` (+ `timezone`). Re-plan on: app start, settings change, location change, midnight, timezone change, after boot (Android `RECEIVE_BOOT_COMPLETED`). iOS: 64 pending limit → plan ~5 days of prayers first, then reminders.
- **Adhan audio**: custom sounds bundled (≤ 30 s on iOS — full adhan only on Android via a foreground playback service when `mode=adhan` + voice `full`). Android channels: `adhan`, `reminders`, `challenge`, `offers` (user can silence each in OS).
- Exact alarms: Android 12+ `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` justification = alarm-clock-like prayer alerts; fallback inexact if denied with note in 15.
- **Remote (marketing/challenge)**: FCM via `PushService`; server dispatcher applies guardrails (quiet hours, ±prayer windows computed from the user's city/method, Jumu'ah block 11:30–13:30 Fri, 1/day for offers). Tap → deep link.
- Inbox entries (5.18) for both.

### 6.6 Quran data ✅ (bundled JSON; licensed fonts/Indo-Pak pending)

- Bundled `assets/quran/quran.db` (SQLite): `surah(114)`, `ayah(6236: surah, ayah, page, juz, hizb, rub, text_uthmani, text_plain)`, `page(604 line layout)`, `juz`, `hizb`. Built by `tools/quran/build_db.py` (new) from licensed sources (§10) with a checksum test (6236 ayat, 604 pages, known hashes).
- Fonts: Amiri Quran bundled (OFL); KFGQPC page fonts as optional download pack after licence.
- Tafsir packs (التفسير الميسر first) downloadable `tafsir_<id>.db`; versioned via `GET /v1/content/packs` (new) → `{id, kind, version, url, sha256, sizeBytes}`; weekly background check.
- Tafsir from **Quran.com / Quran Foundation** (§10) when no pack has the ayah: `GET /v1/content/tafsirs` (curated: التفسير الميسر first, ابن كثير, السعدي, Ibn Kathir abridged English) and `GET /v1/content/tafsirs/:id/surahs/:n` → `{tafsirId, surah, attribution, ayat: {"s:a": plain text}}` (HTML and footnotes stripped server-side; a commentary covering several ayat sits on the first — the app shows it for the following ayat too), `GET …/:id/by-ayah/:key`. The app caches each surah on disk (`<files>/tafsir/<id>/<surah>.json`), refreshes copies older than 7 days when online, reads older copies offline, and shows the bracketed placeholder only when offline with nothing cached. Picker chips in the ayah sheet's tafsir panel (device-only choice, `tafsir.selected`). Every display credits the source («المصدر: Quran.com · Quran Foundation», or the QuranEnc line for the pack).
- Bookmarks/lastRead/wird in local `user.db` (drift).

### 6.7 Audio ✅ (Quran.com / Quran Foundation, §10)

- `just_audio` + `audio_service` + `background_downloader`. Per reciter: surah MP3s + `timings.json` (ayah start/end ms). QF audio streams/downloads straight from their CDN (`download.quranicaudio.com`); the URL + timings come from our API (the app never holds QF credentials).
- Player state persisted (surah, ayah, position, reciter, speed, repeat). Lock-screen metadata: surah name, reciter, mark artwork.
- Downloads: queue, pause/resume, Wi-Fi only default, storage accounting. Delete reclaims.

### 6.8 Recitation check (R&D) 🟡 (engine interface + aligner; model pending) · flag `recite`

- Interface `RecitationEngine { start(expectedAyat); Stream<WordResult>; stop() }`. Implementation candidate: on-device Whisper-small fine-tuned on Quran recitation (e.g. Tarteel-style open models) via `whisper.cpp`/ONNX; model ~150 MB downloaded on demand.
- Alignment: normalise both sides (strip tashkeel for matching), Levenshtein on words, mark `ok / warn / skipped`. Show only «تنبيه», never claim tajweed judgment in v1.
- Privacy: audio in memory only; no upload. Opt-in "help improve" upload is **out of scope** until a separate consent exists.
- Ship gate: ≥ 90 % word accuracy on a 50-reciter internal test set; otherwise keep flag off.

### 6.9 Challenge engine ✅

- Server rules (existing, tested): day = sum of active task points (`dailyTotal`, default 100); qada day capped at `qadaDayPoints` (80) within `qadaWindowDays` (7); bonuses per `bonus_rules`; milestones from `streak_milestones`; idempotent by `ref_key = task:<user>:<date>:<task>`.
- Mobile: `ChallengeRepository` optimistic ticks → Outbox (`clientEventId`) → reconcile with `ChallengeSummary`. "Today" uses the user's timezone; ticks made offline carry their local `date`.
- Streak: consecutive days with ≥ 1 completion (or qada'd). Missed day never resets copy to zero publicly — show «ابدأ من جديد، والقضاء متاح» gently.
- Auto-tick sources: wird (reader), azkar (16), listen (11). Manual: five_prayers, daily_task.

### 6.10 Hijri calendar ✅ (API)

- `GET /v1/calendar/hijri` returns Umm al-Qura (AlAdhan source, cached server-side) with the admin offset (`hijri_adjustments`, region EG) and effective date. App caches 3 months; user may add personal ±1 (`hijriOffsetDays`).
- Special days (white days 13–15, Mon/Thu, Friday, Ramadan, Eids, Arafah, Ashura) computed from the Hijri date → bonus pips and optional reminders.

### 6.11 Religious content sync ✅

- `GET /v1/content?type=dua|zikr&since=` returns only `published` items (reviewer ≠ author, existing). App stores in local DB; bundled seed for first launch offline.
- Each item: `text, source (hadith ref), virtue?, repeat count, category, order, featured`. Rendering always shows the source line.
- `GET /v1/daily-task` → today's «مهمة اليوم» (published only).

### 6.12 Rewards & redemption ✅

- Catalogue `GET /v1/rewards` (+ balance). Redeem `POST /v1/rewards/:id/redeem` → Shopify `discountCodeBasicCreate` / `discountCodeFreeShippingCreate`, single use, `validityDays`, ledger debit in the same transaction as the redemption row; Shopify failure → no debit.
- Limits: stock, `perUserMonthlyLimit`. Codes list `GET /v1/me/redemptions`. Store link `STORE_URL/discount/<code>?redirect=/collections/all` + UTM `utm_source=yaqeen_app`; event `store_click`.
- Phase 2: Shopify order webhook → mark redemption `used`, ad event `purchase` (server-side CAPI only with consent).

### 6.13 Profile, sync & backup ✅

- Synced to server: account, settings (non-location), consents, challenge, ledger, redemptions.
- **Device first**: reading history, bookmarks, notes/highlights, khatma, hifz, azkar counts, dua favourites, listen state, routine, Ramadan log, Home tasbeeh. **Never synced**: location/coordinates, downloads, caches.
- **Opt-in cloud backup «نسخ احتياطي سحابي»** (owner decision, 2026-10): Profile › Privacy switch, **off by default**, signed-in (non-guest) accounts only; a consent of its own (`cloud_backup`, history-tracked). When on, each device-first kind above is kept as one document per kind (`BACKUP_KINDS`) in `user_backups`, sealed with AES-256-GCM under `BACKUP_SECRETS_KEY` (server-held key — not end-to-end), so it comes back on a new phone or a reinstall. The app pulls and merges after the first frame and after sign-in (time-boxed), uploads ~5 s after a change (playback position 2 min), merges and retries once on 409, and keeps changes on the phone while offline — no screen ever waits on it. Merge per kind: union by id with three-way deletes for bookmarks, notes, highlights, favourites, khatma history and Ramadan days; max per day for counters (reading stats, today's azkar counts, listening time, wird pages); last-writer-wins for scalar state (last page by its own time, khatma plan, hifz plan, routine slots, reciter/position, tasbeeh). Shows "last backed up …" and «انسخ الآن»; guests see it disabled ("sign in to enable"); turning it off asks first and deletes the server copy (the phone keeps everything). First sign-in on a new phone with an existing backup offers «استعادة / ليس الآن» once per account. Never visible to admins, never in analytics or ads, included in the user's export, deleted on erasure. API: `docs/API.md` › Cloud backup.

### 6.14 Hifz ✅

- `ReviewScheduler` (existing, `features/hifz/domain`): `hard → 1 d` · `good → max(3, previous×2)` · `easy → max(14, previous×2.5)`, capped at 120 d; new portions per plan rate. Plan estimate = remaining ayat ÷ rate.
- Recitation results (6.8) suggest a rating; the user confirms.

### 6.15 Remote config, maintenance, min-version ✅ (API)

- `GET /v1/config` (cached 1 h, ETag): `features`, `minVersion`, `maintenance`, `splashVerse`, `hijri`, `points`.
- App: version < `minVersion` → blocking sheet «يتوفر إصدار أحدث من يقين» + store button; `maintenance.enabled` → full screen with message, local features still reachable via «متابعة دون اتصال». Feature flag false → hide entry points entirely.
- Flags used by the app: `challenge, rewards, hifz, listen, bonuses, recite, ramadan, tafsirFull` (add the last three to defaults, §8.2).

### 6.16 Offline outbox ✅

- Persistent FIFO; each item `{id, clientEventId, method, path, body, createdAt, attempts}`; flush on connectivity, app resume and every 15 min while foreground; exponential backoff; 4xx (except 401/408/429) dropped with log; order preserved per path.
- UI: «حُفظ وسيُزامَن عند الاتصال» toast; Profile shows pending count if > 0.

### 6.17 Privacy & PDPL ✅ (API)

- `GET /v1/me/export` (JSON of account, settings, consents + events, ledger, redemptions). `DELETE /v1/me` → status `deletion_requested`, tokens revoked, hard delete after 30 days by job (ledger anonymised to keep accounting).
- Admin worship analytics are aggregates with k-anonymity ≥ 20.

### 6.18 i18n & formatting ✅

- `flutter gen-l10n`, ARB per screen prefix (`home_*`, `quran_*`…). `YqFormat.number/time/date` (Western digits, `ar-EG-u-nu-latn`, 12-hour «م/ص» in Arabic). English: same layouts mirrored LTR; Quran text stays RTL.

### 6.19 Analytics (product) ✅ (server-side DAU / challenge stats)

- Two separate pipes: **AdEvent** (9 events, consent-gated → Firebase/Meta/TikTok SDKs) and **product metrics** computed **server-side from first-party data** (DAU from authenticated requests, challenge stats from ledger). No third-party product analytics SDK on worship screens.

### 6.20 Deep links ✅ (map) · 🟡 (universal links: AASA + assetlinks on the store theme)

- `routeForDeepLink` → update to the new sub-routes (calendar → `/challenge/calendar`, azkar → `/home/azkar`, hifz → `/quran/hifz`, redeem → `/challenge/redeem`). iOS Associated Domains + Android App Links for `yaqin-brand.com/app/*` (`apple-app-site-association`, `assetlinks.json` hosted by the store theme).

### 6.21 Quality, crash & performance ✅ (Sentry once DSNs are set)

- Crash/error reporting: **Sentry** for the app (`ErrorReporter`, started after the first frame; boot errors buffered), API + cron jobs and admin — no user, no request bodies/URLs/query strings, no navigation, tap or HTTP breadcrumbs, no screenshots; obfuscated builds symbolicated from CI-uploaded symbols. Product analytics «تحسين التطبيق»: §11.2 and docs/ANALYTICS_EVENTS.md. Performance budget: cold start < 2 s to splash, Home interactive < 1 s after splash, APK < 60 MB (without audio), memory < 250 MB in reader.

---

## 7. Admin dashboard (`apps/admin`)

Arabic RTL, Next.js 15 App Router, server actions → `/admin/*` API with the admin JWT (TOTP-protected login).
Layout: right sidebar (horizontal navy lockup, 6 items, user chip) + porcelain content. Cards = white, 24 radius, hairline.
Every write shows a toast and is written to `audit_log` in the same transaction (existing).

### 7.1 Roles (existing RBAC)

| Role | Can |
| --- | --- |
| `super_admin` «مدير عام» | everything incl. team, settings |
| `content_editor` «محرر محتوى» | create/edit content, daily tasks; submit for review |
| `religious_reviewer` «مراجع شرعي» | approve/request changes (not own items); approve splash verse |
| `marketing` «تسويق» | campaigns, reward catalogue (not points economics) |
| `support` «دعم» | users list, ledger view, manual adjustments with reason, export |

### 7.2 Screens — built vs design

| Screen | Route | Built | Gaps to build (design → code) |
| --- | --- | --- | --- |
| 01 · Overview | `/` | KPIs, attention list, recent campaigns | **DAU line chart (30 d, Friday peaks annotation)** · **challenge funnel** (joined → 7 → 30 → 100 days) · **today's adherence bars** (wird / morning azkar / prayers logged — aggregates, k ≥ 20) · range selector 7d/30d/90d · alerts: pending review count, tomorrow's daily task missing, low reward stock, expected moon sighting |
| 02 · Users | `/users`, `/users/[id]` | list, search, status filter, detail, ledger, manual points (reason required), suspend/reactivate | **«تصدير بيانات المستخدم»** button (calls `GET /admin/users/:id/export`, new) · status chip «طلب حذف» with countdown |
| 03 · Content | `/content` | duas/azkar editor, submit/review workflow, daily-task schedule | role-preview toggle «تعرض كـ» (dev only) · English translation field · history line «آخر تعديل» |
| 04 · Campaigns | `/campaigns`, `/campaigns/new` | kind, segment, timing (now/smart/scheduled), guardrails list, reach estimate, lock-screen preview, cancel, stats | **«إرسال تجريبي لجهازي»** (`POST /admin/campaigns/test`, new: sends to the admin's registered test devices only, bypasses audience but not content validation) · deep-link target select (rewards / challenge / calendar / store) · open-rate column |
| 05 · Rewards | `/rewards` (5 tabs) | program & tasks (sum = dailyTotal), milestones & bonuses, catalogue, grants (preview → confirm), redemptions | **Shopify connection status pill** «متصل · yaqin-brand.com» (`GET /admin/rewards/shopify/status`, new) · "+ مكافأة من منتجات Shopify" product/collection picker (`GET /admin/rewards/shopify/collections`, new) · KPI row (granted / redeemed / used rate / sales from codes) |
| 06 · Settings | `/settings` | Hijri offset preview/apply, feature flags, min versions, maintenance, team, audit | **Splash verse editor** (text + reference; save creates a `pending_review` change; goes live only after a reviewer approves — reuse content workflow with `type=splash_verse`) · flag set aligned to app: `recite` (with % rollout), `hifz`, `rewards`, `ramadan`, `tafsirFull`, `challenge`, `listen`, `bonuses` |

### 7.3 Admin acceptance (all screens)

- [ ] No per-user worship data anywhere (only day number, points, redemptions).
- [ ] Every mutation audited with actor, before/after JSON.
- [ ] Forms are controlled (React 19 resets uncontrolled forms after actions).
- [ ] Arabic numerals Western, dates «الثلاثاء 20 أكتوبر 2026 · 9 جمادى الأولى 1448».
- [ ] Works at 1280 px and collapses sidebar at < 1024 px.

---

## 8. API (`services/api`)

### 8.1 Existing endpoints (✅ tested)

**Public** (`/v1`, bearer JWT except auth/config)

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/v1/auth/sign-in` · `/refresh` · `/sign-out` | Google/Apple/guest sessions |
| GET | `/v1/me` | profile + settings + balance |
| PATCH | `/v1/me/settings` | locale, city, timezone, method, asr, hijri offset |
| GET/PUT | `/v1/me/consents` | 5 buckets + event log |
| POST | `/v1/me/events` | consented product events (closed list, no account link) |
| POST | `/v1/me/devices` | FCM token, platform, app version, locale |
| GET | `/v1/me/redemptions` · `/v1/me/ledger` | codes, points history |
| GET | `/v1/me/export` · DELETE `/v1/me` | PDPL |
| GET | `/v1/config` | remote config |
| GET | `/v1/calendar/hijri` | Hijri days with Egypt offset |
| GET | `/v1/content` · `/v1/daily-task` | published duas/azkar, today's task |
| POST | `/v1/challenge/enroll` | join |
| GET | `/v1/challenge/summary` · `/v1/challenge/days` | today, tasks, streak, balance, milestones · day statuses |
| POST | `/v1/challenge/tasks/:task/complete` | `{date?, clientEventId}` (qada if past date) |
| POST | `/v1/challenge/bonuses/:kind/claim` | white days / Mon-Thu / Friday Kahf |
| GET | `/v1/rewards` · POST `/v1/rewards/:id/redeem` | catalogue + balance · Shopify code |

**Admin** (`/admin`) — `auth` (login, me) · `overview` · `users` (list, detail, `:id/points`, `:id/status`) · `content` (CRUD, submit, review, daily-tasks) · `campaigns` (list, preview, create, cancel, stats) · `rewards` (program, milestones, bonus-rules, grants + preview, catalogue, redemptions) · `settings` (config, hijri preview/apply, audit, team).

### 8.2 New endpoints needed

| Method | Path | For | Notes |
| --- | --- | --- | --- |
| POST | `/v1/auth/link` | 5.24 guest → account | merge in one tx, audited |
| POST | `/v1/me/campaigns/:id/opened` | 5.18 | idempotent; feeds open-rate |
| GET | `/v1/challenge/calendar?month=YYYY-MM` | 5.21 | optional convenience: Hijri + statuses + bonuses merged |
| GET | `/v1/content/reciters` | 5.14 | licensed catalogue |
| GET | `/v1/content/packs` | 6.6 | tafsir/font/audio packs with sha256 |
| GET | `/admin/overview/series?metric=dau&range=30d` | 7.2 overview chart | aggregates only |
| GET | `/admin/overview/funnel` · `/admin/overview/adherence` | overview | k-anonymity ≥ 20 |
| GET | `/admin/users/:id/export` | users | same payload as `/v1/me/export`, audited |
| POST | `/admin/campaigns/test` | campaigns | admin test devices only |
| GET | `/admin/rewards/shopify/status` · `/shopify/collections` | rewards | shop name, scopes, last error |
| PUT | `/admin/settings/splash-verse` | settings | creates pending change → reviewer approves |

**Contract changes**: `RemoteConfig.points` add `dailyTotal` (used by 05); `features` defaults add `recite:false, ramadan:false, tafsirFull:false`; `recite` rollout `%` → `featureRollout: Record<string, number>` with stable bucketing by user id hash.

### 8.3 Conventions

Errors `{error: {code, message}}` with stable snake_case codes (`insufficient_points`, `day_closed`, `qada_window_passed`, `reward_out_of_stock`, `user_reward_limit_reached`, `shopify_unavailable`, `forbidden`, `validation_failed`). Idempotency via `clientEventId`/`Idempotency-Key`. Rate limits: auth 10/min/IP, redeem 5/min/user. All times UTC in DB; "today" from the user's timezone.

---

## 9. Data model

### 9.1 Server (Postgres, existing)

`users · auth_identities · refresh_tokens · devices · consents · consent_events · challenge_enrollments · task_rules · streak_milestones · point_grants · bonus_rules · task_completions · points_ledger (append-only, unique ref_key) · daily_tasks · rewards · redemptions · content_items · campaigns · campaign_deliveries · app_config · hijri_adjustments · admin_users · audit_log`.

### 9.2 Server additions

| Change | Why |
| --- | --- |
| `campaign_deliveries.opened_at` | open tracking (8.2) |
| `content_type` enum + `splash_verse` | reviewed splash verse |
| `reciters`, `content_packs` tables | catalogue + packs (8.2) |
| `admin_users.test_device_ids text[]` | campaign test send |
| `users.merged_into uuid null` | guest link |
| materialised view `daily_active_agg(date, dau)` + `challenge_funnel_agg` | overview charts without row-level worship access |

### 9.3 On-device stores

| Store | Tech | Contents |
| --- | --- | --- |
| `KvStore` (Prefs) | shared_preferences | settings, flags cache, onboarding, consents mirror |
| `SecureKvStore` | flutter_secure_storage | tokens |
| `quran.db` | SQLite (bundled, read-only) | text, pages, juz, hizb |
| `user.db` | drift | bookmarks, lastRead, wird log, azkar progress, hifz plan + review states, inbox, outbox, content cache |
| Files | app support dir | tafsir packs, audio, recitation model |

---

## 10. Content sources & licensing (decisions before launch)

| Content | Candidate source | Licence / action | Status |
| --- | --- | --- | --- |
| Quran text (Uthmani, Hafs) | **Tanzil.net** Uthmani text + metadata (pages, juz, hizb) | Free with attribution; text must not be modified; include Tanzil notice in «عن يقين» | Decide |
| Mushaf page fonts | **KFGQPC** (King Fahd Complex) QCF v2 page fonts | Request written permission from KFGQPC | Request |
| Fallback Quran font | Amiri Quran | OFL — bundled | ✅ |
| Indo-Pak script | Tanzil / IndoPak text + font | Check licence; else ship «قريباً» | Decide |
| Tafsir | **Quran.com / Quran Foundation Content API v4** (owner decision 2026-10): التفسير الميسر (QF 16), ابن كثير (14), السعدي (91), Ibn Kathir abridged EN (169) — and the التفسير الميسر pack via **QuranEnc.com** when installed | QF Developer Terms: display unaltered inside the app only (no redistribution as data), credit Quran Foundation, cache QF content ≤ 1 week unless obtained via Content Sync (server cache 24 h; device copies refreshed weekly). QuranEnc pack terms as before (credit QuranEnc.com + version) | ✅ QF via API · pack optional |
| English translation | Saheeh International | Licence from publisher | Request |
| Recitation audio + timings | **Quran.com / Quran Foundation** chapter recitations (`/chapter_recitations/{id}/{surah}?segments=true`, audio on `download.quranicaudio.com`) — curated in the `reciters` table | Same QF terms (credit, no redistribution; not re-hosted on our CDN). Server: OAuth2 client_credentials (`QF_CLIENT_ID`/`QF_CLIENT_SECRET`); until those are issued the legacy public `api.quran.com/api/v4` is used. Offline downloads: confirm with QF that full-surah downloads are covered (else move offline copies to Content Sync) | ✅ (credentials pending) |
| Adhan audio | Licensed recordings (Makkah, Madinah, calm, takbir) | Buy/licence; ≤ 30 s cuts for iOS | Buy |
| Azkar & duas | Hisn al-Muslim references (text is classical; translations need licence) | Every item reviewed by `religious_reviewer`; show hadith source | In admin |
| Hijri | Umm al-Qura via AlAdhan API + admin Egypt offset | Free API; cache server-side | ✅ |
| Recitation ASR model | Open Quran ASR models (check licence for commercial use) | Legal review | R&D |

**Rule**: until a source is cleared, the UI shows the bracketed placeholder, e.g. `[نص التفسير الميسر لهذه الآية من مصدر المحتوى المرخّص]`. Never generate religious text.

---

## 11. Analytics & notifications summary

### 11.1 Ad events (only these, only with `ads_measurement`)

`first_open · sign_up · onboarding_complete · challenge_join · streak_7 · streak_30 · reward_redeem · store_click · purchase` (contracts `AD_EVENTS`). Params: none that describe worship (no surah, prayer, azkar).

### 11.2 Notification catalogue

| Id | Type | Trigger | Default | Bucket |
| --- | --- | --- | --- | --- |
| `adhan.<prayer>` | local | prayer time | per 5.17 | worship_reminders |
| `pre.<prayer>` | local | N min before | 10 min | worship_reminders |
| `azkar.morning` / `.evening` | local | Fajr+30 / after Asr | on | worship_reminders |
| `kahf.friday` | local | Fri 10:00 | on | worship_reminders |
| `wird.missing` | local | before Isha if goal unmet | off | worship_reminders |
| `hifz.due` | local | review due, 09:00 | on | worship_reminders |
| `challenge.streak` / `.qada` | push (smart) | streak about to break / missed yesterday | on | challenge_rewards |
| `rewards.enough` | push (smart) | balance ≥ cheapest reward | on | challenge_rewards |
| `offers.*` | push campaign | admin | off | store_offers |

Copy tone: invitations, never guilt («دقائق من السكينة قبل المغرب», not «لقد فاتك»).

---

## 12. Build plan

Milestones are sequential; tickets inside a milestone can run in parallel. Each ticket = one PR with tests.
IDs are referenced in commits (`YQ-12: …`).

### M0 — Foundations (1 week)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-01 | Missing core widgets: `YqButton, YqListRow, YqSection, YqEmptyState, YqErrorState, YqOfflineBanner, YqSheet, YqChip, YqStepper, YqCountdown, YqToast` + widget tests + gallery screen (debug only) | §2.4 | goldens RTL+LTR |
| YQ-02 | ARB scaffolding per feature; move all existing strings | §6.18 | no hard-coded UI text (lint) |
| YQ-03 | Router: add all routes in §4.1, full-screen routes, updated deep-link map | §4 | deep-link tests updated |
| YQ-04 | `user.db` (drift) + migrations; `SettingsRepository` | §6.2, §9.3 | migration test |
| YQ-05 | Remote config client: flags, min-version sheet, maintenance screen; contract changes in §8.2 | §6.15 | flag off hides entry points |

### M1 — Onboarding & auth (1 week)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-10 | Sign in (Google, Apple, guest) + `AuthRepository` wiring | 5.3, 6.1 | guest offline path |
| YQ-11 | Language & mushaf step | 5.4 | |
| YQ-12 | Prayer setup step + city search (offline list) | 5.5 | location denied path |
| YQ-13 | Consent step + OS permission + ATT sequencing | 5.6 | consent events with source |
| YQ-14 | Goal & challenge step (enroll / guest sheet) | 5.7 | values from config |
| YQ-15 | Offline mushaf step + download manager skeleton | 5.8, 6.6 | resume |
| YQ-16 | API `POST /v1/auth/link` | 6.1 | Postgres test |

### M2 — Prayer (1–1.5 weeks)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-20 | `PrayerTimesCalculator` + golden tests | 6.4 | ±1 min |
| YQ-21 | Prayer times screen | 5.15 | |
| YQ-22 | Qibla compass | 5.16 | Cairo 136° |
| YQ-23 | `LocalNotifier` + channels + exact alarms + boot re-plan | 6.5 | planner integration test |
| YQ-24 | Adhan & notifications screen | 5.17 | |
| YQ-25 | Inbox store + screen; `POST /v1/me/campaigns/:id/opened` | 5.18 | |

### M3 — Quran (2–3 weeks)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-30 | `tools/quran/build_db.py` + bundled `quran.db` + checksum test | 6.6, §10 | 6236 / 604 |
| YQ-31 | Quran index + search normalisation | 5.10 | < 50 ms |
| YQ-32 | Reading mode: page renderer, themes, chrome, settings sheet, lock | 5.11 | 60 fps |
| YQ-33 | Ayah actions: bookmark, copy, share card, tafsir panel | 5.11 | |
| YQ-34 | Wird tracking + challenge auto-tick | 5.11, 6.9 | once per day |
| YQ-35 | Audio engine + Now playing + timings sync | 5.13, 6.7 | background |
| YQ-36 | Reciters catalogue + downloads; `GET /v1/content/reciters`, `/packs` | 5.14 | resumable |

### M4 — Worship & challenge (1.5 weeks)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-40 | Content sync + local cache + bundled seed | 6.11 | offline first launch |
| YQ-41 | Azkar counter | 5.19 | 10 taps/s |
| YQ-42 | Duas + dua of the day + share | 5.20 | |
| YQ-43 | Home wired to real data (all blocks) | 5.9 | countdown/DST |
| YQ-44 | Challenge screen v2 (tasks from summary, milestones sheet) | 5.22 | no double award |
| YQ-45 | Calendar screen (+ optional merged endpoint) | 5.21 | qada window |
| YQ-46 | Redeem v2 error mapping + «أكوادي» | 5.23 | no debit on failure |

### M5 — Profile, Hifz, admin gaps (1.5 weeks)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-50 | Profile & settings, privacy screen, export, delete | 5.24, 6.17 | PDPL flows |
| YQ-51 | Hifz UI on `ReviewScheduler` | 5.25 | |
| YQ-52 | Admin overview charts + aggregates endpoints | 7.2 | k ≥ 20 |
| YQ-53 | Admin campaign test send + open rate | 7.2 | |
| YQ-54 | Admin Shopify status + collection picker | 7.2 | |
| YQ-55 | Admin splash-verse editor with review | 7.2 | reviewer gate |
| YQ-56 | Admin user export | 7.2 | audited |

### M6 — Hardening & launch (1–2 weeks)

| ID | Ticket | Spec | Acceptance |
| --- | --- | --- | --- |
| YQ-60 | Brand fonts (ZEYADA, Canela) when licensed; update `pubspec.yaml` | §2.2 | |
| YQ-61 | Sentry crash/error reporting, performance budget checks | 6.21 | budgets met |
| YQ-62 | Universal links + store files | 6.20 | |
| YQ-63 | Accessibility pass (VoiceOver/TalkBack, 200 % text) | §1.2 | checklist |
| YQ-64 | Store listings, privacy labels (iOS) / data safety (Android) matching §6.13 | — | |
| YQ-65 | Beta (TestFlight / Play internal) with 50 users; fix list | — | |

### Later (flagged)

`recite` (YQ-70, 6.8) · ~~Ramadan mode with imsakiyya + Ramadan challenge (YQ-71)~~ ✅ §5.27 · full-screen tafsir (YQ-72) · encrypted backup (YQ-73) · Shopify order webhook ✅ (codes marked `used`; server-side `purchase` to ad platforms still needs a decision) (YQ-74) · AR Qibla (YQ-75) · Indo-Pak script (YQ-76).

---

## 13. Open decisions (owner: product)

1. Quran text + fonts + tafsir licences (§10) — blocks M3 release, not development.
2. Reciters list for launch (licences) — default العفاسي.
3. Adhan recordings purchase.
4. Guest points: allow ticks before sign-in (current spec: yes, merged on link) — confirm.
5. `recite` model choice and accuracy gate.
6. Brand fonts licences (ZEYADA Arabic 1, Canela Text) — app uses Amiri/Tajawal until then.
7. Reward catalogue at launch (50 ج.م / 15 % rugs / free shipping / package) and monthly budget.
8. Ramadan 1448 (≈ Feb 2027): mode built (§5.27); decide the Ramadan bonus values and switch them on, and turn the `ramadan` flag on in Sha'ban.

---

## 14. QA & definition of done

**Per ticket**
- Acceptance checklist in the spec passes; screenshots (RTL, LTR, dark mushaf where relevant) attached to the PR.
- Unit tests for every **Rule**; widget tests for states (loading/empty/error/offline).
- `pnpm typecheck && pnpm test`, admin build, `flutter analyze && flutter test` green.

**Release checklist**
- [ ] Airplane mode: Quran, prayer times, Qibla, azkar, duas, hifz, challenge ticks all work; ticks sync later.
- [ ] Notifications fire on time after reboot, timezone change and DST (Egypt last Friday of April / October).
- [ ] Network inspector: zero worship data to any third party; ad SDK calls only after consent.
- [ ] Redemption: success, insufficient, out of stock, monthly limit, Shopify down.
- [ ] Admin: reviewer ≠ author enforced; every write audited; no per-user worship view.
- [ ] Accessibility: all icons labelled, 44 pt targets, reduce-motion, 200 % text on non-mushaf text.
- [ ] Brand: logo from artwork only, tokens only, porcelain backgrounds, no ornament, Western digits.

---

*End of spec. When a screen or function changes, update its section and the status board (§5.1) in the same PR.*
