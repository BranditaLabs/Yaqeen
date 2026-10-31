---
# GENERATED from packages/design-tokens/tokens.json by scripts/build.mjs — edit the tokens, not this block.
version: alpha
name: Yaqeen
description: A premium Islamic companion on a living canvas — light porcelain glass under a sky that follows the day by the real prayer times, one large moment per screen, live instruments that work in place, the day as a journey. Arabic RTL first, Western digits, lapis as the only accent, gold for worship and reward, no ornament.

colors:
  lapis: "#1F3F94"
  royal: "#2A52B8"
  midnight: "#0A1530"
  ink: "#0A1530"
  muted: "#56637F"
  porcelain: "#F3F6FB"
  ice: "#E9EFF9"
  mist: "#C8D5EC"
  sky: "#8FB0E0"
  line: "#DCE4F2"
  gold: "#C6A867"
  gold-text: "#7C6127"
  gold-deep: "#4A3C17"
  gold-light: "#E9D49E"
  cream: "#FFFBF1"
  sand: "#F4E8C8"
  success: "#2E7A55"
  error: "#B23A48"
  white: "#FFFFFF"
  paper-page: "#FFFDF7"
  paper-ink: "#1A1712"
  night-page: "#15161A"
  night-ink: "#E9E2D0"
  navy: "#10214D"
  slate-700: "#475064"
  slate-400: "#858A98"
  slate-200: "#C2C5CB"
  navy-600: "#4C597A"
  navy-400: "#8890A6"
  navy-200: "#C3C8D3"
  lapis-500: "#576FAF"
  lapis-300: "#8F9FCA"
  lapis-100: "#C7CFE4"
  sky-400: "#ABC4E8"
  sky-200: "#C7D8F0"
  sky-100: "#E3EBF7"
  gold-300: "#D4BE8D"
  gold-200: "#E3D4B3"
  gold-100: "#F1E9D9"

typography:
  display-ar: { fontFamily: "ZEYADA Arabic 1, Amiri, Tajawal", fontWeight: 700 }
  display-en: { fontFamily: "Canela Text, Amiri, Georgia, serif", fontWeight: 700 }
  ui: { fontFamily: "Tajawal" }
  numbers: { fontFamily: "Jost", fontFeature: tnum }
  quran: { fontFamily: "Amiri Quran" }
  naskh: { fontFamily: "Amiri" }

rounded:
  pill: 999px
  hero: 30px
  card: 24px
  tile: 20px
  chip: 14px

spacing:
  xs: 4px
  s: 8px
  m: 12px
  l: 16px
  xl: 20px
  xxl: 28px
  gutter: 20px
  touch: 44px

motion:
  ease: "cubic-bezier(0.2, 0.7, 0.2, 1)"
  fast: 200ms
  base: 350ms
  slow: 600ms

glass:
  fillOpacity: 0.58
  blur: 24px
  saturate: 1.8
  rim: "rgba(255,255,255,0.9)"

gradient-brand: "linear-gradient(90deg, #0A1530 0%, #10214D 45%, #1F3F94 100%)"
---

## Overview

Yaqeen (يقين) is a premium Islamic companion for iOS and Android: prayer times, Qibla, the Quran,
azkar, duas and a points challenge. The interface is a **living canvas**: light porcelain glass
under a sky that follows the user's own day (dawn at Fajr, gold at Asr, dusk at Maghrib, night after
Isha), anchored to the real prayer times where they are. Each screen leads with **one moment stated
large**, then live instruments that work in place (the Qibla orbit, a misbaha, liquid wird), then
the day as a vertical journey. Arabic right-to-left first, English fully supported, Western digits
everywhere. Calm by default: eased motion, light haptics, nothing loops forever.

This file is the short brief for design agents. The full rules are in `docs/DESIGN_SYSTEM.md`
(composition), `docs/APP_SPEC.md §2` (tokens) and `CLAUDE.md` (non-negotiables); when they disagree
the spec text wins, then the artboards named in `docs/APP_SPEC.md §0`.

## Colors

Use only the tokens above (`packages/design-tokens/tokens.json` → `YqColors` in Flutter,
`--yq-*` in CSS). Never a raw hex value in UI code.

