# onboarding

**Screens (design canvas):** Splash → Welcome → Language → Location → Consent → Goal → Routine → Your profile → Download (canvas row "First run").

**Built:** `data/` auth and consent repositories · `presentation/` splash (+ gate), welcome, language, prayer (location + method), consent, goal, routine, profile (05·ج «ملفّك», `profile_step.dart`) and download steps, the sign-in sheet and the session controller.

**Order and resume:** `onboardingRoutes` in `splash_gate.dart` is the order. Every step moves on with `advanceOnboarding(context, ref, route)`, which saves `AppSettings.onboardingRoute` (and its index in `onboardingStep`) before going; the splash resumes by that route name. Settings saved before the profile step existed have only the index, read through the frozen `legacyOnboardingRoutesV1` (an old step 6 still resumes at download). Never edit the v1 list; add new steps to `onboardingRoutes` only. Back (chevron and system back) goes to the previous route, never to Home.

**Rules:**
- Consent screen writes the 4 buckets with source=onboarding. ads_measurement defaults OFF; on iOS request ATT only after the user opts in.
- 05·ج «ملفّك»: picture (photo when a picker exists, or one of the 16 presets) and name are saved on the phone first (`meProfileProvider`; guests stay local until they link an account, then `SessionController._afterSignIn` calls `pushAfterSignIn` before any other network call; until it lands, `profile.dirty.v1` keeps the guest's name and picture on top of any refresh, so a screen refreshing the profile meanwhile never loses them). The preview is always level 1 «بداية الطريق» with an empty ring. The name prefills the account's **first name only**, also when a guest signs in from the league switch (unless they typed); joining needs a non-empty name. The weekly-league switch is off by default, hidden when the `leagues` flag is off, asks guests to sign in, needs the age attestation, and joins with a **direct** `PUT /v1/me/community` (source `onboarding`); a failure is shown inline and the person continues with the switch off. Skip keeps the defaults.
- Account deletion wipes the profile and community caches, the `community` consent and the Quran session (`quran.session.v1`); sign-out forgets the account's profile but keeps on-device Quran data. Forgetting an account also resets the in-memory last-seen level (the next account is never compared with it; a new sign-in takes the server's level as its baseline, so signing in is never a level-up) and drops any profile request still out for the old account.

Layering: `domain/` (pure Dart models + logic, unit-tested) → `data/` (repositories; API + local cache) → `presentation/` (widgets + Riverpod controllers). Presentation never calls `ApiClient` directly.
