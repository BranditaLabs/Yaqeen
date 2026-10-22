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
   - Push Notifications (for phase 2).
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
