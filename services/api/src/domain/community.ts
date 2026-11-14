/**
 * Pure rules of the opt-in community (docs/design/2026-11-profile-community-quran.md §3.5):
 * league weeks and Cairo midnights, competition ranking, promote/demote zones, outcomes and badges,
 * tournament windows, and the display-name / handle rules. No I/O — unit-tested in community.test.ts.
 *
 * Fairness: ties share a rank (standard competition ranking 1, 1, 3) and display order inside a tie
 * is the handle, so nobody is rewarded for ticking earlier. A member with 0 points has no rank.
 */
import { DISPLAY_NAME_MAX, LEAGUE_WEEK } from '@yaqeen/contracts';
import { addDays, localToday, parseIsoDate } from './points.js';

const TZ = LEAGUE_WEEK.timezone;
const MINUTE = 60_000;
const DAY_MS = 86_400_000;

/* ------------------------------------------------------------------ time */

/**
 * The first instant of the Cairo calendar day `day` (YYYY-MM-DD). DST-safe: Egypt springs forward
 * at 00:00 (the day starts at 01:00 local) and falls back at 24:00, so the local date is monotonic
 * and a binary search over minutes finds the boundary.
 */
export function cairoMidnight(day: string, tz: string = TZ): Date {
  const utc = parseIsoDate(day).getTime();
  let lo = (utc - 15 * 3_600_000) / MINUTE; // a minute certainly on the previous local day
  let hi = (utc + 15 * 3_600_000) / MINUTE; // a minute certainly on this local day (or later)
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (localToday(new Date(mid * MINUTE), tz) >= day) hi = mid;
    else lo = mid;
  }
  return new Date(hi * MINUTE);
}

/** True when `date` is exactly the first instant of a Cairo calendar day. */
export function isCairoMidnight(date: Date, tz: string = TZ): boolean {
  if (Number.isNaN(date.getTime())) return false;
  return cairoMidnight(localToday(date, tz), tz).getTime() === date.getTime();
}

/** Weekday (0 = Sunday … 6 = Saturday) of a calendar day. */
export function weekdayOf(day: string): number {
  return parseIsoDate(day).getUTCDay();
}

export interface WeekWindow {
  /** The Saturday (Cairo calendar day) the week starts on. */
  startsOn: string;
  startsAt: Date;
  /** Exclusive: the next Saturday 00:00 Cairo. */
  endsAt: Date;
}

/** The league week holding `now`: Saturday 00:00 → next Saturday 00:00, Africa/Cairo. */
export function weekWindow(now: Date, tz: string = TZ): WeekWindow {
  return weekOf(localToday(now, tz), tz);
}

/** The league week that starts on the Saturday on or before `day`. */
export function weekOf(day: string, tz: string = TZ): WeekWindow {
  const back = (weekdayOf(day) - LEAGUE_WEEK.startsOnWeekday + 7) % 7;
  const startsOn = addDays(day, -back);
  return { startsOn, startsAt: cairoMidnight(startsOn, tz), endsAt: cairoMidnight(addDays(startsOn, 7), tz) };
}

/** Cairo calendar days in [from, to). */
export function daysBetween(from: string, toExclusive: string): string[] {
  const out: string[] = [];
  for (let d = from; d < toExclusive; d = addDays(d, 1)) out.push(d);
  return out;
}

/* --------------------------------------------------------------- ranking */

export interface StandingInput {
  userId: string;
  handle: string;
  points: number;
}

export interface Standing {
  userId: string;
  points: number;
  /** Shared on ties (1, 1, 3); null with 0 points. */
  rank: number | null;
  /**
   * Competition rank counting the 0-point members as one tie after everyone else — the position
   * the outcome rules use (a 0-point member is never promoted; a tie at the boundary stays).
   */
  position: number;
  /** 1-based display order: points desc, then handle asc. */
  order: number;
}