### Brand & Accent
- **lapis** `#1F3F94` is the one interactive accent: primary buttons, links, rings, the active state.
  Blue is an accent, never a flood fill.
- **royal** `#2A52B8` is for pressed and focus states only.
- **gold** `#C6A867` marks worship and reward moments: completed checks, the challenge ring, earned
  points, a met goal. Use **goldText** `#7C6127` for gold text on light surfaces (AA).

### Surface
- **porcelain** `#F3F6FB` is the ground of every screen, lit by the living sky.
- **ice** `#E9EFF9` and **white** are glass fills; **line** `#DCE4F2` is the hairline.
- Sky keyframes come from tints only: night (lapis100, sky200, lapis300), dawn (gold100, sky100,
  goldLight), morning (white, sky200, sky400), noon (white, sky100, sky200), golden (cream, sand,
  goldLight), dusk (sand, gold300). They blend continuously and never hard-cut.

### Text
- **ink** `#0A1530` for all text on sky and glass. **muted** `#56637F` for secondary text.
- Text stays ink or muted on every sky palette, at AA contrast.

### Reading surfaces (Quran reader only)
- Paper: **paperPage** `#FFFDF7` with **paperInk** `#1A1712`.
- Night: **nightPage** `#15161A` with **nightInk** `#E9E2D0`.

