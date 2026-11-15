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
| Home | next prayer · countdown · day arc; profile chip (avatar in the lapis level ring) at the start of the header | Qibla orbit · misbaha · liquid wird | «Your day» |
| Prayer | next prayer · countdown · day arc | Qibla · daylight (liquid) · alerts (ring) | six prayers with bells |
| Qibla | turn guidance | the full-screen orbit | calibrate · camera |
| Quran | continue reading + khatma line + search | wird · khatma ring · listen (playing surah + ring) | saved strip · lazy surahs |
| Reader | the printed page (exception) | mode dock «قراءة · استماع · تحفيظ · تسميع» (layers, never a route) | strips per layer; session line «{done} / {goal}» |
| Challenge | gold ring: day N, points | today · streak · make-up | tasks with gold checks |
| Profile | avatar in the level ring (120), name in ink, «المستوى {n} · {name}» (not gold) | level ring · balance/this week (or language) · league (or downloads) | badges strip (the only gold) · journey · «المنافسة» · card row · rewards; settings at `/profile/settings` |
| League | division · my snapshot rank · «{points} نقطة هذا الأسبوع» | — | lazy rows (rank, `YqLevelAvatar` 36, name, snapshot points), zone separators, «يُحدَّث الترتيب كل ليلة.» |
| Tournament(s) | my rank or «انضم» · «{points} نقطة في البطولة» | — | «جارية · قادمة · انتهت» glass cards; paged snapshot standings |
| Level board | «العالم · {country}» | — | rings + level names only (no points); «ترتيبك {rank}» pinned |
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
| `YqRing` | core/widgets/yq_ring.dart | An eased progress ring (lapis, or gold for worship/reward goals); sweeps with the reading direction; optional first draw-in and level-up glint (§5). |
| `LiquidOrb` | core/widgets/liquid_orb.dart | Fill level as still liquid (wird, daylight, hifz plan, download). |
| `MisbahaPainter` | core/widgets/yq_misbaha.dart | Beads that turn gold as they are counted (Home orb, Azkar). |
| `YqTimeline` / `YqStop` | core/widgets/yq_timeline.dart | The journey rail: line or pill stops, `done` (gold check), `highlight`, `trailing` controls, live `detail`, an optional «now» marker. |
| `YqGroup` | core/widgets/yq_layout.dart | A glass group of rows with hairlines. |
| `DayArc` / `dayArcAt` | core/design/living_sky.dart | The day's arc with the sun at its real position. |
| `LiquidGlass` / `GlassTap` | core/widgets | The content surface; live blur only on fixed chrome. |
| `FloatingTabBar` / `YqTab` | core/widgets/floating_tab_bar.dart | The **dock**: a floating porcelain-glass capsule (64 pt, max 520 wide, centred) with five equal slots — Home, Quran, Prayer, Challenge, and Profile with the person's avatar as its icon (`YqTab.avatar(avatar: MeAvatar(size: 24))`: lapis rim when active, white otherwise; their initial in ink on ice until the avatar paints — no gold disc). Each slot is a 24-pt icon over an 11-pt label, always shown (lapis + bold when active, muted otherwise). A soft lapis glass pill sits under the active slot and glides on a spring (jumps with reduce-motion). Press scales to 0.92 with a light haptic; tapping the open tab returns it to its first screen. It steps aside while the keyboard is up. |
| `YqInsets` | core/widgets/yq_layout.dart | Shared geometry: `page` (the directional gutter) and `bottom(context)` — the one bottom inset for scrolling screens. Inside a tab the shell counts the dock as bottom safe area (`FloatingTabBar.clearanceFor`), so content always clears it. |
| `HabitSlotCard` | features/routine/presentation | Picks a habit's time. |
| `YqAvatar` / `YqLevelAvatar` / `YqSkeletonAvatarRows` | core/widgets/yq_avatar.dart | A profile picture (preset art, photo, or the initial in ink on ice; white rim; skeleton circle until the first frame); the same inside the level ring (lapis on a soft lapis track; gold when achieved, with one light sweep and a soft swell only for a level just reached, skipped under reduce-motion; optional draw-in; level numeral at the bottom end); skeleton rows for people lists. `MeAvatar` is the caller's own. |
| `QuranModeDock` / `MiniPlayer` / `YqSkeletonMushafPage` | features/quran, features/listen, core/widgets | Reader layers (glass pill ≤ 640 pt, lapis thumb on the dock spring, icons only when 1.3× text would overflow); the app-wide mini player above the dock (no live blur; the shell adds its height to the bottom inset); the page-shaped reader skeleton. |

## 5. Motion

Premium here means **restrained, physical and purposeful**: springs that settle, light that passes
once, numbers that roll into place. Never confetti, never a loop that runs forever, never motion
that only decorates. Tokens live in `lib/core/design/motion.dart` (`Motion`); the older
`YqMotion` set in `theme/tokens.dart` (200 / 350 / 600 ms, `YqMotion.ease`) stays for existing
widgets.

**Tokens**

