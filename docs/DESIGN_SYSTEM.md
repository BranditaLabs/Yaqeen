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

## 3. The screen pattern: stage → complications → journey

Every screen is a `YqCanvas` (`core/widgets/yq_stage.dart`):
1. **`YqStage`**, the living-sky stage, edge to edge under the status bar.
   - Tab roots use the full stage (40-pt corners); pushed screens use `compact: true` (32-pt).
   - `gold: true` warms the light on reward screens (Challenge, Calendar, Redeem).
   - It holds a `YqStageBar` (back · title · actions; `large` on tab roots) and **one large moment**
     (`YqMoment`: gold eyebrow, the value in the display face or Jost Light, a caption).
2. **Complications**: up to three `YqOrb`s in a `YqOrbRow`, each a live instrument that works in place.
3. **The journey or list**: a `YqTimeline` for anything ordered in time; `YqGroup`s for settings;
   lazy slivers (`slivers:`) for long lists.
4. A **`footer:`** pins the primary action above the system inset (onboarding, success, recite).

Under the content `YqCanvas` leaves `YqInsets.bottom(context)`: the bottom safe area plus 28. Inside a tab
the shell adds the floating dock to that safe area, so a pushed screen (Azkar, Calendar, Privacy…) clears
the dock exactly like a tab root, with no per-screen numbers. Content rises in only while a page opens
(`YqRiseScope`); lazy items scrolled into view later are simply there.

**Symmetry rules.** Insets are directional (`EdgeInsetsDirectional`, `YqInsets.page`). Orbs sit in equal
columns and their titles stay on one line (shrinking to fit), so status lines share a baseline. Segmented
controls keep every label on one line. A bar with a centred element (the onboarding stepper) gives both
sides the same width.

Content rises in once (`YqRise`, staggered 70 ms). Screen readers get it at once.

| Screen | Stage moment | Complications | Journey / body |
| --- | --- | --- | --- |
| Home | next prayer · countdown · day arc | Qibla orbit · misbaha · liquid wird | «Your day» |
| Prayer | next prayer · countdown · day arc | Qibla · daylight (liquid) · alerts (ring) | six prayers with bells |
| Qibla | turn guidance | the full-screen orbit | calibrate · camera |
| Quran | continue reading + khatma line + search | wird · khatma ring · listen | saved strip · lazy surahs |
| Challenge | gold ring: day N, points | today · streak · make-up | tasks with gold checks |
| Profile | identity medallion | balance · rewards ring / language · downloads | settings groups |
| Calendar | Hijri month, stepping | journey ring · streak · balance | luminous day discs; day sheet timeline |
| Redeem | balance | — | rewards with affordability rings |
| Azkar | set tabs | the misbaha (beads = count) | the rest of the set |
| Duas | dua of the day (fav · share) | sections as orbs | — |
| Hifz | plan as liquid orb · goal · finish | — | listen → repeat → test; reviews |
| Now playing | surah name · reciter | orbit scrubber around the play pill | controls · chips |
| Reciters | selected voice ringed by offline progress | — | voices with download rings |
| Recite | mode tabs | mic orb ringed by progress (footer) | text · results |
| Onboarding | step title; Welcome/Prayer show the day arc | — | the step; Routine previews «your day» live |
| Notifications | — | — | today's reminders timeline, then settings |
| Inbox | filters | — | each day as a timeline; unread glows |

**Exceptions:** the Quran reader (mushaf themes) and the splash.

## 4. Components

| Component | Where | Use |
| --- | --- | --- |
| `YqCanvas`, `YqStage`, `YqStageBar`, `YqMoment`, `YqHeading` | core/widgets/yq_stage.dart | The screen pattern above. |
| `YqOrb` / `YqOrbRow` | core/widgets/yq_orb.dart | A 100-pt glass disc + title + one status line; gold glow when its goal is met; `YqOrb.number` for a numeral disc. |
| `YqRing` | core/widgets/yq_ring.dart | An eased progress ring (lapis, or gold for worship/reward goals); sweeps with the reading direction. |
| `LiquidOrb` | core/widgets/liquid_orb.dart | Fill level as still liquid (wird, daylight, hifz plan, download). |
| `MisbahaPainter` | core/widgets/yq_misbaha.dart | Beads that turn gold as they are counted (Home orb, Azkar). |
| `YqTimeline` / `YqStop` | core/widgets/yq_timeline.dart | The journey rail: line or pill stops, `done` (gold check), `highlight`, `trailing` controls, live `detail`, an optional «now» marker. |
| `YqGroup` | core/widgets/yq_layout.dart | A glass group of rows with hairlines. |
| `DayArc` / `dayArcAt` | core/design/living_sky.dart | The day's arc with the sun at its real position. |
| `LiquidGlass` / `GlassTap` | core/widgets | The content surface; live blur only on fixed chrome. |
| `FloatingTabBar` / `YqTab` | core/widgets/floating_tab_bar.dart | The **dock**: a floating porcelain-glass capsule (64 pt, max 520 wide, centred) with five equal slots — Home, Quran, Prayer, Challenge, and Profile with the person's initial on a gold disc as its icon (`YqTab.avatar`). Each slot is a 24-pt icon over an 11-pt label, always shown (lapis + bold when active, muted otherwise). A soft lapis glass pill sits under the active slot and glides on a spring (jumps with reduce-motion). Press scales to 0.92 with a light haptic; tapping the open tab returns it to its first screen. It steps aside while the keyboard is up. |
| `YqInsets` | core/widgets/yq_layout.dart | Shared geometry: `page` (the directional gutter) and `bottom(context)` — the one bottom inset for scrolling screens. Inside a tab the shell counts the dock as bottom safe area (`FloatingTabBar.clearanceFor`), so content always clears it. |
| `HabitSlotCard` | features/routine/presentation | Picks a habit's time. |

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