const byHandle = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/** Standard competition ranking on points; display order inside a tie by handle. */
export function rankStandings(rows: StandingInput[]): Standing[] {
  const sorted = [...rows].sort((a, b) => b.points - a.points || byHandle(a.handle, b.handle) || byHandle(a.userId, b.userId));
  const out: Standing[] = [];
  let position = 0;
  let prev: number | null = null;
  sorted.forEach((r, i) => {
    const pts = Math.max(0, r.points);
    if (prev === null || pts !== prev) position = i + 1;
    prev = pts;
    out.push({ userId: r.userId, points: pts, rank: pts > 0 ? position : null, position, order: i + 1 });
  });
  return out;
}

/* ----------------------------------------------------------------- zones */

export interface Zones {
  promote: number;
  demote: number;
}

/**
 * Promote/demote zone sizes, applied in this order: groups under 5 neither promote nor demote; caps
 * at a third of the group; then division 6 never promotes and division 1 never demotes.
 */
export function effectiveZones(size: number, settings: { promote: number; demote: number }, division: number): Zones {
  if (size < 5) return { promote: 0, demote: 0 };
  const cap = Math.floor(size / 3);
  let promote = Math.min(settings.promote, cap);
  let demote = Math.min(settings.demote, cap);
  if (division >= 6) promote = 0;
  if (division <= 1) demote = 0;
  return { promote, demote };
}

export type Outcome = 'up' | 'stay' | 'down';

/**
 * A member's result. `position` is the competition rank (ties share it). Everyone tied at the
 * promote boundary goes up (points > 0 required); a tie straddling the demote boundary stays, the
 * kinder side. Members who left get no outcome (the caller passes them as `left`).
 */
export function outcomeFor(position: number, size: number, points: number, zones: Zones, left = false): Outcome | null {
  if (left) return null;
  if (zones.promote > 0 && position <= zones.promote && points > 0) return 'up';
  if (zones.demote > 0 && position > size - zones.demote) return 'down';
  return 'stay';
}

export type LeagueBadgeKind = 'league_first' | 'league_top3' | 'league_promoted';

/** The best league badge for a week (ties share it); never with 0 points or in groups under 5 for 1st/top 3. */
export function leagueBadge(position: number, size: number, points: number, outcome: Outcome | null): LeagueBadgeKind | null {
  if (points <= 0) return null;
  if (position === 1 && size >= 5) return 'league_first';
  if (position <= 3 && size >= 5) return 'league_top3';
  if (outcome === 'up') return 'league_promoted';
  return null;
}

export type TournamentBadgeKind = 'tournament_podium' | 'tournament_top10' | 'tournament_finisher';

/** One badge per joiner at close (ties share): podium (ranks 1–3, ≥ 10 joiners) > top 10% > finisher. */
export function tournamentBadge(position: number, n: number, points: number, minPoints: number): TournamentBadgeKind | null {
  if (points < Math.max(1, minPoints)) return null;
  if (n >= 10 && position <= 3) return 'tournament_podium';
  if (n >= 10 && position <= Math.ceil(0.1 * n)) return 'tournament_top10';
  return 'tournament_finisher';
}

/** The division after an outcome, clamped to 1..6. */
export function nextDivision(division: number, outcome: Outcome | null): number {
  const d = outcome === 'up' ? division + 1 : outcome === 'down' ? division - 1 : division;
  return Math.min(6, Math.max(1, d));
}

/**
 * Pack `n` new members into groups that already hold `sizes` members, filling each to `groupSize`
 * before opening another (so a division has at most one partial group). Returns, for each existing
 * group index or 'new:<k>', how many to add.
 */
export function packInto(sizes: number[], n: number, groupSize: number): { existing: number[]; fresh: number[] } {
  const existing = sizes.map(() => 0);
  const fresh: number[] = [];
  let left = n;
  sizes.forEach((s, i) => {
    if (left <= 0) return;
    const take = Math.min(left, Math.max(0, groupSize - s));
    existing[i] = take;
    left -= take;
  });
  while (left > 0) {
    const take = Math.min(left, groupSize);
    fresh.push(take);
    left -= take;
  }
  return { existing, fresh };
}

