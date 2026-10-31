import { describe, expect, it } from 'vitest';
import type { TaskKey } from '@yaqeen/contracts';
import {
  type Completion,
  type TaskRule,
  addDays,
  challengeDayNumber,
  computeStreak,
  dayStatus,
  decideTaskAward,
  eligibleBonuses,
  localToday,
  nextMilestone,
  reachedMilestones,
  validateTaskRules,
} from '../src/domain/points.js';

const RULES: TaskRule[] = [
  { key: 'wird', points: 20 },
  { key: 'morning_azkar', points: 10 },
  { key: 'five_prayers', points: 25 },
  { key: 'evening_azkar', points: 10 },
  { key: 'listen', points: 10 },
  { key: 'daily_task', points: 25 },
];
const ALL = RULES.map((r) => r.key);
const START = '2026-09-03'; // 21 Rabi I 1448
const TODAY = '2026-10-20'; // day 48

describe('task rules', () => {
  it('accepts the default rules (total 100)', () => {
    expect(validateTaskRules(RULES)).toEqual({ ok: true });
  });
  it('rejects rules that do not total 100', () => {
    const bad = RULES.map((r) => (r.key === 'wird' ? { ...r, points: 30 } : r));
    expect(validateTaskRules(bad)).toMatchObject({ ok: false });
  });
});

describe('challenge day number', () => {
  it('counts the start date as day 1', () => {
    expect(challengeDayNumber(START, START)).toBe(1);
    expect(challengeDayNumber(START, TODAY)).toBe(48);
  });
  it('returns null outside the 365 days', () => {
    expect(challengeDayNumber(START, addDays(START, -1))).toBeNull();
    expect(challengeDayNumber(START, addDays(START, 365))).toBeNull();
    expect(challengeDayNumber(START, addDays(START, 364))).toBe(365);
  });
});

describe('localToday', () => {
  it('uses Cairo time, not UTC', () => {
    // 22:30 UTC on 19 Oct is 01:30 on 20 Oct in Cairo (UTC+3 in summer time) / 00:30 (UTC+2)
    expect(localToday(new Date('2026-10-19T22:30:00Z'), 'Africa/Cairo')).toBe('2026-10-20');
  });
});

describe('day status', () => {
  const done = (tasks: TaskKey[], isQada = false): Completion[] => tasks.map((task) => ({ task, isQada }));
  it('future / today / done', () => {
    expect(dayStatus({ date: '2026-10-21', today: TODAY, completions: [], allTasks: ALL })).toBe('future');
    expect(dayStatus({ date: TODAY, today: TODAY, completions: done(['wird']), allTasks: ALL })).toBe('today');
    expect(dayStatus({ date: TODAY, today: TODAY, completions: done(ALL), allTasks: ALL })).toBe('done');
  });
  it('past days: done, qada, partial, missed', () => {
    const past = '2026-10-18';
    expect(dayStatus({ date: past, today: TODAY, completions: done(ALL), allTasks: ALL })).toBe('done');
    expect(
      dayStatus({ date: past, today: TODAY, completions: [...done(['wird']), ...done(ALL.slice(1), true)], allTasks: ALL }),
    ).toBe('qada');
    expect(dayStatus({ date: past, today: TODAY, completions: done(['wird']), allTasks: ALL })).toBe('partial');
    expect(dayStatus({ date: past, today: TODAY, completions: [], allTasks: ALL })).toBe('missed');
  });
});

describe('task award', () => {
  const base = { today: TODAY, startedOn: START, rules: RULES, existing: [] as Completion[], pointsAlreadyForDate: 0 };

  it('awards full points for today', () => {
    expect(decideTaskAward({ ...base, task: 'five_prayers', date: TODAY })).toEqual({
      kind: 'award',
      points: 25,
      reason: 'task',
      isQada: false,
    });
  });

  it('rejects future, pre-enrolment, duplicates and old days', () => {
    expect(decideTaskAward({ ...base, task: 'wird', date: '2026-10-21' })).toMatchObject({ error: 'future_date' });
    expect(decideTaskAward({ ...base, task: 'wird', date: '2026-09-01' })).toMatchObject({ error: 'before_enrollment' });
    expect(
      decideTaskAward({ ...base, task: 'wird', date: TODAY, existing: [{ task: 'wird', isQada: false }] }),
    ).toMatchObject({ error: 'already_completed' });
    expect(decideTaskAward({ ...base, task: 'wird', date: '2026-10-12' })).toMatchObject({
      error: 'outside_qada_window',
    });
  });

  it('a fully made-up day totals exactly 80 points', () => {
    const date = '2026-10-17';
    let existing: Completion[] = [];
    let total = 0;
    for (const task of ALL) {
      const d = decideTaskAward({ ...base, task, date, existing, pointsAlreadyForDate: total });
      expect(d.kind).toBe('award');
      if (d.kind === 'award') {
        expect(d.reason).toBe('qada');
        total += d.points;
      }
      existing = [...existing, { task, isQada: true }];
    }
    expect(total).toBe(80);
  });

  it('a partial day topped up by qada never exceeds 80', () => {
    // 75 points earned on the day itself, then the last task (daily_task, 25) as qada.
    const existing: Completion[] = ALL.filter((t) => t !== 'daily_task').map((task) => ({ task, isQada: false }));
    const d = decideTaskAward({ ...base, task: 'daily_task', date: '2026-10-19', existing, pointsAlreadyForDate: 75 });
    expect(d).toMatchObject({ kind: 'award', points: 5, reason: 'qada' });
  });
});

