/**
 * Seasonal tournaments (APP_SPEC §5.31.2, design §3.3–§3.4, §4.1 step 4): admin-created windows of
 * whole Cairo days, ranked by points earned in the window, one badge per joiner at close. Standings
 * come from the nightly snapshot (or the finals once closed); the caller alone sees their live
 * points. Closing never writes `points_ledger`.
 */
import { type SQL, sql } from 'drizzle-orm';
import type {
  AdminStandingRow,
  AdminTournamentCreate,
  AdminTournamentPatch,
  AdminTournamentRow,
  AdminTournamentStats,
  Tournament,
  TournamentStandings,
} from '@yaqeen/contracts';
import { BADGE_KINDS } from '@yaqeen/contracts';
import { rankStandings, tournamentBadge, tournamentDays, tournamentPhase, tournamentWindow, validateTournament, cairoMidnight } from '../domain/community.js';
import { addDays, localToday } from '../domain/points.js';
import { suppress } from '../domain/aggregates.js';
import { AppError, badRequest, conflict, notFound } from '../lib/errors.js';
import { type AwardRow, awardBadges } from './badges.service.js';
import type { CommunityCtx } from './community-settings.service.js';
import {
  ACTIVE_USER,
  COMPETITOR_COLUMNS,
  COMPETITOR_COLUMNS_ANY,
  COMPETITOR_JOINS,
  type CompetitorRow,
  type DbOrTx,
  blockedBothWays,
  personalise,
  prepareJoin,
  recomputeCommunityConsent,
  recomputeCommunityConsentMany,
  toCompetitor,
} from './community.service.js';

type TournamentRecord = {
  id: string;
  slug: string;
  title_ar: string;
  title_en: string;
  body_ar: string;
  body_en: string;
  starts_at: Date;
  ends_at: Date;
  join_until: Date;
  badge_ar: string;
  badge_en: string;
  min_points: number;
  status: 'draft' | 'published' | 'cancelled';
  finalizing_at: Date | null;
  closed_at: Date | null;
  created_by: string | null;
  participants: number;
}

const iso = (d: Date | string) => new Date(d).toISOString();

async function load(db: DbOrTx, id: string, lock = false): Promise<TournamentRecord | null> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const r = await db.execute<TournamentRecord>(sql`
    select t.*, (select count(*) from tournament_entries e where e.tournament_id = t.id and e.left_at is null)::int as participants
    from tournaments t where t.id = ${id} ${lock ? sql`for update` : sql``}`);
  return r.rows[0] ?? null;
}

/** Window days [start, end) as Cairo calendar days. */
function windowDays(t: Pick<TournamentRecord, 'starts_at' | 'ends_at'>) {
  return { from: localToday(new Date(t.starts_at)), to: localToday(new Date(t.ends_at)) };
}

function base(t: TournamentRecord, now: Date) {
  return {
    id: t.id,
    slug: t.slug,
    titleAr: t.title_ar,
    titleEn: t.title_en,
    bodyAr: t.body_ar,
    bodyEn: t.body_en,
    startsAt: iso(t.starts_at),
    endsAt: iso(t.ends_at),
    joinUntil: iso(t.join_until),
    phase: tournamentPhase({ startsAt: new Date(t.starts_at), endsAt: new Date(t.ends_at) }, now),
    closed: t.closed_at !== null || t.status === 'cancelled',
    participants: Number(t.participants),
    badgeAr: t.badge_ar,
    badgeEn: t.badge_en,
  };
}

type EntryRow = { tournament_id: string; left: boolean; snapshot_rank: number | null; final_rank: number | null; final_points: number | null };

/**
 * The caller's part of each tournament (joined, rank, own live points) in two queries whatever the
 * number of tournaments: their entries, then the live sums for the joined ones without finals.
 */
