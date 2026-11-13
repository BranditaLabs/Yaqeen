/**
 * The nightly public snapshot (design §1.1 snapshot rule, §4.1 step 3). Every public standing, rank,
 * period total and public level ring is read from these columns, refreshed once per Cairo day and
 * covering ledger activity up to Cairo 00:00 of that day — a new point never moves a public list
 * before the next snapshot, and no time ordering is ever stored. Batched; never touches the ledger.
 */
import { sql } from 'drizzle-orm';
import { K_COUNTRY_BOARD } from '@yaqeen/contracts';
import { localToday } from '../domain/points.js';
import type { CommunityCtx } from './community-settings.service.js';

const GROUP_BATCH = 500;
const TOTALS_BATCH = 5000;

/** League groups of open weeks: snapshot points = earned days from the week start to yesterday. */
export async function snapshotLeagues(ctx: CommunityCtx, today: string): Promise<number> {
  const groups = await ctx.db.execute<{ id: string }>(sql`
    select g.id from league_groups g join league_weeks w on w.starts_on = g.starts_on
    where w.status = 'open' and g.closed_at is null order by g.id`);
  const ids = groups.rows.map((g) => g.id);
  for (let i = 0; i < ids.length; i += GROUP_BATCH) {
    const batch = JSON.stringify(ids.slice(i, i + GROUP_BATCH));
    await ctx.db.transaction(async (tx) => {
      await tx.execute(sql`
        with pts as (
          select m.starts_on, m.user_id, m.group_id,
            coalesce((select sum(d.earned) from points_earned_daily d
                      where d.user_id = m.user_id and d.day >= m.starts_on and d.day < least(${today}::date, m.starts_on + 7)), 0)::int as points
          from league_members m
          where m.group_id in (select x::uuid from jsonb_array_elements_text(${batch}::jsonb) as x) and m.left_at is null
        ),
        ranked as (
          select pts.*, case when points > 0 then rank() over (partition by group_id order by points desc) end as rnk from pts
        )
        update league_members m set snapshot_points = r.points, snapshot_rank = r.rnk
        from ranked r where m.starts_on = r.starts_on and m.user_id = r.user_id`);
      await tx.execute(sql`
        update league_members set snapshot_points = null, snapshot_rank = null
        where group_id in (select x::uuid from jsonb_array_elements_text(${batch}::jsonb) as x) and left_at is not null`);
    });
  }
  return ids.length;
}

/** Live and just-ended (not yet closed) tournaments: points over the window days before today. */
export async function snapshotTournaments(ctx: CommunityCtx, today: string): Promise<number> {
  const now = ctx.now();
  const ts = await ctx.db.execute<{ id: string; starts_at: Date; ends_at: Date }>(sql`
    select id, starts_at, ends_at from tournaments
    where status = 'published' and closed_at is null and starts_at <= ${now} order by starts_at`);
  for (const t of ts.rows) {
    const startDay = localToday(new Date(t.starts_at));
    const endDay = localToday(new Date(t.ends_at));
    const upto = endDay < today ? endDay : today;
    await ctx.db.transaction(async (tx) => {
      await tx.execute(sql`
        with pts as (
          select e.user_id,
            coalesce((select sum(d.earned) from points_earned_daily d
                      where d.user_id = e.user_id and d.day >= ${startDay}::date and d.day < ${upto}::date), 0)::int as points
          from tournament_entries e where e.tournament_id = ${t.id} and e.left_at is null
        ),
        ranked as (select pts.*, case when points > 0 then rank() over (order by points desc) end as rnk from pts)
        update tournament_entries e set snapshot_points = r.points, snapshot_rank = r.rnk
        from ranked r where e.tournament_id = ${t.id} and e.user_id = r.user_id`);
      await tx.execute(sql`
        update tournament_entries set snapshot_points = null, snapshot_rank = null
        where tournament_id = ${t.id} and left_at is not null`);
    });
  }
  return ts.rows.length;
}