| Token | Value | For |
| --- | --- | --- |
| `Motion.quick` | 160 ms | a press going down, a label swap |
| `Motion.standard` | 280 ms | most UI transitions; lapis ↔ gold blends |
| `Motion.emphasised` | 450 ms | a value arriving, a glyph settling, a row gliding |
| `Motion.fade` | 200 ms | skeleton → content (`YqFadeSwap`) |
| `Motion.ringDraw` / `ringDrawSmall` | 900 / 600 ms | a level ring's first sweep (Profile stage / Home chip) |
| `Motion.glint` / `glintHold` | 900 / 1600 ms | the level-up light; how long the ring stays gold |
| `Motion.easeOut` | `Curves.easeOutCubic` | default UI curve |
| `Motion.emphasisedCurve` | `Cubic(0.2, 0, 0, 1)` | emphasised moments |
| `pressSpring`, `popSpring`, `sheetSpring`, `settleSpring` | `SpringDescription`s (and `SpringCurve`s) | press, release/pop, sheets (critically damped), an overshooting settle |

**The reduce-motion rule.** `reduceMotion(context)` reads `MediaQuery.disableAnimationsOf`; use it
everywhere (or `motionOr(context, d)`). Under it every moment **jumps to its end state**: rings
drawn, numbers final, sheets open, faces flipped, no light, no reveal, and **no ticker left
running** (`pumpAndSettle` completes). A toast that follows a light comes at once.

**Rules**

- Sky changes ease over 0.9–1 s with `easeInOut`; never a hard cut.
- Content rises once as a page opens (`YqRise`, 14 px, 70 ms apart; orbs 10 px, 40 ms apart via
  `YqOrbRow(rise: true)`), never again on tab switches or for lazy items scrolled into view.
- Implicit animations only for value changes: rings, liquid, beads, the tape, the sun. Painters
  never animate per frame while idle; continuously animating pieces sit behind a
  `RepaintBoundary` and use `AnimatedBuilder` with a `child` (no `setState` per frame on a screen).
- One-time moments in lazy lists are remembered per screen (`MotionMemo` / `YqMotionMemo`,
  `RankMotionScope`), so scrolling back never replays them; illustrations below the fold start
  when they scroll into view (`YqWhenVisible`).
- Loops are bounded: the «live» dot breathes a few times and rests lit; the recording orbit turns
  only while playing and on screen (`TickerMode`).
- Haptics only on user actions, through `GlassTap` (a selection tick) or the existing
  setting-aware calls; never on a moment that plays by itself.
- Gold moves only for achievement: the level-up light, a medal's first light, a closed podium.
- «تسميع» (`ReciteLayer`, own layer over the printed page — the glyphs never repaint): a
  recognised word fades in and rises (12 % of the line pitch) over 420 ms, lapis settling to ink
  (`easeOutCubic`); the glow on the next word glides 260 ms; «سمّع ثم تحقّق» reveals all words
  one after another (35 ms apart, ≤ 1.4 s in all). The ticker runs only while something moves.
  The mic orb's halo follows the voice level; a light haptic tick per completed ayah, a soft one
  per counted repetition. Reduce motion: words appear, the glow jumps, no halo, no stagger.

**Primitives** (in `core/widgets` unless noted)

