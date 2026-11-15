# Universal / App Links

`https://yaqeenarabia.com/app/<target>` opens the app (spec §6.20). The API serves the two
verification files on the site host, generated from its settings — nothing to upload anywhere:

| URL | Setting (API env) |
| --- | --- |
| `/.well-known/apple-app-site-association` | `APPLE_TEAM_ID` (10-character Team ID); bundle `IOS_BUNDLE_ID` |
| `/.well-known/assetlinks.json` | `ANDROID_CERT_SHA256` — the Play **app signing** SHA-256 first (Play Console › App integrity), then the upload/debug keys; package `ANDROID_APP_ID` |

Until a setting is present the route answers 404, never a file with placeholder ids. The app side:
iOS `Runner.entitlements` (`applinks:yaqeenarabia.com`, `www.`) and the Android `autoVerify`
intent filter for `/app/*`. Paths map through `routeForDeepLink`.
