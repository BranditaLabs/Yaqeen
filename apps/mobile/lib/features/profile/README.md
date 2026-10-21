# profile

**Screens:** `21 · Profile & settings` and its sub-screens — privacy & consents, points history, offline
downloads (`presentation/profile_screen.dart`). «أكوادي» lives in `features/rewards`.

**Rules:** the per-user view shows the points ledger and redemptions, never which worship act earned them.
Deleting the account calls `DELETE /v1/me` and wipes this device; sign-out keeps the on-device mushaf data.
