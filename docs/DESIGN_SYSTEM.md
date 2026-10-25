# Yaqeen design system: "the living canvas"

This is how every screen should look and behave. Tokens (colour, type, space, radius, motion) live in
`packages/design-tokens` → `apps/mobile/lib/core/theme/tokens.dart`, and their values are in
`APP_SPEC.md §2`. This document covers **how the pieces are composed**. Brand rules in `CLAUDE.md`
still apply:
- light porcelain UI, blue accent, liquid glass;
- no geometric ornament;
- colours from tokens only;
- the logo only from artwork.

## Principles

1. **The light follows the day.** The app's light is the sky of the user's own day: dawn at Fajr,
   clear blue through the morning, gold at Asr, dusk at Maghrib, night after Isha. Colours blend
   continuously between keyframes anchored to the **real prayer times** at the user's place, so
   they also follow the season and the city. Nothing jumps.
2. **One moment, stated large.** A screen leads with the single most important thing now (the
   next prayer, the surah to resume) in large type, then supporting detail.
3. **Complications, not cards.** Live, single-purpose instruments (the Qibla orbit, the misbaha,
   the liquid wird) that work in place: tap to count, turn to align. They aren't links to
   another screen.
4. **The day as a journey.** Time-based content reads as one vertical timeline, with past
   moments receding and a «now» marker. A feed of cards is not the pattern.
5. **Calm by default.** Motion eases, haptics are light, nothing loops forever, and every
   animation respects reduce-motion.

## 1. Living sky (`lib/core/design/living_sky.dart`)

**Keyframes.** Each palette is (top, bottom, glow), from brand tints only:

| Anchor (that day's real time) | Palette | Colours |
| --- | --- | --- |
| previous Isha → Fajr | `night` | lapis100, sky200, lapis300 |
| Fajr | `dawn` | gold100, sky100, goldLight |
| sunrise + 40 min | `morning` | white, sky200, sky400 |
| Dhuhr | `noon` | white, sky100, sky200 |
| Asr | `golden` | cream, sand, goldLight |
| Maghrib | `dusk` | sand, gold300, gold300 |
| Isha | `night` | sky200, lapis100 (as above) |

**Functions:**
- `skyNow(settings, repo, now)` returns the palette, the sun's position on the arc (0…1, the five
  prayers at evenly spaced stations) and the phase (sun or moon).
- `skyPaletteAt` blends two keyframes with ease-in-out.

**Widgets:**
- `LivingSky(builder:)` rebuilds every 30 s while visible and pauses off-screen and in the background.
- `skyClockProvider` is its clock; the test harness pins it, so screenshots are deterministic.

**Rules:**
- Ease every sky change: about 1 s for the background, 900 ms for bands.
- Never use a hard cut between palettes.
- Sky colours are surfaces. Text stays `ink` and `muted` (AA on every palette).

## 2. Ground: `AmbientBackground`

**Every screen** sits on `AmbientBackground`. It draws porcelain lit by the living sky:
- a tint fading down the page;
- a glow under the sun's arc position (mirrored in RTL);
- a faint counter-light lower on the opposite side.

`lights:` adds accents on top:
- `goldLights` on reward, challenge and calendar screens, and on the aligned Qibla;
- nothing elsewhere.

**Exceptions:**
- the **Quran reader**, which uses mushaf paper/white/night themes for reading comfort;
- the **splash**, which keeps the brand choreography.

## 3. Headers

**Home: the sky stage** (`_Sky` in `features/home/home_screen.dart`).
- Edge to edge under the status bar, with 40-pt lower corners.
- Contents: greeting · «الصلاة القادمة» · prayer name at 58 pt bold · adhan time · countdown in Jost
  Light 46 · the day arc (sun or crescent, five stations) · station names.

**Tab roots: `YqSkyHeader`** (`core/widgets/yq_sky_header.dart`).
- A band of the same sky (32-pt lower corners) around the screen's own title row.
- Used on Quran, Prayer, Challenge and Profile.
- Put it first in a scroll view whose padding is the gutter; the parent `SafeArea` uses
  `top: false`.

**Pushed screens:** `YqTopBar` (back · title · actions) on the living ground.

## 4. Components

| Component | Where | Use |
| --- | --- | --- |
| `LiquidGlass` / `GlassTap` | core/widgets | The surface for content. Live blur only on fixed chrome (`blur:`); cards in scroll views use the frosted fill. `GlassTap` handles tap **and** long-press in one detector. |
| Orb (complication) | features/home/widgets/orbs.dart | A 100-pt glass disc, title and one status line. Glows gold when its goal is met (Qibla aligned). Three per row at most. |
| `DayTimeline` | features/home/widgets/day_journey.dart | Prayers (text rows), azkar and routine stops (glass pills), the «now» marker with a child, and a trailing card. Past moments are slate, the next prayer is lapis with a «التالية» tag, open windows glow gold. |
| `HabitSlotCard` | features/routine/presentation | Picks a habit's time: after a prayer, a set time, or off, with today's real time as a preview. |
| `FloatingTabBar` | core/widgets | One glass lens slides under the active tab; tabs cross-fade (`TabBranches`). |
| Sky arc painter | core/design/living_sky.dart | The day arc. Travelled path in gold (lapis at night), stations, sun or crescent. |

## 5. Motion

- Curves: `YqMotion.ease` (0.2, 0.7, 0.2, 1) for UI and `easeInOut` for sky.
- Durations: 200 / 350 / 600 ms; sky changes 0.9–1 s.
- Home sections rise in once (staggered 70 ms, 14 px), never again on tab switches.
- Implicit animations only for value changes: rings, liquid, beads, the tape, the sun.
  Painters never animate per frame while idle.
- Reduce-motion: jump to the end state, no reveal.

## 6. Performance

- Per-second tickers wrap only their text, behind a `RepaintBoundary`. Cards re-plan every 15–30 s.
- Long lists are lazy (`SliverList.builder`).
- Painters sit behind `RepaintBoundary`, with a `shouldRepaint` that compares values.
- Sensors (compass) run only while visible and in the foreground, and repaint only when the
  value changes by 1° or more.
- One app-wide `DownloadQueue`. Heavy parsing runs off the UI isolate.

## 7. RTL and type

- Arabic first. Use directional insets and alignments everywhere. Skies, arcs and glows mirror
  through `skyX(…, rtl:)`. Compass and heading tapes do **not** mirror (they are physical).
- Never swap chevrons or arrows by direction: they are `matchTextDirection`.
- Western digits through `YqFormat`. Numbers use Jost, UI uses Tajawal.
- Arabic display headings use the brand face (falling back to Amiri); Latin display headings use Amiri.

## 8. Do / don't

- ✅ Lead with one large moment. ❌ Stack several equal-weight cards at the top.
- ✅ Make widgets work in place. ❌ Build tiles whose only job is to open another screen.
- ✅ Show time as a journey. ❌ Show it as a list of timestamps.
- ✅ Use colour from the sky and tokens. ❌ Use hex values, saturated fills or ornament patterns.
- ✅ Keep worship timing (the routine) on the device. ❌ Sync it.