async function toTournaments(ctx: CommunityCtx, ts: TournamentRecord[], uid: string): Promise<Tournament[]> {
  if (!ts.length) return [];
  const now = ctx.now();
  const ids = JSON.stringify(ts.map((t) => t.id));
  const e = await ctx.db.execute<EntryRow>(sql`
    select tournament_id, (left_at is not null) as left, snapshot_rank, final_rank, final_points from tournament_entries
    where user_id = ${uid} and tournament_id in (select x::uuid from jsonb_array_elements_text(${ids}::jsonb) as x)`);
  const entries = new Map(e.rows.map((r) => [r.tournament_id, r]));
  const tomorrow = addDays(localToday(now), 1);
  const windows = ts
    .filter((t) => {
      const entry = entries.get(t.id);
      return entry && !entry.left && !(t.closed_at !== null && entry.final_points !== null);
    })
    .map((t) => {
      const w = windowDays(t);
      return { id: t.id, f: w.from, t: w.to < tomorrow ? w.to : tomorrow };
    });
  const live = new Map<string, number>();
  if (windows.length) {
    const r = await ctx.db.execute<{ id: string; pts: number }>(sql`
      select x.id::text as id, coalesce((select sum(d.earned) from points_earned_daily d
        where d.user_id = ${uid} and d.day >= x.f::date and d.day < x.t::date), 0)::int as pts
      from jsonb_to_recordset(${JSON.stringify(windows)}::jsonb) as x(id uuid, f text, t text)`);
    for (const row of r.rows) live.set(row.id, Number(row.pts));
  }
  return ts.map((t) => {
    const entry = entries.get(t.id);
    const joined = !!entry && !entry.left;
    let me: Tournament['me'] = null;
    if (entry && joined) {
      const closed = t.closed_at !== null;
      const points = closed && entry.final_points !== null ? Number(entry.final_points) : (live.get(t.id) ?? 0);
      const rank = closed ? entry.final_rank : entry.snapshot_rank;
      me = { rank: rank === null ? null : Number(rank), points };
    }
    return { ...base(t, now), joined, me };
  });
}

async function toTournament(ctx: CommunityCtx, t: TournamentRecord, uid: string): Promise<Tournament> {
  return (await toTournaments(ctx, [t], uid))[0]!;
}

/* ----------------------------------------------------------------- public */

/**
 * Published tournaments: live + upcoming + ended in the last 30 days (live first). The shared part
 * (the rows and their participant counts) is cached in `community` for a minute — joins, leaves and
 * the job bump it — so opening the tab doesn't count every tournament's entrants each time; the
 * caller's own part is added after the cached read.
 */
export async function list(ctx: CommunityCtx, uid: string): Promise<Tournament[]> {
  const now = ctx.now();
  const minute = Math.floor(now.getTime() / 60_000);
  const json = await ctx.cache.getJson('community', `tournaments:${minute}`, 60, async (): Promise<TournamentRecord[]> => {
    const r = await ctx.db.execute<TournamentRecord>(sql`
      select t.*, (select count(*) from tournament_entries e where e.tournament_id = t.id and e.left_at is null)::int as participants
      from tournaments t
      where t.status = 'published' and t.ends_at > ${new Date(now.getTime() - 30 * 86_400_000)}
      order by case when t.starts_at <= ${now} and t.ends_at > ${now} then 0 when t.starts_at > ${now} then 1 else 2 end, t.starts_at desc
      limit 50`);
    return r.rows;
  });
  return toTournaments(ctx, JSON.parse(json) as TournamentRecord[], uid);
}

export async function get(ctx: CommunityCtx, uid: string, id: string): Promise<Tournament> {
  const t = await load(ctx.db, id);
  if (!t || t.status !== 'published') throw notFound('tournament');
  return toTournament(ctx, t, uid);
}

/** Join (direct online call): acknowledgement, attestation, a name, not banned, within the join window. */
export async function join(ctx: CommunityCtx, uid: string, id: string, body: { acknowledge?: unknown; attestAdult?: unknown }, ip: string | null): Promise<Tournament> {
  if (body.acknowledge !== true) throw badRequest('ack_required', 'Agree to appear in this tournament');
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const t = await load(tx, id);
    if (!t || t.status === 'draft') throw notFound('tournament');
    if (t.status !== 'published' || t.closed_at || t.finalizing_at || now.getTime() >= new Date(t.join_until).getTime() || now.getTime() >= new Date(t.ends_at).getTime()) {
      throw conflict('tournament_not_open', 'Joining this tournament has closed');
    }
    await prepareJoin(tx, ctx, uid, body.attestAdult === true ? true : undefined, ip);
    await tx.execute(sql`
      insert into tournament_entries (tournament_id, user_id, joined_at) values (${id}, ${uid}, ${now})
      on conflict (tournament_id, user_id) do update set left_at = null, joined_at = excluded.joined_at
      where tournament_entries.left_at is not null`);
    // A join always carries the 18+ attestation (given now or before): the consent event records it.
    await recomputeCommunityConsent(tx, uid, 'settings', { attestedAdult: true });
  });
  await ctx.cache.bumpNamespace('community');
  return get(ctx, uid, id);
}

