/**
 * Badges (rewards are badges only — no points are minted, design §1.2): the append-only
 * `user_badges` table (league, division and tournament badges, unique per `ref_key`) unioned with
 * the derived ones — streak milestones (`milestone:<days>` ledger rows) and level crossings.
 */
import { and, eq, like, sql } from 'drizzle-orm';
import { type Badge, LEVEL_REASONS, LEVELS } from '@yaqeen/contracts';
import { pointsLedger, userBadges } from '../db/schema.js';
import type { CommunityCtx } from './community-settings.service.js';
import type { DbOrTx } from './community.service.js';

type BadgeMeta = Badge['meta'];

const reasonList = sql.raw(LEVEL_REASONS.map((r) => `'${r}'`).join(', '));

/** When lifetime earned points (LEVEL_REASONS, delta > 0) first reached each level ≥ 2. */
export async function levelCrossings(db: DbOrTx, uid: string): Promise<{ level: number; at: Date }[]> {
  const thresholds = LEVELS.slice(1).map((l) => l.min);
  const rows = await db.execute<{ min: number; reached: Date | string | null }>(sql`
    with earned as (
      select created_at as at, sum(delta) over (order by created_at, id) as cum
      from points_ledger
      where user_id = ${uid} and delta > 0 and reason::text in (${reasonList})
    )
    select t.min, (select min(at) from earned where cum >= t.min) as reached
    from unnest(${sql.raw(`array[${thresholds.join(',')}]`)}::int[]) as t(min)`);
  const out: { level: number; at: Date }[] = [];
  for (const r of rows.rows) {
    if (!r.reached) continue;
    out.push({ level: LEVELS.findIndex((l) => l.min === Number(r.min)) + 1, at: new Date(r.reached) });
  }
  return out;
}

/** Every badge of a user, newest first. */
export async function listBadges(ctx: Pick<CommunityCtx, 'db'>, uid: string): Promise<Badge[]> {
  const stored = await ctx.db
    .select({ kind: userBadges.kind, refKey: userBadges.refKey, meta: userBadges.meta, awardedAt: userBadges.awardedAt })
    .from(userBadges)
    .where(eq(userBadges.userId, uid));
  const streaks = await ctx.db
    .select({ ref: pointsLedger.refKey, at: pointsLedger.createdAt })
    .from(pointsLedger)
    .where(and(eq(pointsLedger.userId, uid), eq(pointsLedger.reason, 'milestone'), like(pointsLedger.refKey, 'milestone:%')));
  const levels = await levelCrossings(ctx.db, uid);

  const out: Badge[] = stored.map((b) => ({
    kind: b.kind as Badge['kind'],
    refKey: b.refKey,
    awardedAt: b.awardedAt.toISOString(),
    meta: cleanMeta(b.meta as BadgeMeta),
  }));
  for (const s of streaks) {
    const days = Number(s.ref.slice('milestone:'.length));
    if (Number.isFinite(days) && days > 0) out.push({ kind: 'streak', refKey: s.ref, awardedAt: s.at.toISOString(), meta: { days } });
  }
  for (const l of levels) out.push({ kind: 'level', refKey: `level:${l.level}`, awardedAt: l.at.toISOString(), meta: { level: l.level } });
  return out.sort((a, b) => (a.awardedAt === b.awardedAt ? a.refKey.localeCompare(b.refKey) : a.awardedAt < b.awardedAt ? 1 : -1));
}

/** Keep only the documented meta fields (stored meta is ours, but never leak extra keys). */
function cleanMeta(m: BadgeMeta | null | undefined): BadgeMeta {
  const src = (m ?? {}) as Record<string, unknown>;
  const keep = ['days', 'level', 'division', 'rank', 'size', 'startsOn', 'tournamentId', 'titleAr', 'titleEn', 'labelAr', 'labelEn'];
  const out: Record<string, unknown> = {};
  for (const k of keep) if (src[k] !== undefined && src[k] !== null) out[k] = src[k];
  return out as BadgeMeta;
}

export interface AwardRow {
  userId: string;
  kind: string;
  refKey: string;
  meta: BadgeMeta;
}

/** Append badges; an existing `(user_id, ref_key)` is left as it was (idempotent closes). */
export async function awardBadges(tx: DbOrTx, rows: AwardRow[], now: Date): Promise<number> {
  if (!rows.length) return 0;
  const r = await tx
    .insert(userBadges)
    .values(rows.map((b) => ({ userId: b.userId, kind: b.kind, refKey: b.refKey, meta: b.meta, awardedAt: now })))
    .onConflictDoNothing()
    .returning({ id: userBadges.id });
  return r.length;
}