| Primitive | Motion |
| --- | --- |
| `YqRing(drawIn:, glint:, change:)` | First show: the track fades in, then the arc sweeps from 0 (emphasised). Later values ease from the old value — never from 0 again. A colour change blends over 280 ms. `glint`: one comet of light (white into gold light) travels once round the ring. |
| `YqLevelAvatar(drawIn:, glint:)` | The ring above, plus the picture swelling once (1.0 → 1.04 → 1.0, `YqPulse`) with the glint; a new picture cross-fades in from 0.94 (`YqAvatarSwap`) without redrawing the ring. `glint` is off by default (a top-level gold ring is quiet): only the Profile stage and the Home chip pass it, for a level just reached. |
| `YqRollingNumber` | Digits roll up 0.9 em into place, 90 ms apart, 900 ms, `Cubic(0.2, 0.9, 0.25, 1.15)` — the public card's rolling digits. Later changes roll only the digits that changed (up for more, down for less). Tabular figures. |
| `CountUp` | Counts to the value on first show and glides between values; tabular figures; the final text alone sizes it and the count is drawn over it, wrapped the same way (`maxLines`/`overflow` apply to every text), so nothing moves around it, nor when it lands. |
| `YqFlip` | Two faces of a disc turning about the vertical axis (perspective 0.001, 450 ms, with the reading direction). |
| `YqFadeSwap` | Skeleton → content: a 200 ms cross-fade, the old state fading where `alignment` puts it (`expand` for whole screens). The outgoing state keeps its element (never remounted: scroll, controllers and one-time moments carry on); only the incoming one sizes the swap. Keep controls the person is using (a segmented control) outside the swap. |
| `YqSheen` | One band of light across a child (light on a gold medal, a soft lapis on the person's own row). |
| `YqPulse`, `YqSlideIn`, `YqShiftIn`, `YqDrawLine`, `YqBreathingDot`, `YqWhenVisible` | A once-only swell; a slide + fade in (the pinned «ترتيبك» row, a podium step); a ranked row gliding from its old place (at most 3 rows; a longer move fades in; `RankMotionScope(listId:)` makes another board a new baseline, never a glide); a hairline drawing outward; the «live» dot; start-when-seen. |
| `GlassTap(pressScale:)` | Eases down (160 ms; cards 0.98, orbs 0.96, small badges 0.92) and springs back with a touch of overshoot. |
| `showYqSheet(spring: true)` | The sheet opens on the critically damped `sheetSpring`. |
| `YqPlayRing` | Play/pause morph, a lapis progress ring that follows the reported position exactly (no ease to trail it), and an optional hairline orbit turning once per 12 s while playing (stopped when paused or off-screen). For recordings and recitations (used by «تلاواتي»: cards, review, listener). |
| `YqLiveLevel` | 5–7 lapis bars driven by a `Stream<double>` of real amplitude, newest in the centre spreading outward, each eased (140 ms); still under reduce-motion (samples ignored, the stream listened to once, so a single-subscription microphone stream is safe). No ticker of its own. Used by the «تلاواتي» recorder. |

**Moments**

| Where | Moment |
| --- | --- |
| Profile stage | The 120-pt ring sweeps in once (900 ms). Level-up: the ring turns gold, one light sweeps round it and the picture swells, then the quiet toast «بلغت مستوى…»; gold leaves after 1.6 s. A new picture cross-fades in; the edit badge pops on its own press (0.92). |
| Profile orbs | Rise 40 ms apart; press 0.96 + selection haptic. The level numeral and the points roll into place; «{n} للمستوى التالي» counts. Points flips about its vertical axis to «هذا الأسبوع». |
| Home chip | The 48-pt ring sweeps in once (600 ms). A pending level-up (consumed by Home first) plays the same light + swell, then the toast. Home's three complications rise 40 ms apart and press to 0.96. |
| League | The rank rolls in; «{n} نقطة هذا الأسبوع» counts. Rows that moved between snapshots glide from their old place (keyed by handle); the person's row catches one soft lapis sheen and their ring draws in; zone lines draw outward from their label. |
| Week result | The sheet opens on a spring; the outcome glyph (up · stay · down) settles with an overshoot; a top-three finish rises on a three-step podium in sequence (only the person's own step is named). |
| Tournaments | A live tournament's status and stage eyebrow breathe a 6-pt lapis dot (opacity only, 2-s breaths, a few, then lit). Standings behave like the league; a closed podium rises 1 → 2 → 3. |
| Level board | The person's ring draws in; the pinned «ترتيبك» pill slides up from the bottom with their own ring drawing in beside it. |
| Badges | A medal new to this phone catches one light sweep (90 ms apart), once ever (`profile.badgesSwept.v1`, wiped with the account; the in-memory set updates with it, so «الكل» after the Profile strip stays still, and a medal the lazy strip rebuilds keeps its light spent); the count rolls in. |
| Onboarding 05·ج | The preview's track fades in; a picked picture cross-fades in; preset pictures pop in 30 ms apart. When reached: a small ring fills through the six levels, lighting their dots, and settles back on level 1; a miniature league (neighbours are shapes, never people) slides in from the reading side with the person's picture and name, lit with one sheen when they switch the league on. Once per visit. |
| «تسميع» (reader) | `ReciteLayer`, its own layer over the printed page (the glyphs never repaint): a recognised word fades in and rises (12 % of the line pitch) over 420 ms, lapis settling to ink (`easeOutCubic`); the glow on the next word glides 260 ms; «سمّع ثم تحقّق» reveals all words one after another (35 ms apart, ≤ 1.4 s in all). The ticker runs only while something moves. The mic orb's halo follows the voice level; a light haptic tick per completed ayah, a soft one per counted repetition. Reduce motion: words appear, the glow jumps, no halo, no stagger. |
| Skeletons | Every skeleton in these features gives way to content with the 200 ms fade. |
| «تلاواتي» picker | Each ayah the finger reaches joins the lapis tint with a selection tick; the estimate line changes in place (no motion). |
| «تلاواتي» recorder | 3 · 2 · 1 scale down from 1.25 and fade in (280 ms, emphasised curve). The «مباشر» pill's dot breathes (opacity 0.35 ↔ 1, 1.4 s) only while a take runs — bounded by the 30-second take. `YqLiveLevel` follows the real microphone; the ring round the stop button follows elapsed time exactly; the stop glyph morphs circle → rounded square (280 ms). A recognised word turns lapis over 280 ms, the current word carries a soft lapis wash, and the view eases to keep the voice in sight (450 ms). A haptic at the 30-second stop and on each count-in beat. Reduce motion: a still pill (lit), still bars, the ring still counts, words change at once, the view jumps. |
| «تلاواتي» listener | Karaoke uses the same word transition; `YqPlayRing` with its hairline orbit while playing. A new reaction pops once on `popSpring` (1 → 1.12 → 1) and its count rolls; taking it back only changes colour. Reduce motion: no pop, colours change at once. |
| «تلاواتي» cards | Press 0.98; a recording in the AI check shows a breathing lapis dot (a few breaths, then lit); the list comes in with the 200 ms fade from two card-shaped skeletons. |

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
