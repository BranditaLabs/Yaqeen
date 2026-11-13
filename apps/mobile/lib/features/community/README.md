# features/community — opt-in competitions (APP_SPEC §5.31)

Weekly leagues, seasonal tournaments and the level board (world + opt-in country board), with
report and block. Design: `docs/design/2026-11-profile-community-quran.md` §1, §6.6–§6.10, §12.6.

## Rules this code keeps

- **Never worship detail.** Others appear only as name/@handle (or «عضو يقين»), avatar, a level
  ring from the nightly snapshot and the period's snapshot points. Nothing here mints points or
  sends any analytics or ad event.
- **Nightly snapshots.** Every list says «يُحدَّث الترتيب كل ليلة.»; ranks are the server's (ties
  share a rank: 1, 1, 3) and null/0 render «—». The caller's own live points appear only in the
  stage caption (`LeagueJoined.myLivePoints`, `Tournament.me.points`), never in a row.
- **Opt-in, off by default.** Joining is a **direct** online call (offline → «تحتاج اتصالاً
  للانضمام»; typed failures inline). Every join sheet carries the attestation switch unless
  `community.attestedAdult`, the privacy line and «شروط المنافسات» (`/terms#community`). A name
  support hid is shown read-only as «عضو يقين» and never sent (the server answers `name_locked`
  to any name), so that person can still join.
- **One switch, one list.** «لوحة بلدي» is offered only while «لوحة المستويات» is on (the server
  would otherwise turn the world board on with it); the screens say so instead.
- **Leaving works offline.** League/board leaves go through `meProfileProvider.leave` (Outbox);
  tournament leaves are direct when online, queued otherwise. Either way the person is hidden on
  this phone at once, before any network (`leftTournamentsProvider`; the screens trust the
  profile's switches over a stale server answer).
- **Zones by rank.** The demote label follows the server's `outcomeFor` on the ranks shown, never
  the list length (blocked or hidden rows cannot move it), and no label appears before the first
  snapshot.
- **Gentle.** No red; the bottom zone is «يبدأون الأسبوع القادم في …» in muted ink; division names
  are monochrome («ذهب» included). Gold only on an earned badge (week result) and on podium ranks
  1–3 of a tournament the nightly job has closed (`closed`, not only an ended window).
- **No request loops.** A failed standings page stops auto-loading and shows «إعادة المحاولة».
- **No spinners.** Loading is `YqSkeleton` + `YqSkeletonAvatarRows` and a stage skeleton.

## Layout

| File | What |
| --- | --- |
| `domain/community_models.dart` | Models mirroring `packages/contracts/src/community.ts` (contracts stream). |
| `data/community_repository.dart` | `CommunityRepository` + `communityRepositoryProvider`: reads with KV caches (`community.league.v1`, `community.league.history.v1`, `community.tournaments.v1` incl. first standings pages, `community.leaderboard.<scope>.v1`, `community.blocks.v1` — all in `ProfileRepository.wipedKeys`), `Fresh<T>` (`offline` flag), `CommunityException` for server codes, tournament join/leave, report, block/unblock. |
| `presentation/community_providers.dart` | `leagueProvider`, `leagueHistoryProvider`, `tournamentsProvider`, `tournamentProvider(id)`, `standingsProvider(id)` (paged, `loadMore`, `loadFailed` + `retryMore`), `leaderboardProvider(scope)`, `blocksProvider`, `hiddenHandlesProvider` (blocked this session), `leftTournamentsProvider` (left this session), `joinCommunity`, `leaveLeague`, `leaveTournament`. Cached view first, then fresh. |
| `presentation/league_screen.dart` | `/profile/leagues`: stage (division, my snapshot rank, live week points), zones, history, leave; off/guest/closing/banned/offline/error/flag-off states; shows the week result on open. |
| `presentation/tournaments_screen.dart` | `/profile/tournaments`: «جارية · قادمة · انتهت» cards. |
| `presentation/tournament_screen.dart` | `/profile/tournaments/:id`: rank or «انضم» moment, badge label, paged standings, join/leave. |
| `presentation/leaderboard_screen.dart` | `/profile/leaderboard`: world/country tabs (country name from `assets/geo/cities.json`), rings + level names only, «ترتيبك {rank}» pinned. |
| `presentation/community_settings_screen.dart` | `/profile/community` «الظهور في المنافسات»: switches per flag, live tournament entries, name, blocked list. |
| `presentation/join_sheets.dart` | League, board and tournament join sheets; `confirmLeave`. |
| `presentation/report_sheet.dart` | Long-press another row: report (name/photo/other) or block. |
| `presentation/week_result_sheet.dart` | `maybeShowWeekResult` — once per `lastWeek.startsOn` (KV `community.seenWeek`), from the cached profile; Home calls it after the first frame. |
| `presentation/community_widgets.dart` | `CompetitorRow`, `ZoneLabel`, `SnapshotLine`, `CommunityFooter`, `CommunityNote`, `AttestSwitch`, date helpers (whole Cairo days). |
| `presentation/badge_label.dart` | Division and badge labels (contracts stream). |

Routes live in `lib/app/routes/community_routes.dart`.

## Tests

`test/features/community/`: repository (parse, cache, offline, typed failures, join direct, leave
queued, block drops cached rows), league states and flows, week result, tournaments (ack +
attestation, leave, paging), level board (country states), report/block, visibility settings,
RTL + English with Western digits. Goldens `league_{ar,en}.png` / `tournament_{ar,en}.png` are
generated only on Linux by `.github/workflows/goldens.yml` (dispatch it on the branch). They are
not committed yet: on Linux a missing file fails the test; on other hosts it is skipped.