/** Leave any time: hidden from the standings at once, no badge for this tournament. */
export async function leave(ctx: CommunityCtx, uid: string, id: string): Promise<Tournament> {
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const t = await load(tx, id);
    if (!t || t.status === 'draft') throw notFound('tournament');
    // Once the close has started the field is frozen (finals are being written in batches).
    if (!t.finalizing_at && !t.closed_at) {
      await tx.execute(sql`
        update tournament_entries set left_at = ${now}
        where tournament_id = ${id} and user_id = ${uid} and left_at is null`);
    }
    await recomputeCommunityConsent(tx, uid, 'settings');
  });
  await ctx.cache.bumpNamespace('community');
  return get(ctx, uid, id);
}

const PAGE = 100;
const RANK_MAX = 2_147_483_647;

function encodeCursor(rank: number | null, handle: string) {
  return Buffer.from(JSON.stringify([rank ?? RANK_MAX, handle])).toString('base64url');
}
function decodeCursor(cursor: string | undefined): [number, string] | null {
  if (!cursor) return null;
  try {
    const v = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown;
    if (Array.isArray(v) && typeof v[0] === 'number' && typeof v[1] === 'string') return [v[0], v[1]];
  } catch {
    // fall through
  }
  throw badRequest('bad_cursor');
}

/**
 * Keyset condition after `(rank, handle)` in the order `rank asc nulls last, handle asc` — written
 * so the (tournament_id, rank) index can serve the order (no sort of every entry). RANK_MAX in a
 * cursor stands for a null rank (the unranked tail).
 */
function afterCursor(rankCol: SQL, after: [number, string] | null): SQL {
  if (!after) return sql``;
  const [rank, handle] = after;
  if (rank >= RANK_MAX) return sql`and ${rankCol} is null and pp.handle > ${handle}`;
  return sql`and (${rankCol} > ${rank} or ${rankCol} is null or (${rankCol} = ${rank} and pp.handle > ${handle}))`;
}

interface StandingsPage {
  rows: CompetitorRow[];
  total: number;
  snapshotDay: string | null;
  nextCursor: string | null;
}

/** Visible entries of a tournament ordered by (snapshot or final rank, handle), keyset-paged by 100. */
async function standingsPage(ctx: CommunityCtx, t: TournamentRecord, cursor: string | undefined, limit = PAGE): Promise<StandingsPage> {
  const closed = t.closed_at !== null;
  const after = decodeCursor(cursor);
  const json = await ctx.cache.getJson('community', `standings:${t.id}:${cursor ?? ''}:${limit}`, 60, async (): Promise<StandingsPage> => {
    const rankCol = closed ? sql.raw('e.final_rank') : sql.raw('e.snapshot_rank');
    const ptsCol = closed ? sql.raw('e.final_points') : sql.raw('e.snapshot_points');
    const visible = sql`e.tournament_id = ${t.id} and e.left_at is null and ${ACTIVE_USER} and coalesce(cm.banned_at is null, true)`;
    // A live tournament's filter implies the public photo rule; a closed one's entrants may be in no
    // live competition any more, so their photo shows only where the public route would serve it.
    const columns = closed || t.status !== 'published' ? COMPETITOR_COLUMNS_ANY : COMPETITOR_COLUMNS;
    const r = await ctx.db.execute<CompetitorRow>(sql`
      select ${columns}, ${ptsCol} as points, ${rankCol} as rank
      from tournament_entries e
      join users u on u.id = e.user_id
      ${COMPETITOR_JOINS}
      left join community_members cm on cm.user_id = u.id
      where ${visible}
        ${afterCursor(rankCol, after)}
      order by ${rankCol} asc nulls last, pp.handle asc
      limit ${limit + 1}`);
    const total = await ctx.db.execute<{ n: number }>(sql`
      select count(*)::int as n from tournament_entries e join users u on u.id = e.user_id
      left join community_members cm on cm.user_id = u.id where ${visible}`);
    const snap = await ctx.db.execute<{ day: string | null }>(sql`
      select max(day)::text as day from community_snapshot_days where day > ${localToday(new Date(t.starts_at))}::date`);
    const rows = r.rows.slice(0, limit);
    const last = rows[rows.length - 1];
    return {
      rows,
      total: Number(total.rows[0]?.n ?? 0),
      snapshotDay: closed ? localToday(new Date(t.ends_at)) : (snap.rows[0]?.day ?? null),
      nextCursor: r.rows.length > limit && last ? encodeCursor(last.rank === null ? null : Number(last.rank), last.handle) : null,
    };
  });
  return JSON.parse(json) as StandingsPage;
}

