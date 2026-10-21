/**
 * Reads the admin-controlled points program: global settings, task rules, milestones.
 * Everything the engine needs comes through here, so a dashboard change applies to the
 * next request with no deploy.
 */
import { asc, eq, sql } from 'drizzle-orm';
import { PointsSettings } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { appConfig, pointsLedger, streakMilestones, taskRules } from '../db/schema.js';
import { DEFAULT_SETTINGS, type Milestone, reachedMilestones } from '../domain/points.js';

export const POINTS_CONFIG_KEY = 'points';

export async function getPointsSettings(ctx: AppContext): Promise<PointsSettings> {
  const [row] = await ctx.db.select().from(appConfig).where(eq(appConfig.key, POINTS_CONFIG_KEY));
  const parsed = PointsSettings.safeParse({ ...DEFAULT_SETTINGS, ...((row?.value as object) ?? {}) });
  return parsed.success ? parsed.data : DEFAULT_SETTINGS;
}

export async function getAllRules(ctx: AppContext) {
  return ctx.db.select().from(taskRules).orderBy(asc(taskRules.sortOrder));
}

export async function getActiveRules(ctx: AppContext) {
  return (await getAllRules(ctx)).filter((r) => r.active);
}

export async function getMilestones(ctx: AppContext): Promise<(Milestone & { labelAr: string })[]> {
  return ctx.db
    .select({ days: streakMilestones.days, points: streakMilestones.points, active: streakMilestones.active, labelAr: streakMilestones.labelAr })
    .from(streakMilestones)
    .orderBy(asc(streakMilestones.days));
}

/** Award every reached milestone not yet awarded. Unique ref_key makes this idempotent. */
export async function awardMilestones(ctx: AppContext, userId: string, streak: number): Promise<number> {
  const due = reachedMilestones(await getMilestones(ctx), streak);
  if (due.length === 0) return 0;
  const inserted = await ctx.db
    .insert(pointsLedger)
    .values(due.map((m) => ({ userId, delta: m.points, reason: 'milestone' as const, refKey: `milestone:${m.days}`, note: `${m.days} days` })))
    .onConflictDoNothing()
    .returning({ delta: pointsLedger.delta });
  return inserted.reduce((s, r) => s + r.delta, 0);
}

/** Total of all points ever granted by a reason — used by the admin dashboard. */
export async function totalByReason(ctx: AppContext) {
  return ctx.db
    .select({ reason: pointsLedger.reason, total: sql<string>`sum(${pointsLedger.delta})` })
    .from(pointsLedger)
    .groupBy(pointsLedger.reason);
}
