# Releasing the mobile app (TestFlight + Google Play)

Workflow: `.github/workflows/release-mobile.yml`.
- Run it from **Actions › Release mobile › Run workflow**: choose the stores and the Play track.
- Or push a tag like `mobile-v0.1.0`.

Each run:
1. Runs the tests.
2. Builds obfuscated release binaries against `API_BASE_URL`.
3. Uploads them:
   - Android → Play (track `internal` by default);
   - iOS → TestFlight.
4. Keeps the binaries and debug symbols as run artifacts for 90 days.

Version name comes from `apps/mobile/pubspec.yaml` (`version: x.y.z+…`). The build number is the run
number, so it always grows. Signing material is written at run time and deleted afterwards; it is
never committed.

All secrets live in a GitHub **Environment** called `production-mobile` (**Settings › Environments**).
Add required reviewers there if releases should need an approval.

## One-time setup

### Google Play
1. Play Console ($25 once) → **Create app** «يقين» / Yaqeen, package `com.yaqinbrand.yaqeen`.
2. Upload key. Create it once on your computer and keep a safe backup:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   base64 -i upload-keystore.jks | pbcopy        # → ANDROID_KEYSTORE_BASE64
   ```
   Enrol in **Play App Signing**: Google holds the app-signing key, you keep the upload key.
3. **First upload is manual** (a Play rule). Run the workflow with `platforms: android` and
   download `app-release.aab` from the run's artifacts. Upload it once under **Testing › Internal
   testing**. Every later run uploads by itself.
4. Service account for uploads:
   - Google Cloud → create a service account → JSON key.
   - Play Console → **Users and permissions** → invite its email with *Release to testing tracks*
     (and *production* when ready).
   - Paste the JSON into `PLAY_SERVICE_ACCOUNT_JSON`.
5. Copy the Play **app-signing** SHA-256 (Setup › App integrity) into
   `deploy/well-known/assetlinks.json`.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | base64 of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_PASSWORD` | the passwords you chose |
| `ANDROID_KEY_ALIAS` | `upload` |
| `PLAY_SERVICE_ACCOUNT_JSON` | the service-account JSON |

`PLAY_RELEASE_STATUS` (variable, optional): leave it unset (`draft`) until the app has passed its
first review. Then set it to `completed`.

### Apple / TestFlight
1. Apple Developer Program ($99/year).
2. **Identifier** `com.yaqinbrand.yaqeen` with these capabilities:
   - Associated Domains;
   - Sign in with Apple;
   - Push Notifications (FCM campaigns; regenerate the App Store profile after enabling it);
   - **NFC Tag Reading** (medal scan + staff encoding, `com.apple.developer.nfc.readersession.formats`
     NDEF + TAG in `Runner.entitlements`). Enable it on the App ID, then **regenerate the App Store
     provisioning profile** — a profile without it fails signing. `NFCReaderUsageDescription` is in
     `Info.plist`. iPhone 7+ reads; writing needs iOS 13+. The plugin (`nfc_manager` ≥ 4.2) ships a
     Swift Package, so no CocoaPods is needed.
3. **App Store Connect** → New App with the same bundle id.
4. **Apple Distribution** certificate. Export it from Keychain as a `.p12` with a password, then
   `base64 -i dist.p12`.
5. **App Store** provisioning profile for the bundle id. Note its exact name.
6. **App Store Connect API key** (Users and Access › Integrations › Keys, role *App Manager*):
   - Key ID → `ASC_API_KEY_ID`;
   - Issuer ID → `ASC_ISSUER_ID`;
   - the `.p8` contents → `ASC_API_PRIVATE_KEY`.
7. Put your Team ID in `deploy/well-known/apple-app-site-association`.

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `IOS_DIST_CERT_P12_BASE64` / `IOS_DIST_CERT_PASSWORD` | distribution certificate |
| `IOS_PROFILE_NAME` | the App Store profile's name |
| `ASC_API_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_PRIVATE_KEY` | App Store Connect API key |
| `GOOGLE_IOS_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` | Google Sign-In iOS client |