export async function standings(ctx: CommunityCtx, uid: string, id: string, cursor: string | undefined): Promise<TournamentStandings> {
  const t = await load(ctx.db, id);
  if (!t || t.status !== 'published') throw notFound('tournament');
  const page = await standingsPage(ctx, t, cursor);
  const blocked = await blockedBothWays(ctx.db, uid);
  const closed = t.closed_at !== null;
  // The caller's row isn't filtered on visibility: the full public photo rule.
  const mine = await ctx.db.execute<CompetitorRow>(sql`
    select ${COMPETITOR_COLUMNS_ANY}, ${closed ? sql.raw('e.final_points') : sql.raw('e.snapshot_points')} as points,
      ${closed ? sql.raw('e.final_rank') : sql.raw('e.snapshot_rank')} as rank
    from tournament_entries e join users u on u.id = e.user_id ${COMPETITOR_JOINS}
    where e.tournament_id = ${id} and e.user_id = ${uid} and e.left_at is null`);
  return {
    total: page.total,
    snapshotDay: page.snapshotDay,
    rows: personalise(ctx, page.rows, uid, blocked),
    me: mine.rows[0] ? toCompetitor(ctx, mine.rows[0], uid) : null,
    nextCursor: page.nextCursor,
  };
}

/* ------------------------------------------------------------------ admin */

export function adminRow(t: TournamentRecord, now: Date): AdminTournamentRow {
  return {
    ...base(t, now),
    status: t.status,
    closedAt: t.closed_at ? iso(t.closed_at) : null,
    minPoints: Number(t.min_points),
    createdBy: t.created_by,
  };
}

export async function adminList(ctx: CommunityCtx): Promise<AdminTournamentRow[]> {
  const r = await ctx.db.execute<TournamentRecord>(sql`
    select t.*, (select count(*) from tournament_entries e where e.tournament_id = t.id and e.left_at is null)::int as participants
    from tournaments t order by t.starts_at desc limit 200`);
  return r.rows.map((t) => adminRow(t, ctx.now()));
}

export async function adminGet(db: DbOrTx, id: string, now: Date): Promise<AdminTournamentRow> {
  const t = await load(db, id);
  if (!t) throw notFound('tournament');
  return adminRow(t, now);
}

const isUnique = (e: unknown) => {
  const code = (e as { code?: string; cause?: { code?: string } }).cause?.code ?? (e as { code?: string }).code;
  return code === '23505';
};

export async function create(tx: DbOrTx, input: AdminTournamentCreate, adminId: string, now: Date): Promise<AdminTournamentRow> {
  const w = tournamentWindow(input);
  if (validateTournament({ slug: input.slug, ...w }, now)) throw badRequest('tournament_dates', 'Whole Cairo days, start before end, at most 90 days');
  try {
    const r = await tx.execute<{ id: string }>(sql`
      insert into tournaments (slug, title_ar, title_en, body_ar, body_en, starts_at, ends_at, join_until, badge_ar, badge_en, min_points, status, created_by, created_at, updated_at)
      values (${input.slug}, ${input.titleAr}, ${input.titleEn}, ${input.bodyAr}, ${input.bodyEn}, ${w.startsAt}, ${w.endsAt}, ${w.joinUntil},
              ${input.badgeAr}, ${input.badgeEn}, ${input.minPoints}, 'draft', ${adminId}, ${now}, ${now})
      returning id`);
    return adminGet(tx, r.rows[0]!.id, now);
  } catch (e) {
    if (isUnique(e)) throw conflict('slug_taken', 'This slug is already used');
    throw e;
  }
}