describe('streak', () => {
  it('counts done and qada days and tolerates an unfinished today', () => {
    const m = new Map([
      ['2026-10-16', 'missed' as const],
      ['2026-10-17', 'done' as const],
      ['2026-10-18', 'qada' as const],
      ['2026-10-19', 'done' as const],
      [TODAY, 'today' as const],
    ]);
    expect(computeStreak(m, TODAY)).toBe(3);
    m.set(TODAY, 'done');
    expect(computeStreak(m, TODAY)).toBe(4);
  });
  it('breaks on a partial day', () => {
    const m = new Map([
      ['2026-10-18', 'done' as const],
      ['2026-10-19', 'partial' as const],
    ]);
    expect(computeStreak(m, TODAY)).toBe(0);
  });
});

describe('bonuses', () => {
  it('white days, Monday/Thursday and Friday', () => {
    expect(eligibleBonuses({ weekday: 1, hijriDay: 13, hijriMonth: 5 })).toEqual(['white_days_fast', 'mon_thu_fast']);
    expect(eligibleBonuses({ weekday: 5, hijriDay: 2, hijriMonth: 5 })).toEqual(['friday_kahf']);
    expect(eligibleBonuses({ weekday: 2, hijriDay: 20, hijriMonth: 5 })).toEqual([]);
  });
  it('Ramadan: its own bonuses, no voluntary-fast ones; none on Eid or tashreeq days', () => {
    expect(eligibleBonuses({ weekday: 1, hijriDay: 14, hijriMonth: 9 })).toEqual(['ramadan_fast', 'taraweeh', 'ramadan_juz']);
    expect(eligibleBonuses({ weekday: 5, hijriDay: 3, hijriMonth: 9 })).toEqual(['friday_kahf', 'ramadan_fast', 'taraweeh', 'ramadan_juz']);
    expect(eligibleBonuses({ weekday: 4, hijriDay: 1, hijriMonth: 10 })).toEqual([]); // Eid al-Fitr
    expect(eligibleBonuses({ weekday: 1, hijriDay: 13, hijriMonth: 12 })).toEqual([]); // tashreeq
    expect(eligibleBonuses({ weekday: 1, hijriDay: 14, hijriMonth: 12 })).toEqual(['white_days_fast', 'mon_thu_fast']);
  });
});

describe('admin-controlled settings', () => {
  const base = { today: TODAY, startedOn: START, rules: RULES, existing: [] as Completion[], pointsAlreadyForDate: 0 };

  it('validates against a custom daily total, active tasks only', () => {
    const active = RULES.filter((r) => r.key !== 'listen'); // 90
    expect(validateTaskRules(active, 90)).toEqual({ ok: true });
    expect(validateTaskRules(active, 100)).toMatchObject({ ok: false });
    expect(validateTaskRules([], 100)).toMatchObject({ ok: false });
  });

  it('a made-up day respects a custom qada cap', () => {
    const settings = { dailyTotal: 100, qadaDayPoints: 50, qadaWindowDays: 7, challengeLengthDays: 365 };
    let existing: Completion[] = [];
    let total = 0;
    for (const task of ALL) {
      const d = decideTaskAward({ ...base, task, date: '2026-10-17', existing, pointsAlreadyForDate: total, settings });
      if (d.kind === 'award') total += d.points;
      existing = [...existing, { task, isQada: true }];
    }
    expect(total).toBe(50);
  });

  it('qada window 0 disables make-ups; a longer window allows older days', () => {
    const off = { dailyTotal: 100, qadaDayPoints: 80, qadaWindowDays: 0, challengeLengthDays: 365 };
    expect(decideTaskAward({ ...base, task: 'wird', date: '2026-10-19', settings: off })).toMatchObject({ error: 'outside_qada_window' });
    const long = { ...off, qadaWindowDays: 14 };
    expect(decideTaskAward({ ...base, task: 'wird', date: '2026-10-10', settings: long })).toMatchObject({ kind: 'award' });
  });

  it('challenge length is configurable', () => {
    expect(challengeDayNumber(START, addDays(START, 39), 40)).toBe(40);
    expect(challengeDayNumber(START, addDays(START, 40), 40)).toBeNull();
  });
});

describe('streak milestones', () => {
  const ms = [
    { days: 7, points: 50, active: true },
    { days: 30, points: 200, active: true },
    { days: 14, points: 80, active: false },
  ];
  it('returns active milestones reached, and the next one', () => {
    expect(reachedMilestones(ms, 6)).toEqual([]);
    expect(reachedMilestones(ms, 20).map((m) => m.days)).toEqual([7]);
    expect(nextMilestone(ms, 7)?.days).toBe(30);
    expect(nextMilestone(ms, 30)).toBeNull();
  });
});
