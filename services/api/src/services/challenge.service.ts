/**
 * Challenge service: glues the pure points engine to the database.
 * All point awards go through `points_ledger` with a unique (user, ref_key), so a retried
 * request from the offline queue can never double-credit.
 */
import { and, between, eq, sql } from 'drizzle-orm';
import type { BonusKind, ChallengeDay, ChallengeSummary, TaskKey } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { bonusRules, challengeEnrollments, pointsLedger, taskCompletions, users } from '../db/schema.js';
import {
  type Completion,
  addDays,
  challengeDayNumber,
  computeStreak,
  dayStatus,
  decideTaskAward,
  eligibleBonuses,
  localToday,
  nextMilestone,
} from '../domain/points.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import { hijriFor } from './calendar.service.js';
import { awardMilestones, getActiveRules, getMilestones, getPointsSettings } from './program.service.js';

/** Active task rules (admin can deactivate a task; it then disappears from the app). */
export const getRules = getActiveRules;

export async function balance(ctx: AppContext, userId: string): Promise<number> {
  const [row] = await ctx.db
    .select({ total: sql<string>`coalesce(sum(${pointsLedger.delta}), 0)` })
    .from(pointsLedger)
    .where(eq(pointsLedger.userId, userId));
  return Number(row?.total ?? 0);
}

/** "Today" in the user's own timezone. */
export async function todayFor(ctx: AppContext, userId: string): Promise<string> {
  return userToday(ctx, userId);
}

async function userToday(ctx: AppContext, userId: string): Promise<string> {
  const [u] = await ctx.db.select({ tz: users.timezone }).from(users).where(eq(users.id, userId));
  return localToday(ctx.now(), u?.tz ?? 'Africa/Cairo');
}

async function enrollment(ctx: AppContext, userId: string) {
  const [e] = await ctx.db.select().from(challengeEnrollments).where(eq(challengeEnrollments.userId, userId));
  return e ?? null;
}

export async function enroll(ctx: AppContext, userId: string) {
  const today = await userToday(ctx, userId);
  await ctx.db.insert(challengeEnrollments).values({ userId, startedOn: today }).onConflictDoNothing();
  return (await enrollment(ctx, userId))!;
}

export async function days(ctx: AppContext, userId: string, from: string, to: string): Promise<ChallengeDay[]> {
  const enr = await enrollment(ctx, userId);
  if (!enr) return [];
  const today = await userToday(ctx, userId);
  const [rules, settings] = await Promise.all([getRules(ctx), getPointsSettings(ctx)]);
  const allTasks = rules.map((r) => r.key);

  const rows = await ctx.db
    .select({ date: taskCompletions.date, task: taskCompletions.task, isQada: taskCompletions.isQada })
    .from(taskCompletions)
    .where(and(eq(taskCompletions.userId, userId), between(taskCompletions.date, from, to)));
  const ledger = await ctx.db
    .select({ refKey: pointsLedger.refKey, delta: pointsLedger.delta })
    .from(pointsLedger)
    .where(and(eq(pointsLedger.userId, userId), sql`${pointsLedger.refKey} >= ${from} and ${pointsLedger.refKey} < ${addDays(to, 1)}`));

  const byDate = new Map<string, Completion[]>();
  for (const r of rows) byDate.set(r.date, [...(byDate.get(r.date) ?? []), { task: r.task, isQada: r.isQada }]);

  const out: ChallengeDay[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    const n = challengeDayNumber(enr.startedOn, d, settings.challengeLengthDays);
    if (n === null) continue;
    const completions = byDate.get(d) ?? [];
    const points = ledger.filter((l) => l.refKey.startsWith(d)).reduce((s, l) => s + l.delta, 0);
    out.push({
      date: d,
      dayNumber: n,
      status: dayStatus({ date: d, today, completions, allTasks }),
      points,
      completedTasks: completions.map((c) => c.task),
      bonuses: ledger
        .filter((l) => l.refKey.startsWith(`${d}:bonus:`))
        .map((l) => l.refKey.split(':')[2] as BonusKind),
    });
  }
  return out;
}