### Sign in with Google and Apple (one-time)

Google (Google Cloud console of the Yaqeen project › APIs & Services › Credentials, OAuth consent screen published):
1. **Web application** client → its id is the *server client id*. Repo **variable** `GOOGLE_SERVER_CLIENT_ID`
   (both release jobs fail without it: Android returns no ID token).
2. **Android** client for package `com.yaqinbrand.yaqeen` with the SHA-1 of the upload key **and** of the
   Play app-signing key (Play Console › App integrity). No secret; it only has to exist.
3. **iOS** client for bundle `com.yaqinbrand.yaqeen` → `GOOGLE_IOS_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` secrets.
4. API: `GOOGLE_CLIENT_IDS` = the web client id (add the iOS client id too).

Apple (developer.apple.com › Certificates, Identifiers & Profiles):
1. App ID `com.yaqinbrand.yaqeen` with **Sign in with Apple** (iOS uses it natively).
2. **Services ID** `com.yaqinbrand.yaqeen.signin` (Android web flow) → Configure → primary App ID above,
   domain `api.yaqin-brand.com`, return URL `https://api.yaqin-brand.com/v1/auth/apple/callback`.
   Different values → repo variables `APPLE_SERVICE_ID` / `APPLE_REDIRECT_URI`.
3. API: `APPLE_CLIENT_IDS=com.yaqinbrand.yaqeen,com.yaqinbrand.yaqeen.signin` (bundle id + Services ID).
   The callback form-posts back into the app (`signinwithapple://callback`, package `ANDROID_APP_ID`).
| `FACEBOOK_APP_ID` / `FACEBOOK_CLIENT_TOKEN` | optional — Meta App Events (see *Ad measurement SDKs*) |

TestFlight builds appear after Apple's processing (about 10–30 min). Internal testers (up to 100
people on your team) can install them at once. External testers need a one-time beta review.

### Both
| Variable (not secret) | Value |
| --- | --- |
| `API_BASE_URL` | the deployed API, e.g. `https://api.yaqin-brand.com` |
| `STORE_URL` | optional; defaults to `https://www.yaqin-brand.com` |

## If a run fails
- **"Missing: …"**: a secret or variable from the tables above is not set in the
  `production-mobile` environment.
- **Play "only draft releases"**: keep `PLAY_RELEASE_STATUS` unset until the first review passes.
- **Play "package not found"**: the first manual upload (Google Play, step 3) hasn't been done.
- **iOS "No profile matching"**: `IOS_PROFILE_NAME` must match the profile's name exactly, and
  the profile must contain the imported distribution certificate.
- **iOS "requires a development team" for a CocoaPods bundle**: ask Claude to add a Podfile
  `post_install` that sets the team for pod targets.

## Crash reporting (Sentry)

Optional; the workflow skips it when unset.

| Where | Name | Value |
| --- | --- | --- |
| Variable | `APP_SENTRY_DSN` | DSN of the `yaqeen-app` Sentry project (compiled in with `--dart-define=SENTRY_DSN`) |
| Variable | `SENTRY_ORG` | Sentry organisation slug |
| Secret | `SENTRY_AUTH_TOKEN` | token allowed to upload debug files |

After each build, `dart run sentry_dart_plugin` uploads the obfuscation symbols (`build/symbols`,
config under `sentry:` in `pubspec.yaml`) for release `yaqeen@<version>+<build number>` — the
same release the app reports — so crashes show readable stack traces. Reports carry no user,
URLs, navigation or screenshots (docs/SECURITY_PRIVACY.md).


## Ad measurement SDKs (Google Ads, Meta)

Optional; the workflow builds without them and the app then ships no active ad SDK. With them, each
SDK still stays off until the user grants `ads_measurement` (docs/SECURITY_PRIVACY.md › Ads & tracking).