/**
 * Draft: any field. Published and not started: any field except the slug. Live: only a later last
 * day, with a reason. Ended, closed or cancelled: nothing.
 */
export async function patch(tx: DbOrTx, id: string, input: AdminTournamentPatch, now: Date): Promise<{ before: AdminTournamentRow; after: AdminTournamentRow }> {
  const t = await load(tx, id, true);
  if (!t) throw notFound('tournament');
  const before = adminRow(t, now);
  if (t.status === 'cancelled' || t.closed_at || t.finalizing_at || now.getTime() >= new Date(t.ends_at).getTime()) {
    throw conflict('tournament_closed', 'This tournament has ended');
  }
  const days = tournamentDays({ startsAt: new Date(t.starts_at), endsAt: new Date(t.ends_at), joinUntil: new Date(t.join_until) });
  const live = t.status === 'published' && now.getTime() >= new Date(t.starts_at).getTime();
  const { reason, ...fields } = input;
  const changed = Object.entries(fields).filter(([, v]) => v !== undefined) as [keyof typeof fields, unknown][];

  if (live) {
    if (!reason) throw badRequest('reason_required', 'A reason is required to change a live tournament');
    if (changed.some(([k]) => k !== 'lastDay')) throw conflict('tournament_not_editable', 'A live tournament can only end later');
    if (!input.lastDay || input.lastDay <= days.lastDay) throw conflict('tournament_not_editable', 'A live tournament can only end later');
  } else if (t.status === 'published' && input.slug !== undefined && input.slug !== t.slug) {
    throw conflict('tournament_not_editable', 'The slug of a published tournament is fixed');
  }

  const merged = {
    slug: input.slug ?? t.slug,
    startsOn: input.startsOn ?? days.startsOn,
    lastDay: input.lastDay ?? days.lastDay,
    joinLastDay: input.joinLastDay ?? (input.lastDay && days.joinLastDay === days.lastDay && !live ? input.lastDay : days.joinLastDay),
  };
  const w = tournamentWindow(merged);
  if (validateTournament({ slug: merged.slug, ...w }, now)) throw badRequest('tournament_dates', 'Whole Cairo days, start before end, at most 90 days');
  try {
    await tx.execute(sql`
      update tournaments set
        slug = ${merged.slug},
        title_ar = ${input.titleAr ?? t.title_ar}, title_en = ${input.titleEn ?? t.title_en},
        body_ar = ${input.bodyAr ?? t.body_ar}, body_en = ${input.bodyEn ?? t.body_en},
        starts_at = ${w.startsAt}, ends_at = ${w.endsAt}, join_until = ${w.joinUntil},
        badge_ar = ${input.badgeAr ?? t.badge_ar}, badge_en = ${input.badgeEn ?? t.badge_en},
        min_points = ${input.minPoints ?? t.min_points}, updated_at = ${now}
      where id = ${id}`);
  } catch (e) {
    if (isUnique(e)) throw conflict('slug_taken', 'This slug is already used');
    throw e;
  }
  return { before, after: await adminGet(tx, id, now) };
}

export async function publish(tx: DbOrTx, id: string, now: Date) {
  const t = await load(tx, id, true);
  if (!t) throw notFound('tournament');
  if (t.status !== 'draft') throw conflict('tournament_not_editable', 'Only a draft can be published');
  if (now.getTime() >= new Date(t.ends_at).getTime()) throw badRequest('tournament_dates', 'This window is already over');
  const before = adminRow(t, now);
  await tx.execute(sql`update tournaments set status = 'published', updated_at = ${now} where id = ${id}`);
  return { before, after: await adminGet(tx, id, now) };
}

