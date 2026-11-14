/**
 * Weekly leagues (APP_SPEC §5.31.1, design §4.1–§4.2): six divisions, groups of ~30, Saturday 00:00 →
 * Saturday 00:00 Africa/Cairo. Standings and ranks come only from the nightly snapshot columns; the
 * caller's own live week points are shown to the caller alone. Results are computed at the closing
 * boundary from `points_earned_daily` — a qada claimed after the close never changes them. Rewards
 * are badges only; nothing here writes `points_ledger`.
 */
import { sql } from 'drizzle-orm';
import type { LeagueCurrent, LeagueHistoryItem, LeagueLastWeek, LeagueSettings, LeagueSummary } from '@yaqeen/contracts';
import {
  type Standing,
  effectiveZones,
  leagueBadge,
  nextDivision,
  outcomeFor,
  packInto,
  rankStandings,
  weekOf,
  weekWindow,
} from '../domain/community.js';
import { addDays } from '../domain/points.js';
import { type AwardRow, awardBadges } from './badges.service.js';
import { type CommunityCtx, divisionName, parseLeagueSettings, readLeagueSettings } from './community-settings.service.js';
import {
  ACTIVE_USER,
  COMPETITOR_COLUMNS,
  COMPETITOR_JOINS,
  type CompetitorRow,
  type DbOrTx,
  blockedBothWays,
  personalise,
} from './community.service.js';

/* ------------------------------------------------------------------ weeks */

/**
 * The week row exists (so the first deploy works before the job runs). With `fillSettings`, a week
 * without settings takes the current `app_config 'leagues'` — once; it never changes after.
 */
export async function ensureWeek(db: DbOrTx, ctx: CommunityCtx, startsOn: string, fillSettings: boolean): Promise<LeagueSettings> {
  const w = weekOf(startsOn);
  await db.execute(sql`
    insert into league_weeks (starts_on, starts_at, ends_at) values (${w.startsOn}, ${w.startsAt}, ${w.endsAt})
    on conflict (starts_on) do nothing`);
  if (fillSettings) {
    const current = await readLeagueSettings(ctx);
    await db.execute(sql`update league_weeks set settings = ${JSON.stringify(current)}::jsonb where starts_on = ${w.startsOn} and settings is null`);
  }
  return weekSettings(db, w.startsOn);
}

/** The settings a week runs with (defaults until it was filled). */
export async function weekSettings(db: DbOrTx, startsOn: string): Promise<LeagueSettings> {
  const r = await db.execute<{ settings: unknown }>(sql`select settings from league_weeks where starts_on = ${startsOn}`);
  return parseLeagueSettings(r.rows[0]?.settings ?? null);
}

/* -------------------------------------------------------------- placement */

/**
 * Pack members into a division's groups for a week, filling each group to `groupSize` before opening
 * another (at most one partial group per division). Serialised per (week, division) with an advisory
 * lock; idempotent per member (PK).
 */
