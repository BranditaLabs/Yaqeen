# Universal / App Links

Served by the Shopify store theme at `https://yaqin-brand.com/.well-known/` (spec §6.20):

| File | Replace before publishing |
| --- | --- |
| `apple-app-site-association` (no extension, `application/json`) | `TEAMID` → Apple Developer Team ID |
| `assetlinks.json` | the Play **app signing** SHA-256 fingerprint (Play Console › App integrity) |

The app side is already configured: iOS `Runner.entitlements` (`applinks:yaqin-brand.com`) and the
Android `autoVerify` intent filter for `/app/*`. Paths map through `routeForDeepLink`.