/* ------------------------------------------------------------ tournaments */

export const TOURNAMENT_MAX_DAYS = 90;
export const TOURNAMENT_SLUG = /^[a-z0-9-]{3,40}$/;

export interface TournamentWindowInput {
  slug: string;
  startsAt: Date;
  endsAt: Date;
  joinUntil: Date;
}

/**
 * A tournament window is whole Cairo days: every instant a Cairo midnight, start < end, the join
 * deadline after the start and not after the end, at most 90 days. Returns `tournament_dates` (or
 * null when valid). `now`: a new or rescheduled window must not already be over.
 */
export function validateTournament(input: TournamentWindowInput, now?: Date): 'tournament_dates' | null {
  const { startsAt, endsAt, joinUntil } = input;
  if (!TOURNAMENT_SLUG.test(input.slug)) return 'tournament_dates';
  for (const d of [startsAt, endsAt, joinUntil]) if (!isCairoMidnight(d)) return 'tournament_dates';
  if (!(startsAt.getTime() < endsAt.getTime())) return 'tournament_dates';
  if (!(joinUntil.getTime() > startsAt.getTime()) || joinUntil.getTime() > endsAt.getTime()) return 'tournament_dates';
  if (endsAt.getTime() - startsAt.getTime() > TOURNAMENT_MAX_DAYS * DAY_MS) return 'tournament_dates';
  if (now && endsAt.getTime() <= now.getTime()) return 'tournament_dates';
  return null;
}

/** Inclusive Cairo days (admin form) → the stored window (exclusive end and join instants). */
export function tournamentWindow(input: { startsOn: string; lastDay: string; joinLastDay?: string | undefined }) {
  return {
    startsAt: cairoMidnight(input.startsOn),
    endsAt: cairoMidnight(addDays(input.lastDay, 1)),
    joinUntil: cairoMidnight(addDays(input.joinLastDay ?? input.lastDay, 1)),
  };
}

/** Stored window → inclusive Cairo days. */
export function tournamentDays(w: { startsAt: Date; endsAt: Date; joinUntil: Date }) {
  return {
    startsOn: localToday(w.startsAt),
    lastDay: addDays(localToday(w.endsAt), -1),
    joinLastDay: addDays(localToday(w.joinUntil), -1),
  };
}

export type TournamentPhase = 'upcoming' | 'live' | 'ended';

export function tournamentPhase(w: { startsAt: Date; endsAt: Date }, now: Date): TournamentPhase {
  if (now.getTime() < w.startsAt.getTime()) return 'upcoming';
  if (now.getTime() < w.endsAt.getTime()) return 'live';
  return 'ended';
}

/* ------------------------------------------------------------------- names */

/** Trim, collapse inner whitespace, NFC. */
export function canonicalName(input: string): string {
  return input.normalize('NFC').replace(/\s+/g, ' ').trim();
}

// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/;
const BIDI = /[‎‏‪-‮⁦-⁩]/;
const ZERO_WIDTH = /[​-‍﻿⁠᠎]/;
const URLISH = /https?:|www\.|\.(com|net|org|io|me|app|link)\b/i;

/** Case-folded, diacritic-free, Arabic-letter-unified form used for brand/profanity matching. */
export function foldName(input: string): string {
  return canonicalName(input)
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '') // Latin combining marks
    .replace(/[ً-ٰٟۖ-ۭـ]/g, '') // Arabic tashkeel, superscript alef, Quranic marks, tatweel
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/ؤ/g, 'و')
    .replace(/ئ/g, 'ي')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

/** Words that would read as Yaqeen staff or the brand (after `foldName`). */
const BRAND_CONTAINS = ['yaqeen', 'yaqin', 'yakeen', 'يقين'];
const BRAND_TOKENS = new Set(['support', 'admin', 'administrator', 'official', 'moderator', 'الدعم', 'دعم', 'الاداره', 'اداره', 'المشرف']);
const BRAND_PHRASES = ['فريق يقين', 'فريق الدعم'];