### Brand Gradient
`midnight → navy → lapis` at 90° (dark at the start). Only for brand moments (splash, store art,
the public card's night theme); never behind UI text blocks.

## Typography

### Font Family
- **Tajawal**: all UI and body text (Arabic and Latin).
- **Jost**: numerals (countdowns, points, degrees), tabular figures, Light 300 for big numbers.
- **ZEYADA Arabic 1** (licensed, falls back to Amiri): Arabic display headlines and brand moments.
- **Canela Text** (licensed, falls back to Amiri / Georgia): Latin display headlines.
- **Amiri Quran**: the mushaf only. **Amiri**: duas and azkar.

### Hierarchy
| Role | Face | Size / line height | Weight |
| --- | --- | --- | --- |
| Numeral (the stage moment) | Jost | 38 / 1.1, lapis | 300 |
| Display (feature titles) | ZEYADA → Amiri | 30 / 1.4, midnight | 700 |
| Headline large | Tajawal | 32 / 1.25 | 700 |
| Headline medium | Tajawal | 28 / 1.35 | 700 |
| Title large | Tajawal | 19 | 700 |
| Title medium | Tajawal | 15 | 700 |
| Body large | Tajawal | 15 / 1.7 | 400 |
| Body | Tajawal | 14 / 1.6 | 400 |
| Caption | Tajawal | 12 / 1.6, muted | 400 |
| Label | Tajawal | 13–15 | 500 |
| Dua / zikr | Amiri | 21 / 2.0 | 700 |
| Mushaf | Amiri Quran | 22–34 (user), line height 2.4 | 400 |

### Principles
- Arabic line heights are generous (1.6–2.4); never tighten Arabic tracking.
- Digits are Western (`ar-EG-u-nu-latn`) in both languages, via `YqFormat`.
- The logo is artwork (`YqLogo`, `/brand/*.png`). **Never typeset «يقين» as a logo.**

## Layout

### Spacing System
4 · 8 · 12 · 16 · 20 · 28 (`xs`…`xxl`); screen gutter 20; minimum touch target 44.

### The screen pattern
Every screen except the Quran reader and the splash is a `YqCanvas`:
1. **Stage**: the living sky, edge to edge under the status bar, carrying a bar (back · title ·
   actions) and **one large moment** (gold eyebrow, the value in Jost Light or the display face, a
   caption).
2. **Complications**: up to three 100-pt glass orbs, each a live instrument that works in place.
3. **Journey or list**: a vertical timeline for anything ordered in time; glass groups for settings;
   lazy lists for long content.
4. **Footer**: the primary action pinned above the system inset, when the screen has one.

### Whitespace Philosophy
One idea per band. Let the sky breathe above the moment; group related rows in one glass group
rather than many cards.

## Elevation & Depth

- **Liquid glass**: fill opacity 0.58, blur 24, saturate 1.8, a white rim. Live blur only on fixed
  chrome (the dock); content glass is pre-composited.
- Shadows paint **outside** shapes only, soft and low; no inner shadows, no stacked drop shadows.
- Depth comes from light (the sky glow under the sun's arc position), not from heavy elevation.

## Shapes

### Border Radius Scale
chip 14 · tile 20 · card 24 · hero 30 · pill 999. The stage uses 40-pt corners on tab roots and
32-pt on pushed screens.

### No ornament
**No geometric ornament** anywhere in the app: no star patterns, arabesque tiles or mosque
silhouettes as decoration. Shape comes from glass, light and type.

## Components

- **Primary button**: lapis fill, white Tajawal 15/500, pill radius, 44-pt minimum height.
- **Secondary button**: glass fill, lapis text, pill radius.
- **Orb** (`YqOrb`): a 100-pt glass disc, a title and one status line; a gold glow when its goal is met.
- **Ring** (`YqRing`): an eased progress ring, lapis (or gold for worship/reward goals), sweeping
  with the reading direction.
- **Timeline** (`YqTimeline`): a rail of stops (done = gold check, a highlighted stop, a «now» marker).
- **Group** (`YqGroup`): glass rows separated by hairlines.
- **Dock** (`FloatingTabBar`): a floating porcelain-glass capsule with five equal slots (Home, Quran,
  Prayer, Challenge, Profile — the person's initial on a gold disc is the Profile icon). A 24-pt icon over
  an always-visible 11-pt label; the active slot is lapis and bold over a soft lapis glass pill that glides
  on a spring (it jumps with reduce-motion). No ornament, no indicator lines. Scrolling content clears it
  through the bottom safe area (`YqInsets.bottom`).
- **Skeletons**: shaped like the content they replace, one RTL-aware shimmer.

## Do's and Don'ts

### Do
- Lead with one large moment.
- Make widgets work in place: tap to count, turn to align.
- Show time as a journey with a «now» marker.
- Take colour from the sky and the tokens; keep text ink or muted.
- Mirror layouts, arcs and glows in RTL; keep compass and heading tapes physical (not mirrored).
- Respect reduce-motion: jump to the end state.

### Don't
- Stack several equal-weight cards at the top of a screen.
- Build tiles whose only job is to open another screen.
- Use raw hex values, saturated fills, neon, purple gradients or ornament patterns.
- Typeset the logo, or use Arabic-Indic digits.
- Show worship detail (which prayers, azkar, pages) anywhere public, shared or in admin views.
- Invent religious text: unlicensed content stays visibly bracketed, e.g. `[نص التفسير من المصدر المرخّص]`.

## Responsive Behavior

### Breakpoints
- Phone first (360–430 pt wide).
- Wide screens (≥ 700 and landscape): the Quran reader shows a two-page spread; chrome is capped at
  640 pt and centred.

### Touch Targets
44 pt minimum on every control, including orb taps and timeline trailing controls.

## Motion

- Curve `cubic-bezier(0.2, 0.7, 0.2, 1)`; ease-in-out for the sky.
- 200 / 350 / 600 ms; sky changes 0.9–1 s.
- Content rises in once (staggered 70 ms, 14 px), never again on tab switches.
- Animate value changes only (rings, liquid, beads, the sun); painters never animate while idle.

## Iteration Guide

1. Read the feature's section in `docs/APP_SPEC.md` and its artboard before touching a screen.
2. Build with the core kit (`YqCanvas`, `YqStage`, `YqOrb`, `YqRing`, `YqTimeline`, `YqGroup`)
   rather than new one-off widgets.
3. Check Arabic and English, light sky palettes at dawn, noon and night, and reduce-motion.
4. Update the goldens (`apps/mobile/test/goldens`) when a screen's look changes on purpose.

## Known Gaps

- ZEYADA Arabic 1 and Canela Text are licensed faces not yet bundled; Amiri renders until the
  files are added (`packages/brand/fonts`).
- The admin dashboard (Next.js, Arabic RTL) uses the same colour tokens through `tokens.css` but is
  a utilitarian surface, not a living canvas.
