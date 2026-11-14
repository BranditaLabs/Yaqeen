# profile

**Screens** (APP_SPEC §5.24, design `docs/design/2026-11-profile-community-quran.md` §6.1–§6.5):

| Route | File | What |
| --- | --- | --- |
| `/profile` | `presentation/profile_screen.dart` | `21 · Profile`: stage (avatar in the level ring, name, «المستوى {n} · {name} · @handle»), orbs Level · Points (or Language) · League (or Downloads), body: badges strip, journey, «المنافسة», «بطاقة يقين» row, rewards |
| `/profile/settings` | `presentation/profile_settings_screen.dart` | account (name, picture, «الظهور في المنافسات»), app (language, prayer, privacy, downloads), about, export, delete (two-step), sign out |
| `/profile/badges` | `presentation/badges_screen.dart` | earned badges by section (league, tournaments, journey); `myBadgesProvider` → `GET /v1/me/badges` |
| `/profile/privacy` | `presentation/privacy_screen.dart` | consents + cloud backup |
| `/profile/ledger` | `presentation/ledger_screen.dart` | the points ledger (`ledgerProvider` lives in `features/rewards/presentation/ledger_providers.dart`) |
| `/profile/downloads` | `presentation/downloads_screen.dart` | audio and packs on disk |

Sheets: `avatar_sheet.dart` (16 presets filtered «الكل · رجال · نساء», photo, initial, age attestation,
support-hidden photo), `edit_name_sheet.dart` (1–40 characters, mirrors contracts `DisplayName`, locked when
support hid the name), `level_ladder_sheet.dart` (six levels). `badges_strip.dart` holds `BadgeMedal`.
Routes are registered in `lib/app/routes/profile_routes.dart`; «بطاقة يقين» is `features/card`.

**Data:** `meProfileProvider` / `levelUpProvider` (`me_profile_controller.dart`) and `ProfileRepository`:
name and avatar are written on the phone first and synced through the Outbox; a photo uploads directly
(the stage ring shimmers while it does — `photoUploadingProvider`); joining competitions is direct, leaving
is queued. The orb set depends only on flags and session, so it never swaps while data loads.
A signed-in account with nothing cached waits for its real profile (`meProfileReadyProvider`) instead of
drawing the level-1 placeholder, and a failed first fetch ends on `YqErrorState` with a retry. A queued
name the server refuses on replay (`invalid_name`) is reverted to the server's with «لم يُقبل الاسم…»
(`nameRevertsProvider`, listened to by the Profile tab).

**Rules:**
- Colour: porcelain, ink, muted; lapis is the only accent. Gold only for achievement — the badges strip
  (the only gold block on the tab), level-reached dots (ladder, journey), the one-shot level-up glint and
  the top-level ring. Delete is an ink row; the error colour appears only on the final confirm.
- The per-user view shows the points ledger and redemptions, never which worship act earned them.
- The level-up moment («بلغت مستوى {name}») shows once — on Home or here, whichever comes first.
- A photo is public only after the age attestation; the sheet and the card editor ask for it when a photo
  would be visible (card published or in a competition).
- Deleting the account calls `DELETE /v1/me` and wipes this device; sign-out keeps the on-device mushaf data.
- No spinners: shaped skeletons (stage circle + lines, `YqSkeletonOrbs`, rows, medal circles), and only
  while a first load is on its way — a failed load ends on «—» or a retry, never an endless shimmer.
- Screen-reader labels built from parts join them with `pfSemanticsJoin` (Arabic «، », English «, »).