/**
 * A small profanity list (ar/en), matched on folded tokens; the long English stems also inside words.
 * Kept here on purpose (unit-tested); support moderation catches the rest.
 */
const PROFANITY_TOKENS = new Set([
  'fuck', 'fucker', 'fucking', 'shit', 'bitch', 'cunt', 'dick', 'pussy', 'whore', 'slut', 'bastard', 'asshole', 'ass', 'nigger', 'nigga', 'faggot', 'porn', 'sex',
  'شرموط', 'شرموطه', 'شرموطة', 'عرص', 'معرص', 'منيوك', 'متناك', 'خول', 'قحبه', 'زب', 'كس', 'كسمك', 'نيك', 'لبوه', 'وسخه', 'زاني', 'زانيه', 'سكس',
]);
const PROFANITY_CONTAINS = ['fuck', 'shit', 'bitch', 'cunt', 'whore', 'nigger', 'faggot', 'asshole', 'شرموط', 'منيوك', 'متناك', 'كسمك'];

export type NameProblem = 'name_required' | 'invalid_name';

/**
 * Why a display name can't be used, or null. URLs, control/bidi/zero-width characters, the reserved
 * handles (built-in + cards settings), brand impersonation and the profanity list → `invalid_name`.
 */
export function nameProblem(name: string, reservedHandles: Iterable<string> = []): NameProblem | null {
  if (CONTROL.test(name) || BIDI.test(name) || ZERO_WIDTH.test(name)) return 'invalid_name';
  const canon = canonicalName(name);
  if (!canon) return 'name_required';
  if (canon.length > DISPLAY_NAME_MAX) return 'invalid_name';
  if (URLISH.test(canon)) return 'invalid_name';
  const folded = foldName(canon);
  if (!folded) return 'invalid_name';
  const tokens = folded.split(' ');
  const compact = tokens.join('');
  if (BRAND_CONTAINS.some((w) => compact.includes(w))) return 'invalid_name';
  if (tokens.some((t) => BRAND_TOKENS.has(t))) return 'invalid_name';
  if (BRAND_PHRASES.some((p) => folded.includes(foldName(p)))) return 'invalid_name';
  for (const h of reservedHandles) {
    const r = foldName(h).replace(/ /g, '');
    if (r && (compact === r || tokens.includes(r))) return 'invalid_name';
  }
  if (tokens.some((t) => PROFANITY_TOKENS.has(t))) return 'invalid_name';
  if (PROFANITY_CONTAINS.some((w) => compact.includes(w))) return 'invalid_name';
  return null;
}

/** The first word of a name — what join sheets prefill and what a new handle may carry. */
export function firstName(name: string | null | undefined): string {
  return canonicalName(name ?? '').split(' ')[0] ?? '';
}

const ALNUM = 'abcdefghijklmnopqrstuvwxyz0123456789';

/** `n` random characters from `alphabet` using `rand` (uniform in [0, 1)). */
export function randomChars(n: number, rand: () => number, alphabet = ALNUM): string {
  let s = '';
  for (let i = 0; i < n; i++) s += alphabet[Math.min(alphabet.length - 1, Math.floor(rand() * alphabet.length))];
  return s;
}

/**
 * A new competitor handle that never carries the full name: the first word slugified to ASCII +
 * '-' + 4 random digits (`omar-5521`), or `member-` + 6 random [a-z0-9] when the first word has no
 * ASCII letters (e.g. Arabic-only names).
 */
export function competitorHandle(name: string | null | undefined, rand: () => number): string {
  const slug = firstName(name)
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
    .replace(/^[0-9]+/, '')
    .slice(0, 16);
  if (!slug) return memberHandle(rand);
  return `${slug}-${randomChars(4, rand, '0123456789')}`;
}

/** `member-` + 6 random [a-z0-9] (also the handle a hidden name rotates to). */
export function memberHandle(rand: () => number): string {
  return `member-${randomChars(6, rand)}`;
}
