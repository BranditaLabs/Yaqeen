/**
 * Points engine — pure functions, no I/O.
 *
 * Every number here is admin-controlled (dashboard → النقاط والمكافآت → البرنامج) and
 * arrives as `PointsSettings`; the constants below are only the defaults.
 *  - Active daily tasks have values that must add up to `dailyTotal`.
 *  - A task can be completed for "today" (the user's timezone, Cairo by default).
 *  - A past day inside `qadaWindowDays` can be made up; the whole day is then worth at
 *    most `qadaDayPoints` — the award tops the day up to that cap, never beyond.
 *  - Bonuses (white days / Mon–Thu fasting / Friday Kahf) are self-reported and only
 *    count when the admin has enabled that bonus rule.
 *  - Streak milestones are awarded automatically, once per milestone per user.
 */
import type { BonusKind, DayStatus, PointsSettings, TaskKey } from '@yaqeen/contracts';

export const DEFAULT_SETTINGS: PointsSettings = {
  dailyTotal: 100,
  qadaDayPoints: 80,
  qadaWindowDays: 7,
  challengeLengthDays: 365,
};
export const DAILY_TOTAL = DEFAULT_SETTINGS.dailyTotal;
export const QADA_DAY_POINTS = DEFAULT_SETTINGS.qadaDayPoints;
export const QADA_WINDOW_DAYS = DEFAULT_SETTINGS.qadaWindowDays;
export const CHALLENGE_LENGTH_DAYS = DEFAULT_SETTINGS.challengeLengthDays;

export interface TaskRule {
  key: TaskKey;
  points: number;
}

export interface Completion {
  task: TaskKey;
  isQada: boolean;
}

/* --------------------------------------------------------------- date utils */

const DAY_MS = 86_400_000;

/** Parse a YYYY-MM-DD string as a UTC calendar date. */
export function parseIsoDate(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number);
  if (!y || !m || !d) throw new Error(`Bad date: ${iso}`);
  return new Date(Date.UTC(y, m - 1, d));
}

export function toIsoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function addDays(iso: string, days: number): string {
  return toIsoDate(new Date(parseIsoDate(iso).getTime() + days * DAY_MS));
}

export function diffDays(fromIso: string, toIso: string): number {
  return Math.round((parseIsoDate(toIso).getTime() - parseIsoDate(fromIso).getTime()) / DAY_MS);
}

/** Calendar date ("today") in a given IANA timezone. */
export function localToday(now: Date, timeZone = 'Africa/Cairo'): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  return parts; // en-CA formats as YYYY-MM-DD
}

/* ------------------------------------------------------------------- rules */

/** `rules` = the ACTIVE tasks only. */
export function validateTaskRules(
  rules: TaskRule[],
  dailyTotal: number = DAILY_TOTAL,
): { ok: true } | { ok: false; error: string } {
  if (rules.length === 0) return { ok: false, error: 'At least one task must be active' };
  if (rules.some((r) => r.points < 0)) return { ok: false, error: 'Points cannot be negative' };
  const total = rules.reduce((s, r) => s + r.points, 0);
  if (total !== dailyTotal) {
    return { ok: false, error: `Active task points must total ${dailyTotal}; got ${total}` };
  }
  return { ok: true };
}

export function pointsFor(rules: TaskRule[], task: TaskKey): number {
  const rule = rules.find((r) => r.key === task);
  if (!rule) throw new Error(`No rule for task ${task}`);
  return rule.points;
}

/* ------------------------------------------------------------- day number */

/** 1-based day number in the 365-day challenge, or null when outside it. */
export function challengeDayNumber(startedOn: string, date: string, lengthDays = CHALLENGE_LENGTH_DAYS): number | null {
  const n = diffDays(startedOn, date) + 1;
  return n >= 1 && n <= lengthDays ? n : null;
}

/* -------------------------------------------------------------- day status */

export function dayStatus(args: {
  date: string;
  today: string;
  completions: Completion[];
  allTasks: TaskKey[];
}): DayStatus {
  const { date, today, completions, allTasks } = args;
  if (date > today) return 'future';
  const doneSet = new Set(completions.map((c) => c.task));
  const allDone = allTasks.every((t) => doneSet.has(t));
  if (date === today) return allDone ? 'done' : 'today';
  if (allDone) return completions.some((c) => c.isQada) ? 'qada' : 'done';
  return doneSet.size > 0 ? 'partial' : 'missed';
}

/* -------------------------------------------------------------- task award */

export type AwardDecision =
  | { kind: 'award'; points: number; reason: 'task' | 'qada'; isQada: boolean }
  | { kind: 'reject'; error: 'future_date' | 'before_enrollment' | 'outside_qada_window' | 'already_completed' };

