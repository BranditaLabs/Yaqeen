/**
 * The level board (APP_SPEC §5.31.3): global, plus a country board that is its own switch and exists
 * only with at least K_COUNTRY_BOARD (= K_ANONYMITY) participants. Ranks by the nightly
 * `public_lifetime`; rows carry the level ring only (points null). Top 100 + the caller.
 */
import { sql } from 'drizzle-orm';
import { K_COUNTRY_BOARD, LEVELS, type AdminStandingRow, type LeaderboardScope, type LeaderboardView } from '@yaqeen/contracts';
import { suppress } from '../domain/aggregates.js';
import { conflict } from '../lib/errors.js';
import type { CommunityCtx } from './community-settings.service.js';
import {
  ACTIVE_USER,
  COMPETITOR_COLUMNS,
  COMPETITOR_JOINS,
  type CompetitorRow,
  type DbOrTx,
  blockedBothWays,
  personalise,
  toCompetitor,
} from './community.service.js';

const TOP = 100;

interface Board {
  rows: CompetitorRow[];
  snapshotDay: string | null;
}

/** Visible members of a board with a snapshot rank, top `limit` (shared cache, 120 s). */
async function board(ctx: CommunityCtx, scope: LeaderboardScope, country: string, limit = TOP): Promise<Board> {
  const json = await ctx.cache.getJson('community', `board:${scope}:${country}:${limit}`, 120, async (): Promise<Board> => {
    const r = await ctx.db.execute<CompetitorRow>(sql`
      select ${COMPETITOR_COLUMNS}, null::int as points, s.rank
      from leaderboard_snapshot s
      join users u on u.id = s.user_id
      ${COMPETITOR_JOINS}
      join community_members cm on cm.user_id = u.id
      where s.scope = ${scope} and s.country = ${country}
        and ${ACTIVE_USER} and cm.leaderboard and cm.banned_at is null
        ${scope === 'country' ? sql`and cm.leaderboard_country and u.country = ${country}` : sql``}
      order by s.rank asc, pp.handle asc
      limit ${limit}`);
    const d = await ctx.db.execute<{ day: string | null }>(sql`
      select max(day)::text as day from leaderboard_snapshot where scope = ${scope} and country = ${country}`);
    return { rows: r.rows, snapshotDay: d.rows[0]?.day ?? null };
  });
  return JSON.parse(json) as Board;
}

/** Country-board participants right now (the K threshold). */
export async function countryParticipants(db: DbOrTx, country: string): Promise<number> {
  const r = await db.execute<{ n: number }>(sql`
    select count(*)::int as n from community_members cm join users u on u.id = cm.user_id
    where cm.leaderboard and cm.leaderboard_country and cm.banned_at is null and u.status = 'active' and u.country = ${country}`);
  return Number(r.rows[0]?.n ?? 0);
}

/** GET /v1/leaderboard. */
export async function view(ctx: CommunityCtx, uid: string, scope: LeaderboardScope): Promise<LeaderboardView> {
  const m = await ctx.db.execute<{ leaderboard: boolean | null; country_switch: boolean | null; banned: boolean | null; country: string | null }>(sql`
    select cm.leaderboard, cm.leaderboard_country as country_switch, (cm.banned_at is not null) as banned, u.country
    from users u left join community_members cm on cm.user_id = u.id where u.id = ${uid}`);
  const me = m.rows[0];
  const joined = !!me?.leaderboard && !me.banned;
  const countryJoined = joined && !!me?.country_switch;
  let country = '';
  if (scope === 'country') {
    if (!me?.country) throw conflict('country_unknown', 'Choose your city to see your country board');
    country = me.country;
    if ((await countryParticipants(ctx.db, country)) < K_COUNTRY_BOARD) throw conflict('country_too_small', 'Your country board needs more participants');
  }
  const b = await board(ctx, scope, country);
  const blocked = await blockedBothWays(ctx.db, uid);

  let mine: LeaderboardView['me'] = null;
  if (scope === 'global' ? joined : countryJoined) {
    const r = await ctx.db.execute<CompetitorRow>(sql`
      select ${COMPETITOR_COLUMNS}, null::int as points, s.rank
      from users u ${COMPETITOR_JOINS}
      left join leaderboard_snapshot s on s.user_id = u.id and s.scope = ${scope} and s.country = ${country}
      where u.id = ${uid}`);
    if (r.rows[0]) mine = toCompetitor(ctx, r.rows[0], uid);
  }
  return {
    scope,
    country: scope === 'country' ? country : null,
    snapshotDay: b.snapshotDay,
    joined,
    countryJoined,
    rows: personalise(ctx, b.rows, uid, blocked),
    me: mine,
  };
}

/** Admin: the same snapshot board with user ids, plus the level distribution (suppressed). */
export async function adminView(ctx: CommunityCtx, scope: LeaderboardScope, country: string | undefined) {
  const c = scope === 'country' ? (country ?? '').toUpperCase() : '';
  const b = await board(ctx, scope, c);
  const dist = await ctx.db.execute<{ lifetime: number; n: number }>(sql`
    select lifetime, count(*)::int as n from leaderboard_snapshot where scope = ${scope} and country = ${c} group by lifetime`);
  const levels = LEVELS.map(() => 0);
  for (const row of dist.rows) {
    let i = 0;
    while (i + 1 < LEVELS.length && Number(row.lifetime) >= LEVELS[i + 1]!.min) i++;
    levels[i]! += Number(row.n);
  }
  const rows: AdminStandingRow[] = b.rows.map((r) => ({ ...toCompetitor(ctx, r, null), userId: r.user_id }));
  return {
    scope,
    country: scope === 'country' ? c : null,
    snapshotDay: b.snapshotDay,
    rows,
    levels: levels.map((n, i) => ({ level: i + 1, count: suppress(n) })),
  };
}