/** Early close: the window ends at the next Cairo midnight (today still counts); the job closes it after. */
export async function closeEarly(tx: DbOrTx, id: string, now: Date) {
  const t = await load(tx, id, true);
  if (!t) throw notFound('tournament');
  if (t.status !== 'published' || t.closed_at || t.finalizing_at) throw conflict('tournament_closed', 'This tournament is not running');
  const endsAt = cairoMidnight(addDays(localToday(now), 1));
  if (endsAt.getTime() <= new Date(t.starts_at).getTime()) throw conflict('tournament_not_editable', 'Cancel a tournament that has not started');
  const before = adminRow(t, now);
  if (endsAt.getTime() < new Date(t.ends_at).getTime()) {
    await tx.execute(sql`
      update tournaments set ends_at = ${endsAt}, join_until = least(join_until, ${endsAt}), updated_at = ${now} where id = ${id}`);
  }
  return { before, after: await adminGet(tx, id, now) };
}

/** Cancel: no badges; every entrant's community consent is recomputed (source system). */
export async function cancel(tx: DbOrTx, id: string, now: Date) {
  const t = await load(tx, id, true);
  if (!t) throw notFound('tournament');
  if (t.status === 'cancelled' || t.closed_at) throw conflict('tournament_closed', 'This tournament is already over');
  const before = adminRow(t, now);
  await tx.execute(sql`update tournaments set status = 'cancelled', updated_at = ${now} where id = ${id}`);
  await recomputeCommunityConsentMany(tx, sql`select user_id from tournament_entries where tournament_id = ${id}`, 'system');
  return { before, after: await adminGet(tx, id, now) };
}

/** Top standings for the admin (snapshot, or finals once closed) with user ids. */
export async function adminStandings(ctx: CommunityCtx, id: string, limit: number): Promise<{ snapshotDay: string | null; total: number; rows: AdminStandingRow[] }> {
  const t = await load(ctx.db, id);
  if (!t) throw notFound('tournament');
  const page = await standingsPage(ctx, t, undefined, limit);
  return { snapshotDay: page.snapshotDay, total: page.total, rows: page.rows.map((r) => ({ ...toCompetitor(ctx, r, null), userId: r.user_id })) };
}

/** Aggregates only, each suppressed under K_ANONYMITY. */
export async function stats(ctx: CommunityCtx, id: string): Promise<AdminTournamentStats> {
  const t = await load(ctx.db, id);
  if (!t) throw notFound('tournament');
  const col = t.closed_at ? sql.raw('final_points') : sql.raw('snapshot_points');
  const r = await ctx.db.execute<{ participants: number; active: number; median: number | null; b0: number; b1: number; b2: number; b3: number; b4: number }>(sql`
    select count(*)::int as participants,
      count(*) filter (where coalesce(${col}, 0) > 0)::int as active,
      percentile_cont(0.5) within group (order by coalesce(${col}, 0)) as median,
      count(*) filter (where coalesce(${col}, 0) = 0)::int as b0,
      count(*) filter (where ${col} between 1 and 99)::int as b1,
      count(*) filter (where ${col} between 100 and 499)::int as b2,
      count(*) filter (where ${col} between 500 and 999)::int as b3,
      count(*) filter (where ${col} >= 1000)::int as b4
    from tournament_entries where tournament_id = ${id} and left_at is null`);
  const s = r.rows[0]!;
  const n = Number(s.participants);
  const badges = await ctx.db.execute<{ kind: string; n: number }>(sql`
    select kind, count(*)::int as n from user_badges where ref_key = ${`tournament:${id}`} group by kind`);
  const byKind = new Map(badges.rows.map((b) => [b.kind, Number(b.n)]));
  return {
    participants: suppress(n),
    active: suppress(Number(s.active)),
    median: n >= 20 && s.median !== null ? Number(s.median) : null,
    buckets: [
      { label: '0', count: suppress(Number(s.b0)) },
      { label: '1–99', count: suppress(Number(s.b1)) },
      { label: '100–499', count: suppress(Number(s.b2)) },
      { label: '500–999', count: suppress(Number(s.b3)) },
      { label: '1000+', count: suppress(Number(s.b4)) },
    ],
    badges: BADGE_KINDS.filter((k) => k.startsWith('tournament_')).map((kind) => ({ kind, count: suppress(byKind.get(kind) ?? 0) })),
  };
}

/* -------------------------------------------------------------------- job */

const FINAL_BATCH = 1000;