| Where | Name | Value |
| --- | --- | --- |
| Variable | `FIREBASE_ANALYTICS` | `true` to register the Google Ads sink (Firebase Analytics) |
| Secret | `FACEBOOK_APP_ID` | Meta app id (digits only, no `fb` prefix) |
| Secret | `FACEBOOK_CLIENT_TOKEN` | Meta client token (App settings › Advanced › Security) |

Meta needs **both** values or neither — the workflow fails otherwise. They are compiled in twice from
the same secrets, and the two must match:
- as `--dart-define`s, which decide whether the Dart sink is registered (both platforms) and, on
  Android, fill the manifest through `android/app/build.gradle.kts`;
- on iOS also in `ios/Flutter/Secrets.xcconfig` → `Info.plist` (`FacebookAppID`, `FacebookClientToken`).

Building by hand: pass the same `--dart-define`s, and on iOS put the same values in
`ios/Flutter/Secrets.xcconfig` (see `Secrets.example.xcconfig`). Never pass the Meta defines to an
iOS build whose `Secrets.xcconfig` lacks them: the SDK would start without an app id.

### One-time setup — Google Ads (Firebase)
1. Firebase console › project `yaqeen-eg` › Project settings › Integrations › **Google Analytics**:
   enable it (pick or create a GA4 property; data region and sharing settings: turn off sharing
   with Google for benchmarking/support unless counsel agrees).
2. GA4 › Admin › Product links › **Google Ads**: link the Ads account. Mark `sign_up` and
   `purchase` as key events (conversions) and import them into Google Ads.
3. Set the variable `FIREBASE_ANALYTICS=true` and release.
4. Check with **DebugView** (`adb shell setprop debug.firebase.analytics.app com.yaqinbrand.yaqeen`,
   or `-FIRDebugEnabled` on iOS) on a device that granted `ads_measurement`. If Android logs
   "Missing google_app_id", ask Claude to add the Firebase Android config resource.

### One-time setup — Meta
1. developers.facebook.com › Create app (type *Business*), add the **App Events** product, and add
   both platforms: Android package `com.yaqinbrand.yaqeen` (+ key hashes from Play App Signing),
   iOS bundle id `com.yaqinbrand.yaqeen`.
2. Copy the App ID and the Client Token into the secrets above.
3. Events Manager: connect the app to the ad account. Check events with **Test Events**.

### TikTok
No SDK in the app: conversions go server-side through the TikTok Events API (see
docs/ANALYTICS_EVENTS.md). Nothing to set here.

### Store forms and SKAdNetwork
- Update the App Store privacy label and Play Data safety before the first build with these
  values (docs/STORE_LISTING.md). Play: the app declares `com.google.android.gms.permission.AD_ID`
  (the SDKs merge it in too), so answer *Yes* to "uses advertising ID".
- `SKAdNetworkItems` is **not** needed: that list is for apps that *show* ads from those networks.
  Yaqeen only advertises; the SDKs handle SKAdNetwork conversion values themselves.

## Home-screen widget (iOS extension)

The app embeds the `YaqeenWidget` WidgetKit extension (`com.yaqinbrand.yaqeen.YaqeenWidget`), which shares data with the app through the App Group `group.com.yaqinbrand.yaqeen`. One-time, in the Apple Developer account:

1. Create the App Group `group.com.yaqinbrand.yaqeen`.
2. Enable *App Groups* (with that group) on **both** App IDs: `com.yaqinbrand.yaqeen` and `com.yaqinbrand.yaqeen.YaqeenWidget`.
3. Create an App Store provisioning profile for the widget's App ID and put its name in the secret `IOS_WIDGET_PROFILE_NAME` (the workflow downloads it and passes it as `WIDGET_PROVISIONING_PROFILE_SPECIFIER`). Regenerate the app's own profile too, so it includes the App Group.

Android needs nothing: `NextPrayerWidget` ships inside the APK/AAB.