export async function summary(ctx: AppContext, userId: string): Promise<ChallengeSummary> {
  const [rules, settings, milestones] = await Promise.all([getRules(ctx), getPointsSettings(ctx), getMilestones(ctx)]);
  const tasks = rules.map((r) => ({ key: r.key, labelAr: r.labelAr, labelEn: r.labelEn, points: r.points }));
  const bal = await balance(ctx, userId);
  const enr = await enrollment(ctx, userId);
  const challengeLengthDays = settings.challengeLengthDays;
  if (!enr) {
    const first = nextMilestone(milestones, 0);
    return {
      enrolled: false,
      startedOn: null,
      dayNumber: 0,
      streak: 0,
      balance: bal,
      challengeLengthDays,
      nextMilestone: first ? { days: first.days, points: first.points } : null,
      today: null,
      tasks,
    };
  }

  const today = await userToday(ctx, userId);
  const recent = await days(ctx, userId, addDays(today, -60) < enr.startedOn ? enr.startedOn : addDays(today, -60), today);
  const streak = computeStreak(new Map(recent.map((d) => [d.date, d.status])), today);
  const next = nextMilestone(milestones, streak);
  return {
    enrolled: true,
    startedOn: enr.startedOn,
    dayNumber: challengeDayNumber(enr.startedOn, today, challengeLengthDays) ?? 0,
    streak,
    balance: bal,
    challengeLengthDays,
    nextMilestone: next ? { days: next.days, points: next.points } : null,
    today: recent.find((d) => d.date === today) ?? null,
    tasks,
  };
}

export async function completeTask(
  ctx: AppContext,
  userId: string,
  task: TaskKey,
  date: string,
  clientEventId: string,
): Promise<{ awarded: number; milestoneAwarded: number; day: ChallengeDay | null }> {
  const enr = await enrollment(ctx, userId);
  if (!enr) throw conflict('not_enrolled');
  const today = await userToday(ctx, userId);
  const [rules, settings] = await Promise.all([getRules(ctx), getPointsSettings(ctx)]);
  if (!rules.some((r) => r.key === task)) throw badRequest('task_inactive');

  // Idempotency: the same clientEventId returns the existing result.
  const [dup] = await ctx.db
    .select({ id: taskCompletions.id })
    .from(taskCompletions)
    .where(and(eq(taskCompletions.userId, userId), eq(taskCompletions.clientEventId, clientEventId)));
  if (dup) return { awarded: 0, milestoneAwarded: 0, day: (await days(ctx, userId, date, date))[0] ?? null };

  const awarded = await ctx.db.transaction(async (tx) => {
    // Serialise awards per user so the qada cap can't be raced.
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${userId}))`);
    const existing = await tx
      .select({ task: taskCompletions.task, isQada: taskCompletions.isQada })
      .from(taskCompletions)
      .where(and(eq(taskCompletions.userId, userId), eq(taskCompletions.date, date)));
    const [already] = await tx
      .select({ total: sql<string>`coalesce(sum(${pointsLedger.delta}), 0)` })
      .from(pointsLedger)
      .where(and(eq(pointsLedger.userId, userId), sql`${pointsLedger.refKey} like ${`${date}:task:%`}`));

    const decision = decideTaskAward({
      task,
      date,
      today,
      startedOn: enr.startedOn,
      rules,
      existing,
      pointsAlreadyForDate: Number(already?.total ?? 0),
      settings,
    });
    if (decision.kind === 'reject') throw badRequest(decision.error);

    await tx.insert(taskCompletions).values({ userId, date, task, isQada: decision.isQada, clientEventId });
    if (decision.points > 0) {
      await tx.insert(pointsLedger).values({
        userId,
        delta: decision.points,
        reason: decision.reason,
        refKey: `${date}:task:${task}`,
      });
    }
    return decision.points;
  });

  const day = (await days(ctx, userId, date, date))[0] ?? null;
  // A completed day may unlock a streak milestone (awarded once, automatically).
  let milestonePoints = 0;
  if (day && (day.status === 'done' || day.status === 'qada')) {
    const recent = await days(ctx, userId, addDays(today, -60) < enr.startedOn ? enr.startedOn : addDays(today, -60), today);
    const streak = computeStreak(new Map(recent.map((d) => [d.date, d.status])), today);
    milestonePoints = await awardMilestones(ctx, userId, streak);
  }
  return { awarded, milestoneAwarded: milestonePoints, day };
}

export async function claimBonus(ctx: AppContext, userId: string, kind: BonusKind): Promise<number> {
  const date = await userToday(ctx, userId);
  const [rule] = await ctx.db.select().from(bonusRules).where(eq(bonusRules.kind, kind));
  if (!rule?.enabled) throw notFound('bonus');
  const [u] = await ctx.db.select({ off: users.hijriOffsetDays }).from(users).where(eq(users.id, userId));
  // Hijri day is computed server-side — never trusted from the client.
  const hijri = await hijriFor(ctx, date, u?.off ?? 0);
  if (!hijri) throw badRequest('hijri_unavailable');
  if (!eligibleBonuses({ weekday: hijri.weekday, hijriDay: hijri.hijriDay }).includes(kind)) {
    throw badRequest('bonus_not_eligible');
  }
  const inserted = await ctx.db
    .insert(pointsLedger)
    .values({ userId, delta: rule.points, reason: 'bonus', refKey: `${date}:bonus:${kind}` })
    .onConflictDoNothing()
    .returning({ id: pointsLedger.id });
  if (inserted.length === 0) throw conflict('bonus_already_claimed');
  return rule.points;
}