/**
 * Decide what completing `task` on `date` is worth.
 * For qada days, points are scaled so that the full day can never exceed QADA_DAY_POINTS.
 */
export function decideTaskAward(args: {
  task: TaskKey;
  date: string;
  today: string;
  startedOn: string;
  rules: TaskRule[];
  existing: Completion[];
  /** Points already credited for this date (task + qada reasons). */
  pointsAlreadyForDate: number;
  settings?: PointsSettings;
}): AwardDecision {
  const { task, date, today, startedOn, rules, existing, pointsAlreadyForDate } = args;
  const settings = args.settings ?? DEFAULT_SETTINGS;
  if (date > today) return { kind: 'reject', error: 'future_date' };
  if (date < startedOn) return { kind: 'reject', error: 'before_enrollment' };
  if (existing.some((c) => c.task === task)) return { kind: 'reject', error: 'already_completed' };

  const base = pointsFor(rules, task);
  if (date === today) return { kind: 'award', points: base, reason: 'task', isQada: false };

  if (diffDays(date, today) > settings.qadaWindowDays) return { kind: 'reject', error: 'outside_qada_window' };

  // Qada: scale the task's share of the day down to the qada cap, never exceeding the cap.
  const scaled = Math.floor((base * settings.qadaDayPoints) / settings.dailyTotal);
  const remaining = Math.max(0, settings.qadaDayPoints - pointsAlreadyForDate);
  const doneAfter = new Set([...existing.map((c) => c.task), task]);
  const completesDay = rules.every((r) => doneAfter.has(r.key));
  // On the last task, top up to exactly the cap so rounding never loses points.
  const points = completesDay ? remaining : Math.min(scaled, remaining);
  return { kind: 'award', points, reason: 'qada', isQada: true };
}

/* ------------------------------------------------------------------ streak */

/**
 * Consecutive completed days (done or qada) ending today — or yesterday if today
 * is still in progress, so an unfinished morning doesn't reset the streak.
 */
export function computeStreak(statusByDate: Map<string, DayStatus>, today: string): number {
  let cursor = statusByDate.get(today) === 'done' ? today : addDays(today, -1);
  let streak = 0;
  for (;;) {
    const s = statusByDate.get(cursor);
    if (s !== 'done' && s !== 'qada') break;
    streak += 1;
    cursor = addDays(cursor, -1);
  }
  return streak;
}

/* ----------------------------------------------------------------- bonuses */

export const RAMADAN = 9;

/** Days on which fasting is not voluntary: Ramadan itself, Eid al-Fitr, Eid al-Adha + tashreeq. */
function noVoluntaryFast(hijriMonth: number, hijriDay: number): boolean {
  return hijriMonth === RAMADAN || (hijriMonth === 10 && hijriDay === 1) || (hijriMonth === 12 && hijriDay >= 10 && hijriDay <= 13);
}

/**
 * Which bonuses are *eligible* on a date (the user still has to claim them). Voluntary-fast
 * bonuses are never offered in Ramadan or on Eid / tashreeq days; the Ramadan ones only in Ramadan.
 */
export function eligibleBonuses(args: { weekday: number; hijriDay: number; hijriMonth: number }): BonusKind[] {
  const out: BonusKind[] = [];
  const voluntary = !noVoluntaryFast(args.hijriMonth, args.hijriDay);
  if (voluntary && args.hijriDay >= 13 && args.hijriDay <= 15) out.push('white_days_fast');
  if (voluntary && (args.weekday === 1 || args.weekday === 4)) out.push('mon_thu_fast');
  if (args.weekday === 5) out.push('friday_kahf');
  if (args.hijriMonth === RAMADAN) out.push('ramadan_fast', 'taraweeh', 'ramadan_juz');
  return out;
}

/* -------------------------------------------------------------- milestones */

export interface Milestone {
  days: number;
  points: number;
  active: boolean;
}

/** Active milestones the streak has reached (awarding is idempotent per milestone). */
export function reachedMilestones(milestones: Milestone[], streak: number): Milestone[] {
  return milestones.filter((m) => m.active && m.days <= streak).sort((a, b) => a.days - b.days);
}

export function nextMilestone(milestones: Milestone[], streak: number): Milestone | null {
  return milestones.filter((m) => m.active && m.days > streak).sort((a, b) => a.days - b.days)[0] ?? null;
}

/* ---------------------------------------------------------------- balance */

export function balanceOf(ledger: { delta: number }[]): number {
  return ledger.reduce((s, e) => s + e.delta, 0);
}

export function canAfford(balance: number, cost: number): boolean {
  return Number.isInteger(cost) && cost > 0 && balance >= cost;
}
