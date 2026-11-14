/**
 * The community job — hourly at :07:  pnpm --filter @yaqeen/api job:community
 *
 * Design §4.1. Each step is resumable and none holds one giant transaction:
 *   1. ensure the current and next league week rows (the current one gets its settings);
 *   2. close every week past its end, one group per transaction (finals, outcomes, badges, placing
 *      continuing members into the next week);
 *   3. the nightly public snapshot, once per Cairo day (league and tournament snapshot points/ranks,
 *      public lifetime, level boards);
 *   4. close tournaments past their end in batches of 1,000 (finals, badges, consent);
 *   5. delete resolved reports older than 180 days.
 * It never touches `points_ledger` and needs no Redis. A Postgres advisory lock makes overlapping
 * runs (or the admin «rollover») skip instead of racing.
 */
import { sql } from 'drizzle-orm';
import { Redis } from 'ioredis';
import type pg from 'pg';
import { loadEnv } from '../config/env.js';
import { createDb } from '../db/client.js';
import { weekWindow } from '../domain/community.js';
import { addDays } from '../domain/points.js';
import { ResponseCache } from '../lib/cache.js';
import { runJob } from '../lib/observability.js';
import type { CommunityCtx } from '../services/community-settings.service.js';
import { closeDueWeeks, ensureWeek } from '../services/leagues.service.js';
import { takeNightlySnapshot } from '../services/snapshots.service.js';
import { closeDueTournaments } from '../services/tournaments.service.js';
import { withJobLock } from './lock.js';

/** Resolved reports are kept this long, then deleted. */
export const REPORT_RETENTION_DAYS = 180;

export interface CommunityJobResult {
  weeksClosed: number;
  groupsClosed: number;
  snapshot: { taken: boolean; day: string };
  tournamentsClosed: number;
  reportsDeleted: number;
}

/** The job body (also run by the admin «rollover»). */
export async function runCommunity(ctx: CommunityCtx): Promise<CommunityJobResult> {
  const week = weekWindow(ctx.now());
  await ensureWeek(ctx.db, ctx, week.startsOn, true);
  await ensureWeek(ctx.db, ctx, addDays(week.startsOn, 7), false);
  const closed = await closeDueWeeks(ctx);
  const snapshot = await takeNightlySnapshot(ctx);
  const t = await closeDueTournaments(ctx);
  const del = await ctx.db.execute(sql`
    delete from community_reports where resolved_at is not null and resolved_at < ${new Date(ctx.now().getTime() - REPORT_RETENTION_DAYS * 86_400_000)}`);
  return { weeksClosed: closed.weeks, groupsClosed: closed.groups, snapshot, tournamentsClosed: t.closed, reportsDeleted: del.rowCount ?? 0 };
}

/** Under the job lock (skips when another run holds it). */
export async function runCommunityJob(ctx: CommunityCtx): Promise<{ ran: boolean; result?: CommunityJobResult }> {
  const pool = (ctx.db as unknown as { $client: pg.Pool }).$client;
  const res = await withJobLock(pool, 'community', () => runCommunity(ctx));
  return res.ran ? { ran: true, result: res.result } : { ran: false };
}

// Run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const { db, pool } = createDb(env.DATABASE_URL);
  const redis = env.REDIS_URL ? new Redis(env.REDIS_URL, { lazyConnect: true, maxRetriesPerRequest: 1 }) : null;
  redis?.on('error', () => undefined); // cache bumps are best effort; the job needs no Redis
  const ctx: CommunityCtx = { env, db, cache: new ResponseCache(redis), now: () => new Date() };
  const res = await runJob(env, 'yaqeen-community', '7 * * * *', () => withJobLock(pool, 'community', () => runCommunity(ctx)));
  console.log(res.ran ? `[community] ${JSON.stringify(res.result)}` : '[community] another run in progress — skipped');
  await pool.end();
  redis?.disconnect();
}
