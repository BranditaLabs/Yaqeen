/**
 * Scale (design §13, item 28): with ~50k competitors, the level board (top 100 + me) and a tournament
 * standings page read the snapshot indexes and never scan `points_ledger` or `points_earned_daily`.
 * The SQL the routes really send is captured from the pool and EXPLAINed with its parameters.
 * Skipped without TEST_DATABASE_URL.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { type Harness, TEST_DB_URL, auth, setFlags, setup } from './community.helpers.js';
import { signUserToken } from '../src/lib/tokens.js';

const N = 50_000;

interface PlanNode {
  'Node Type': string;
  'Relation Name'?: string;
  'Index Name'?: string;
  Plans?: PlanNode[];
}

function nodes(p: PlanNode): PlanNode[] {
  return [p, ...(p.Plans ?? []).flatMap(nodes)];
}

describe.skipIf(!TEST_DB_URL)('community at scale (Postgres)', () => {
  let h: Harness;
  let captured: { text: string; values: unknown[] }[] = [];
  let tournamentId: string;
  let token: string;

  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
    await setFlags(h, { leagues: true, tournaments: true, leaderboard: true });
    // Fast set-based seed: users, handles, switches, rollups, a snapshot and a tournament.
    await h.db.execute(sql.raw(`
      insert into users (display_name, adult_attested_at, country)
      select 'Member ' || g, now(), case when g % 3 = 0 then 'EG' else 'SA' end from generate_series(1, ${N}) g`));
    await h.db.execute(sql.raw(`
      insert into public_profiles (user_id, handle, display_name, show)
      select id, 'm-' || substr(replace(id::text, '-', ''), 1, 12), display_name, '{}'::jsonb from users`));
    await h.db.execute(sql.raw(`insert into community_members (user_id, leaderboard, leaderboard_country) select id, true, true from users`));
    await h.db.execute(sql.raw(`
      insert into points_earned_daily (user_id, day, earned)
      select u.id, d::date, 10 + (abs(hashtext(u.id::text || d::text)) % 90)
      from users u cross join generate_series('2026-11-04'::date, '2026-11-10'::date, interval '1 day') d`));
    await h.db.execute(sql.raw(`
      insert into user_point_totals (user_id, lifetime_earned, public_lifetime, public_day)
      select user_id, sum(earned), sum(earned), '2026-11-11' from points_earned_daily group by user_id`));
    await h.db.execute(sql.raw(`
      insert into leaderboard_snapshot (scope, country, user_id, rank, lifetime, day)
      select 'global', '', user_id, rank() over (order by public_lifetime desc), public_lifetime, '2026-11-11' from user_point_totals`));
    const t = await h.db.execute<{ id: string }>(sql`
      insert into tournaments (slug, title_ar, title_en, starts_at, ends_at, join_until, badge_ar, badge_en, status)
      values ('scale-cup', 'ك', 'Cup', '2026-11-03T22:00:00Z', '2026-11-30T22:00:00Z', '2026-11-30T22:00:00Z', 'ب', 'B', 'published') returning id`);
    tournamentId = t.rows[0]!.id;
    await h.db.execute(sql`
      insert into tournament_entries (tournament_id, user_id, snapshot_points, snapshot_rank)
      select ${tournamentId}::uuid, user_id, public_lifetime, rank() over (order by public_lifetime desc) from user_point_totals`);
    await h.db.execute(sql.raw(`insert into community_snapshot_days (day) values ('2026-11-11')`));
    await h.db.execute(sql.raw('analyze'));

    const me = await h.db.execute<{ id: string }>(sql.raw(`select user_id as id from leaderboard_snapshot where rank > 30000 limit 1`));
    token = await signUserToken({ sub: me.rows[0]!.id, guest: false }, h.env.JWT_SECRET);

    // Record every statement the app sends through the pool.
    const original = h.pool.query.bind(h.pool) as (...a: unknown[]) => unknown;
    (h.pool as unknown as { query: (...a: unknown[]) => unknown }).query = (...args: unknown[]) => {
      const [cfg, values] = args as [string | { text: string }, unknown[] | undefined];
      captured.push({ text: typeof cfg === 'string' ? cfg : cfg.text, values: values ?? [] });
      return original(...args);
    };
  }, 600_000);
  afterAll(async () => h?.close());

  async function plansFor(match: RegExp): Promise<PlanNode[][]> {
    const hits = captured.filter((q) => !q.text.startsWith('explain') && match.test(q.text));
    expect(hits.length).toBeGreaterThan(0);
    const out: PlanNode[][] = [];
    for (const q of hits) {
      const r = await h.pool.query<{ 'QUERY PLAN': { Plan: PlanNode }[] }>(`explain (format json) ${q.text}`, q.values as unknown[]);
      out.push(nodes(r.rows[0]!['QUERY PLAN'][0]!.Plan));
    }
    return out;
  }

  const scansOf = (plan: PlanNode[], rel: string) => plan.filter((n) => n['Relation Name'] === rel);

  it('the level board (top 100 + me) reads leaderboard_snapshot by its rank index', async () => {
    captured = [];
    await h.ctx.cache.bumpNamespace('community');
    const res = await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().rows).toHaveLength(100);
    expect(res.json().me.rank).toBeGreaterThan(30000);

    const plans = await plansFor(/from leaderboard_snapshot s|left join leaderboard_snapshot s/);
    for (const plan of plans) {
      expect(scansOf(plan, 'points_ledger')).toEqual([]);
      expect(scansOf(plan, 'points_earned_daily')).toEqual([]);
      expect(scansOf(plan, 'leaderboard_snapshot').every((n) => n['Node Type'] !== 'Seq Scan')).toBe(true);
    }
    const top = plans.find((p) => p.some((n) => n['Index Name'] === 'leaderboard_snapshot_rank_idx'));
    expect(top).toBeDefined();
  });

  it('a tournament standings page (and the next one) reads tournament_entries by its snapshot index', async () => {
    captured = [];
    await h.ctx.cache.bumpNamespace('community');
    const first = await h.app.inject({ method: 'GET', url: `/v1/tournaments/${tournamentId}/standings`, headers: auth(token) });
    expect(first.statusCode).toBe(200);
    const page = first.json();
    expect(page.rows).toHaveLength(100);
    expect(page.total).toBe(N);
    expect(page.nextCursor).toBeTruthy();
    const second = await h.app.inject({ method: 'GET', url: `/v1/tournaments/${tournamentId}/standings?cursor=${page.nextCursor}`, headers: auth(token) });
    const next = second.json().rows;
    expect(next).toHaveLength(100);
    expect(next[0].rank).toBeGreaterThanOrEqual(page.rows[99].rank);
    expect(new Set([...page.rows, ...next].map((r: { handle: string }) => r.handle)).size).toBe(200);

    // Every query stays off the ledger and the daily rollup; the pages and the caller's row are
    // served by an index (the visible-entries count may read the tournament's entries in full).
    for (const plan of await plansFor(/from tournament_entries e/)) {
      expect(scansOf(plan, 'points_ledger')).toEqual([]);
      expect(scansOf(plan, 'points_earned_daily')).toEqual([]);
    }
    const ordered = await plansFor(/from tournament_entries e[\s\S]*(order by|e\.user_id =)/);
    for (const plan of ordered) expect(scansOf(plan, 'tournament_entries').every((n) => n['Node Type'] !== 'Seq Scan')).toBe(true);
    expect(ordered.some((p) => p.some((n) => n['Index Name'] === 'tournament_entries_snapshot_idx'))).toBe(true);
  });
});