/**
 * The public level: lifetime earned up to Cairo 00:00 today (today's earned points are held back
 * until the next snapshot). In batches of 5,000 users.
 */
export async function snapshotPublicLifetime(ctx: CommunityCtx, today: string): Promise<number> {
  let total = 0;
  for (;;) {
    const r = await ctx.db.execute(sql`
      update user_point_totals t
      set public_lifetime = greatest(0, t.lifetime_earned - coalesce((select d.earned from points_earned_daily d where d.user_id = t.user_id and d.day = ${today}::date), 0)),
          public_day = ${today}::date
      where t.user_id in (
        select user_id from user_point_totals where public_day is distinct from ${today}::date order by user_id limit ${TOTALS_BATCH})`);
    const n = r.rowCount ?? 0;
    total += n;
    if (n < TOTALS_BATCH) break;
  }
  return total;
}

/** The level boards: global, and each country with at least K_COUNTRY_BOARD country-board participants. */
export async function snapshotLeaderboard(ctx: CommunityCtx, today: string): Promise<void> {
  await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`delete from leaderboard_snapshot`);
    await tx.execute(sql`
      insert into leaderboard_snapshot (scope, country, user_id, rank, lifetime, day)
      select 'global', '', u.id, rank() over (order by t.public_lifetime desc), t.public_lifetime, ${today}::date
      from community_members cm
      join users u on u.id = cm.user_id
      join user_point_totals t on t.user_id = u.id
      where cm.leaderboard and cm.banned_at is null and u.status = 'active' and t.public_lifetime > 0`);
    await tx.execute(sql`
      with eligible as (
        select u.country from community_members cm join users u on u.id = cm.user_id
        where cm.leaderboard and cm.leaderboard_country and cm.banned_at is null and u.status = 'active' and u.country is not null
        group by u.country having count(*) >= ${K_COUNTRY_BOARD}
      )
      insert into leaderboard_snapshot (scope, country, user_id, rank, lifetime, day)
      select 'country', u.country, u.id, rank() over (partition by u.country order by t.public_lifetime desc), t.public_lifetime, ${today}::date
      from community_members cm
      join users u on u.id = cm.user_id
      join user_point_totals t on t.user_id = u.id
      where cm.leaderboard and cm.leaderboard_country and cm.banned_at is null and u.status = 'active'
        and t.public_lifetime > 0 and u.country in (select country from eligible)`);
  });
}

/** Job step 3: once per Cairo day (skipped when `community_snapshot_days` already has today). */
export async function takeNightlySnapshot(ctx: CommunityCtx, opts: { force?: boolean } = {}): Promise<{ taken: boolean; day: string }> {
  const today = localToday(ctx.now());
  if (!opts.force) {
    const done = await ctx.db.execute(sql`select 1 from community_snapshot_days where day = ${today}::date`);
    if (done.rows.length) return { taken: false, day: today };
  }
  await snapshotLeagues(ctx, today);
  await snapshotTournaments(ctx, today);
  await snapshotPublicLifetime(ctx, today);
  await snapshotLeaderboard(ctx, today);
  await ctx.db.execute(sql`
    insert into community_snapshot_days (day, taken_at) values (${today}::date, ${ctx.now()})
    on conflict (day) do update set taken_at = excluded.taken_at`);
  await ctx.cache.bumpNamespace('community');
  await ctx.cache.bumpNamespace('profile');
  return { taken: true, day: today };
}

/** Hours since the last snapshot (monitoring), or null when none ran yet. */
export async function snapshotAgeHours(ctx: Pick<CommunityCtx, 'db' | 'now'>): Promise<number | null> {
  const r = await ctx.db.execute<{ at: Date | null }>(sql`select max(taken_at) as at from community_snapshot_days`);
  const at = r.rows[0]?.at;
  return at ? (ctx.now().getTime() - new Date(at).getTime()) / 3_600_000 : null;
}