export async function placeInto(tx: DbOrTx, startsOn: string, division: number, userIds: string[], groupSize: number, now: Date): Promise<number> {
  if (!userIds.length) return 0;
  await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${`league:${startsOn}:${division}`}))`);
  const open = await tx.execute<{ id: string; size: number }>(sql`
    select id, size from league_groups
    where starts_on = ${startsOn} and division = ${division} and closed_at is null and size < ${groupSize}
    order by created_at, id`);
  const plan = packInto(
    open.rows.map((g) => Number(g.size)),
    userIds.length,
    groupSize,
  );
  const slots: { groupId: string; take: number }[] = open.rows.map((g, i) => ({ groupId: g.id, take: plan.existing[i]! }));
  for (const take of plan.fresh) {
    const g = await tx.execute<{ id: string }>(sql`
      insert into league_groups (starts_on, division, size, created_at) values (${startsOn}, ${division}, 0, ${now}) returning id`);
    slots.push({ groupId: g.rows[0]!.id, take });
  }
  let placed = 0;
  let i = 0;
  for (const s of slots) {
    if (s.take <= 0) continue;
    const batch = userIds.slice(i, i + s.take);
    i += s.take;
    const ins = await tx.execute<{ user_id: string }>(sql`
      insert into league_members (starts_on, user_id, group_id, division, joined_at)
      select ${startsOn}::date, x.u::uuid, ${s.groupId}::uuid, ${division}::smallint, ${now}::timestamptz
      from jsonb_array_elements_text(${JSON.stringify(batch)}::jsonb) as x(u)
      on conflict (starts_on, user_id) do nothing
      returning user_id`);
    const n = ins.rows.length;
    if (n) await tx.execute(sql`update league_groups set size = size + ${n} where id = ${s.groupId}`);
    placed += n;
  }
  return placed;
}

export type Placement = { state: 'off' } | { state: 'closing' } | { state: 'placed'; startsOn: string; groupId: string };

/**
 * The request path (design §4.2): place an opted-in member in this week's group. While an earlier
 * week past its end is still open, answer `closing` and don't place (the close step places
 * continuing members at their new division). A member who left this week rejoins the same group.
 */
export async function ensurePlacement(ctx: CommunityCtx, uid: string): Promise<Placement> {
  const now = ctx.now();
  const m = await ctx.db.execute<{ leagues: boolean; banned: boolean; division: number; status: string }>(sql`
    select cm.leagues, (cm.banned_at is not null) as banned, cm.division, u.status::text as status
    from community_members cm join users u on u.id = cm.user_id where cm.user_id = ${uid}`);
  const member = m.rows[0];
  if (!member || !member.leagues || member.banned || member.status !== 'active') return { state: 'off' };

  const week = weekWindow(now);
  const settings = await ensureWeek(ctx.db, ctx, week.startsOn, true);
  const pending = await ctx.db.execute(sql`
    select 1 from league_weeks where status = 'open' and starts_on < ${week.startsOn} and ends_at <= ${now} limit 1`);
  if (pending.rows.length) return { state: 'closing' };

  const have = await ctx.db.execute<{ group_id: string; left: boolean }>(sql`
    select group_id, (left_at is not null) as left from league_members where starts_on = ${week.startsOn} and user_id = ${uid}`);
  if (have.rows[0]) {
    if (have.rows[0].left) {
      await ctx.db.execute(sql`update league_members set left_at = null where starts_on = ${week.startsOn} and user_id = ${uid}`);
      await ctx.cache.bumpNamespace('community');
    }
    return { state: 'placed', startsOn: week.startsOn, groupId: have.rows[0].group_id };
  }
  await ctx.db.transaction((tx) => placeInto(tx, week.startsOn, Number(member.division), [uid], settings.groupSize, now));
  await ctx.cache.bumpNamespace('community');
  const row = await ctx.db.execute<{ group_id: string }>(sql`
    select group_id from league_members where starts_on = ${week.startsOn} and user_id = ${uid}`);
  return { state: 'placed', startsOn: week.startsOn, groupId: row.rows[0]!.group_id };
}

/* -------------------------------------------------------------- standings */

interface GroupView {
  rows: CompetitorRow[];
  snapshotDay: string | null;
}

/** A group's visible members with their snapshot points and ranks (shared cache, 60 s). */
async function groupView(ctx: CommunityCtx, groupId: string, startsOn: string): Promise<GroupView> {
  const json = await ctx.cache.getJson('community', `league:${groupId}`, 60, async (): Promise<GroupView> => {
    const r = await ctx.db.execute<CompetitorRow>(sql`
      select ${COMPETITOR_COLUMNS}, m.snapshot_points as points, m.snapshot_rank as rank
      from league_members m
      join users u on u.id = m.user_id
      ${COMPETITOR_JOINS}
      join community_members cm on cm.user_id = u.id
      where m.group_id = ${groupId} and m.left_at is null and ${ACTIVE_USER} and cm.leagues and cm.banned_at is null
      order by m.snapshot_rank asc nulls last, m.snapshot_points desc nulls last, pp.handle asc`);
    const d = await ctx.db.execute<{ day: string | null }>(sql`
      select max(day)::text as day from community_snapshot_days where day >= ${startsOn}`);
    return { rows: r.rows, snapshotDay: d.rows[0]?.day ?? null };
  });
  return JSON.parse(json) as GroupView;
}

/** The caller's live points this week — shown to the caller only, never in a row. */
export async function livePoints(db: DbOrTx, uid: string, fromDay: string, toDayExclusive: string): Promise<number> {
  const r = await db.execute<{ pts: number }>(sql`
    select coalesce(sum(earned), 0)::int as pts from points_earned_daily where user_id = ${uid} and day >= ${fromDay} and day < ${toDayExclusive}`);
  return Number(r.rows[0]?.pts ?? 0);
}

/** The closed week before `startsOn` for this member (null when they weren't in it or left it). */
export async function lastWeekOf(ctx: CommunityCtx, uid: string, startsOn: string): Promise<LeagueLastWeek | null> {
  const prev = addDays(startsOn, -7);
  const r = await ctx.db.execute<{ division: number; final_rank: number | null; outcome: 'up' | 'stay' | 'down' | null }>(sql`
    select m.division, m.final_rank, m.outcome
    from league_members m join league_weeks w on w.starts_on = m.starts_on
    where m.user_id = ${uid} and m.starts_on = ${prev} and w.status = 'closed' and m.left_at is null`);
  const row = r.rows[0];
  if (!row) return null;
  const b = await ctx.db.execute<{ kind: string; ref_key: string; meta: Record<string, unknown>; awarded_at: Date }>(sql`
    select kind, ref_key, meta, awarded_at from user_badges where user_id = ${uid} and ref_key = ${`league:${prev}`}`);
  const badge = b.rows[0];
  return {
    startsOn: prev,
    division: Number(row.division),
    newDivision: nextDivision(Number(row.division), row.outcome),
    rank: row.final_rank === null ? null : Number(row.final_rank),
    outcome: row.outcome,
    badge: badge
      ? { kind: badge.kind as never, refKey: badge.ref_key, awardedAt: new Date(badge.awarded_at).toISOString(), meta: (badge.meta ?? {}) as never }
      : null,
  };
}

/** GET /v1/leagues/current. */
export async function current(ctx: CommunityCtx, uid: string): Promise<LeagueCurrent> {
  const placement = await ensurePlacement(ctx, uid);
  if (placement.state === 'off') return { state: 'off' };
  if (placement.state === 'closing') return { state: 'closing' };
  const week = weekOf(placement.startsOn);
  const r = await ctx.db.execute<{ division: number; settings: unknown }>(sql`
    select m.division, w.settings from league_members m join league_weeks w on w.starts_on = m.starts_on
    where m.starts_on = ${placement.startsOn} and m.user_id = ${uid}`);
  const division = Number(r.rows[0]!.division);
  const settings = parseLeagueSettings(r.rows[0]!.settings);
  const view = await groupView(ctx, placement.groupId, placement.startsOn);
  const size = view.rows.length;
  const zones = effectiveZones(size, settings, division);
  const name = divisionName(settings, division);
  const next = division < 6 ? divisionName(settings, division + 1) : null;
  const prev = division > 1 ? divisionName(settings, division - 1) : null;
  const blocked = await blockedBothWays(ctx.db, uid);
  return {
    state: 'joined',
    startsOn: placement.startsOn,
    endsAt: week.endsAt.toISOString(),
    snapshotDay: view.snapshotDay,
    division,
    divisionAr: name.ar,
    divisionEn: name.en,
    nextAr: next?.ar ?? null,
    nextEn: next?.en ?? null,
    prevAr: prev?.ar ?? null,
    prevEn: prev?.en ?? null,
    size,
    promoteZone: zones.promote,
    demoteZone: zones.demote,
    myLivePoints: await livePoints(ctx.db, uid, placement.startsOn, addDays(placement.startsOn, 7)),
    rows: personalise(ctx, view.rows, uid, blocked),
    lastWeek: await lastWeekOf(ctx, uid, placement.startsOn),
  };
}

/** The Profile's league orb: division, snapshot rank, group size and last week's result. */
export async function summary(ctx: CommunityCtx, uid: string): Promise<LeagueSummary | null> {
  const placement = await ensurePlacement(ctx, uid);
  if (placement.state === 'off') return null;
  const m = await ctx.db.execute<{ division: number }>(sql`select division from community_members where user_id = ${uid}`);
  const startsOn = placement.state === 'placed' ? placement.startsOn : weekWindow(ctx.now()).startsOn;
  if (placement.state === 'closing') {
    const settings = await weekSettings(ctx.db, startsOn);
    const division = Number(m.rows[0]?.division ?? 1);
    const name = divisionName(settings, division);
    return { division, divisionAr: name.ar, divisionEn: name.en, rank: null, size: 0, lastWeek: null };
  }
  const r = await ctx.db.execute<{ division: number; settings: unknown; snapshot_rank: number | null }>(sql`
    select m.division, w.settings, m.snapshot_rank from league_members m join league_weeks w on w.starts_on = m.starts_on
    where m.starts_on = ${startsOn} and m.user_id = ${uid}`);
  const row = r.rows[0]!;
  const division = Number(row.division);
  const name = divisionName(parseLeagueSettings(row.settings), division);
  const view = await groupView(ctx, placement.groupId, startsOn);
  return {
    division,
    divisionAr: name.ar,
    divisionEn: name.en,
    rank: row.snapshot_rank === null ? null : Number(row.snapshot_rank),
    size: view.rows.length,
    lastWeek: await lastWeekOf(ctx, uid, startsOn),
  };
}

/** GET /v1/leagues/history — the member's last 12 closed weeks (final results). */
export async function history(ctx: CommunityCtx, uid: string): Promise<LeagueHistoryItem[]> {
  const r = await ctx.db.execute<{ starts_on: string; division: number; final_rank: number | null; final_points: number | null; outcome: 'up' | 'stay' | 'down' | null; size: number }>(sql`
    select m.starts_on::text as starts_on, m.division, m.final_rank, m.final_points, m.outcome,
      (select count(*) from league_members o where o.group_id = m.group_id and o.left_at is null)::int as size
    from league_members m join league_weeks w on w.starts_on = m.starts_on
    where m.user_id = ${uid} and w.status = 'closed'
    order by m.starts_on desc limit 12`);
  return r.rows.map((x) => ({
    startsOn: x.starts_on,
    division: Number(x.division),
    rank: x.final_rank === null ? null : Number(x.final_rank),
    size: Number(x.size),
    points: x.final_points === null ? null : Number(x.final_points),
    outcome: x.outcome,
  }));
}

/* ------------------------------------------------------------------ close */

type CloseMember = {
  user_id: string;
  handle: string;
  left: boolean;
  points: number;
  continuing: boolean;
}

/**
 * Close one claimed group: finals from `points_earned_daily` over the week's days, outcomes with the
 * week's own settings, division ±1, badges (idempotent), and continuing members placed into the next
 * week at their new division. Runs inside the claim's transaction.
 */
export async function closeGroup(
  tx: DbOrTx,
  group: { id: string; starts_on: string; division: number },
  settings: LeagueSettings,
  next: { startsOn: string; groupSize: number },
  now: Date,
): Promise<{ members: number; up: number; down: number; badges: number }> {
  const startsOn = group.starts_on;
  const endExclusive = addDays(startsOn, 7);
  const division = Number(group.division);
  const r = await tx.execute<CloseMember>(sql`
    select m.user_id, coalesce(pp.handle, m.user_id::text) as handle, (m.left_at is not null) as left,
      coalesce((select sum(d.earned) from points_earned_daily d where d.user_id = m.user_id and d.day >= ${startsOn} and d.day < ${endExclusive}), 0)::int as points,
      coalesce(cm.leagues and cm.banned_at is null, false) and u.status = 'active' as continuing
    from league_members m
    join users u on u.id = m.user_id
    left join public_profiles pp on pp.user_id = m.user_id
    left join community_members cm on cm.user_id = m.user_id
    where m.group_id = ${group.id}`);
  const active = r.rows.filter((x) => !x.left);
  const size = active.length;
  const zones = effectiveZones(size, settings, division);
  const standings: Standing[] = rankStandings(active.map((x) => ({ userId: x.user_id, handle: x.handle, points: Number(x.points) })));

  const finals: { u: string; p: number; r: number | null; o: string | null; d: number }[] = [];
  const badges: AwardRow[] = [];
  const names = (d: number) => divisionName(settings, d);
  let up = 0;
  let down = 0;
  for (const s of standings) {
    const outcome = outcomeFor(s.position, size, s.points, zones);
    const newDiv = nextDivision(division, outcome);
    if (outcome === 'up') up++;
    if (outcome === 'down') down++;
    finals.push({ u: s.userId, p: s.points, r: s.rank, o: outcome, d: newDiv });
    const tier = leagueBadge(s.position, size, s.points, outcome);
    if (tier) {
      const shown = tier === 'league_promoted' ? newDiv : division;
      badges.push({
        userId: s.userId,
        kind: tier,
        refKey: `league:${startsOn}`,
        meta: { startsOn, division: shown, rank: s.rank ?? undefined, size, labelAr: names(shown).ar, labelEn: names(shown).en },
      });
    }
    if (outcome === 'up' && newDiv >= 2) {
      badges.push({ userId: s.userId, kind: 'division_reached', refKey: `division:${newDiv}`, meta: { division: newDiv, labelAr: names(newDiv).ar, labelEn: names(newDiv).en } });
    }
  }
  if (finals.length) {
    await tx.execute(sql`
      update league_members m set final_points = x.p, final_rank = x.r, outcome = x.o
      from jsonb_to_recordset(${JSON.stringify(finals)}::jsonb) as x(u uuid, p int, r int, o text, d int)
      where m.starts_on = ${startsOn} and m.user_id = x.u`);
    await tx.execute(sql`
      update community_members c set division = x.d, updated_at = ${now}
      from jsonb_to_recordset(${JSON.stringify(finals.filter((f) => f.o === 'up' || f.o === 'down'))}::jsonb) as x(u uuid, d int)
      where c.user_id = x.u`);
  }
  const awarded = await awardBadges(tx, badges, now);

  // Continuing members start next week at their new division (batch, same packing as the request path).
  const byDivision = new Map<number, string[]>();
  for (const f of finals) {
    const m = active.find((a) => a.user_id === f.u);
    if (!m?.continuing) continue;
    byDivision.set(f.d, [...(byDivision.get(f.d) ?? []), f.u]);
  }
  for (const [d, ids] of [...byDivision.entries()].sort((a, b) => a[0] - b[0])) {
    await placeInto(tx, next.startsOn, d, ids.sort(), next.groupSize, now);
  }
  return { members: size, up, down, badges: awarded };
}

/**
 * Job step 2: close every week past its end, oldest first, one group per transaction
 * (`for update skip locked`), so a crash resumes from the remaining groups. `maxGroups` stops early
 * (tests simulate a crash with it).
 */
export async function closeDueWeeks(ctx: CommunityCtx, opts: { maxGroups?: number } = {}): Promise<{ weeks: number; groups: number }> {
  let weeks = 0;
  let groups = 0;
  for (;;) {
    const now = ctx.now();
    const due = await ctx.db.execute<{ starts_on: string; settings: unknown }>(sql`
      select starts_on::text as starts_on, settings from league_weeks where status = 'open' and ends_at <= ${now} order by starts_on limit 1`);
    const week = due.rows[0];
    if (!week) break;
    await ensureWeek(ctx.db, ctx, week.starts_on, true);
    const settings = await weekSettings(ctx.db, week.starts_on);
    const nextStartsOn = addDays(week.starts_on, 7);
    const nextSettings = await ensureWeek(ctx.db, ctx, nextStartsOn, true);
    for (;;) {
      if (opts.maxGroups !== undefined && groups >= opts.maxGroups) return { weeks, groups };
      const closed = await ctx.db.transaction(async (tx) => {
        const g = await tx.execute<{ id: string; starts_on: string; division: number }>(sql`
          update league_groups set closed_at = ${now}
          where id = (select id from league_groups where starts_on = ${week.starts_on} and closed_at is null order by id limit 1 for update skip locked)
          returning id, starts_on::text as starts_on, division`);
        const group = g.rows[0];
        if (!group) return false;
        await closeGroup(tx, group, settings, { startsOn: nextStartsOn, groupSize: nextSettings.groupSize }, now);
        return true;
      });
      if (!closed) break;
      groups++;
    }
    const done = await ctx.db.execute(sql`
      update league_weeks set status = 'closed', closed_at = ${now}
      where starts_on = ${week.starts_on} and status = 'open'
        and not exists (select 1 from league_groups g where g.starts_on = ${week.starts_on} and g.closed_at is null)
      returning starts_on`);
    if (!done.rows.length) break; // another worker still holds a group; the next run finishes it
    weeks++;
  }
  if (weeks || groups) await ctx.cache.bumpNamespace('community');
  return { weeks, groups };
}