/**
 * Job step 4: close every published tournament past its end. Finals are deterministic (window days
 * are before `ends_at`; a late qada lands after it), written for entries without finals in batches
 * of 1,000 with their badges, then `closed_at` and the entrants' consent in one short transaction.
 * A crash resumes from the entries still without finals. `maxBatches` stops early (tests).
 */
export async function closeDueTournaments(ctx: CommunityCtx, opts: { maxBatches?: number; batchSize?: number } = {}): Promise<{ closed: number; batches: number }> {
  const now = ctx.now();
  const size = opts.batchSize ?? FINAL_BATCH;
  let closed = 0;
  let batches = 0;
  const due = await ctx.db.execute<TournamentRecord>(sql`
    select t.*, 0 as participants from tournaments t
    where t.status = 'published' and t.ends_at <= ${now} and t.closed_at is null order by t.ends_at, t.id`);
  for (const t of due.rows) {
    const f = await ctx.db.execute<{ at: Date }>(sql`
      update tournaments set finalizing_at = coalesce(finalizing_at, ${now}) where id = ${t.id} returning finalizing_at as at`);
    const finalizingAt = new Date(f.rows[0]!.at);
    const w = windowDays(t);
    // The field is frozen when finalizing starts: someone removed after that (ban, erasure) keeps
    // their place in the ranking so a resumed close ranks the same set; they get no badge.
    const r = await ctx.db.execute<{ user_id: string; handle: string; points: number; has_final: boolean; gone: boolean }>(sql`
      select e.user_id, coalesce(pp.handle, e.user_id::text) as handle, (e.final_points is not null) as has_final, (e.left_at is not null) as gone,
        coalesce((select sum(d.earned) from points_earned_daily d where d.user_id = e.user_id and d.day >= ${w.from}::date and d.day < ${w.to}::date), 0)::int as points
      from tournament_entries e left join public_profiles pp on pp.user_id = e.user_id
      where e.tournament_id = ${t.id} and (e.left_at is null or e.left_at >= ${finalizingAt})`);
    const gone = new Set(r.rows.filter((x) => x.gone).map((x) => x.user_id));
    const n = r.rows.length;
    const standingsAll = rankStandings(r.rows.map((x) => ({ userId: x.user_id, handle: x.handle, points: Number(x.points) })));
    const pending = new Set(r.rows.filter((x) => !x.has_final).map((x) => x.user_id));
    const todo = standingsAll.filter((s) => pending.has(s.userId));
    for (let i = 0; i < todo.length; i += size) {
      if (opts.maxBatches !== undefined && batches >= opts.maxBatches) return { closed, batches };
      const chunk = todo.slice(i, i + size);
      await ctx.db.transaction(async (tx) => {
        const finals = chunk.map((s) => ({ u: s.userId, p: s.points, r: s.rank }));
        await tx.execute(sql`
          update tournament_entries e set final_points = x.p, final_rank = x.r
          from jsonb_to_recordset(${JSON.stringify(finals)}::jsonb) as x(u uuid, p int, r int)
          where e.tournament_id = ${t.id} and e.user_id = x.u and e.final_points is null`);
        const awards: AwardRow[] = [];
        for (const s of chunk) {
          if (gone.has(s.userId)) continue;
          const kind = tournamentBadge(s.position, n, s.points, Number(t.min_points));
          if (!kind) continue;
          awards.push({
            userId: s.userId,
            kind,
            refKey: `tournament:${t.id}`,
            meta: { tournamentId: t.id, titleAr: t.title_ar, titleEn: t.title_en, rank: s.rank ?? undefined, size: n, labelAr: t.badge_ar, labelEn: t.badge_en },
          });
        }
        await awardBadges(tx, awards, now);
      });
      batches++;
    }
    await ctx.db.transaction(async (tx) => {
      await tx.execute(sql`update tournaments set closed_at = ${now}, updated_at = ${now} where id = ${t.id} and closed_at is null`);
      await recomputeCommunityConsentMany(tx, sql`select user_id from tournament_entries where tournament_id = ${t.id}`, 'system');
    });
    closed++;
  }
  if (closed || batches) await ctx.cache.bumpNamespace('community');
  return { closed, batches };
}

/** Throws when a tournament id is not a UUID (route param guard). */
export function assertId(id: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new AppError(404, 'not_found', 'tournament not found');
}
