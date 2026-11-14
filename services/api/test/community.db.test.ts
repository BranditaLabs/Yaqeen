/**
 * Community against Postgres (design §13): flags, opt-in + attestation + derived consent, the
 * snapshot rule (nothing public is live), placement and `closing`, the close step (boundary ties,
 * solo groups, divisions, badges, resumable, idempotent, late qada), settings per week, concurrent
 * placement, tournaments end to end, and that competitions never write the ledger.
 * Skipped without TEST_DATABASE_URL — run with --no-file-parallelism.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { cairoMidnight } from '../src/domain/community.js';
import { runCommunity } from '../src/jobs/community.js';
import { closeDueWeeks, ensurePlacement, ensureWeek } from '../src/services/leagues.service.js';
import { takeNightlySnapshot } from '../src/services/snapshots.service.js';
import { closeDueTournaments } from '../src/services/tournaments.service.js';
import { POLICY_VERSION } from '../src/services/community.service.js';
import {
  type Harness,
  TEST_DB_URL,
  auth,
  consentEventsFor,
  earn,
  ledgerCount,
  makeAdmin,
  makeUser,
  optIn,
  setFlags,
  setup,
} from './community.helpers.js';

const ALL_ON = { leagues: true, tournaments: true, leaderboard: true };

describe.skipIf(!TEST_DB_URL)('community: opt-in, snapshots and the weekly close (Postgres)', () => {
  let h: Harness;
  // Wednesday 2026-11-11, 10:00 Cairo — week of Saturday 2026-11-07.
  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
  });
  afterAll(async () => h?.close());

  let omar: { id: string; token: string };
  let sara: { id: string; token: string };

  it('competitions answer feature_off until an admin turns the flag on', async () => {
    omar = await makeUser(h, 'Omar Ali');
    expect((await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json().error.code).toBe('feature_off');
    expect((await h.app.inject({ method: 'GET', url: '/v1/tournaments', headers: auth(omar.token) })).statusCode).toBe(403);
    expect((await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(omar.token) })).statusCode).toBe(403);
    const res = await optIn(h, omar.token, { leagues: true });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('feature_off');
    const cfg = (await h.app.inject({ method: 'GET', url: '/v1/config' })).json();
    expect(cfg.features).toMatchObject({ leagues: false, tournaments: false, leaderboard: false });
    await setFlags(h, ALL_ON);
  });

  it('opting in needs the attestation and a valid name; a draft handle never carries the full name', async () => {
    const noAttest = await h.app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(omar.token), payload: { leagues: true } });
    expect(noAttest.statusCode).toBe(400);
    expect(noAttest.json().error.code).toBe('attestation_required');

    const nameless = await makeUser(h, null);
    expect((await optIn(h, nameless.token, { leagues: true })).json().error.code).toBe('name_required');
    expect((await optIn(h, nameless.token, { leagues: true, displayName: 'فريق يقين' })).json().error.code).toBe('invalid_name');

    const ok = await optIn(h, omar.token, { leagues: true, source: 'onboarding' });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ leagues: true, leaderboard: false, leaderboardCountry: false, banned: false, attestedAdult: true, country: null });
    const me = (await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(omar.token) })).json();
    expect(me.handle).toMatch(/^omar-\d{4}$/);
    expect(me.community.leagues).toBe(true);
    // The consent event of a join carries the attestation and the source.
    expect(await consentEventsFor(h, omar.id)).toEqual([{ granted: true, source: 'onboarding', attested_adult: true, policy_version: POLICY_VERSION }]);
    const audit = await h.db.execute(sql`select 1 from audit_log where actor_user_id = ${omar.id} and action = 'user.attest_adult'`);
    expect(audit.rows).toHaveLength(1);

    sara = await makeUser(h, 'سارة أحمد');
    await optIn(h, sara.token, { leagues: true, leaderboard: true });
    const sp = (await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(sara.token) })).json();
    expect(sp.handle).toMatch(/^member-[a-z0-9]{6}$/);
  });

  it('nothing public is live: a ledger insert changes no public view until the nightly snapshot', async () => {
    const before = await ledgerCount(h);
    let cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur).toMatchObject({ state: 'joined', startsOn: '2026-11-07', division: 1, size: 2, snapshotDay: null, myLivePoints: 0 });
    expect(cur.rows.map((r: { points: number | null; rank: number | null }) => [r.points, r.rank])).toEqual([[null, null], [null, null]]);

    await earn(h, omar.id, 50, '2026-11-09T10:00:00Z');
    await earn(h, sara.id, 30, '2026-11-10T10:00:00Z');
    await h.app.ctx.cache.bumpNamespace('community'); // even with a cold cache nothing moves
    cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur.myLivePoints).toBe(50); // the caller's own live points…
    expect(cur.rows.every((r: { points: number | null }) => r.points === null)).toBe(true); // …never in a row
    const board0 = (await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(sara.token) })).json();
    expect(board0).toMatchObject({ joined: true, rows: [], snapshotDay: null });
    expect(board0.me).toMatchObject({ rank: null, points: null, level: { level: 1, progress: 0 } });

    expect(await takeNightlySnapshot(h.ctx)).toEqual({ taken: true, day: '2026-11-11' });
    cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur.snapshotDay).toBe('2026-11-11');
    expect(cur.rows.map((r: { points: number; rank: number; me: boolean }) => [r.points, r.rank, r.me])).toEqual([[50, 1, true], [30, 2, false]]);
    expect(JSON.stringify(cur)).not.toMatch(/userId|user_id|five_prayers|wird|azkar/);

    // A point today stays private until tomorrow's snapshot; a second snapshot the same day is skipped.
    await earn(h, sara.id, 100, '2026-11-11T09:00:00Z');
    await earn(h, sara.id, 600, '2026-11-11T09:30:00Z', 'bonus');
    expect((await takeNightlySnapshot(h.ctx)).taken).toBe(false);
    await h.app.ctx.cache.bumpNamespace('community');
    cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur.rows.map((r: { points: number }) => r.points)).toEqual([50, 30]);
    const board1 = (await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(sara.token) })).json();
    expect(board1.me).toMatchObject({ rank: 1, level: { level: 1 } }); // 30 public lifetime, not 760

    h.setNow('2026-11-11T22:30:00Z'); // Thursday 00:30 Cairo
    expect((await takeNightlySnapshot(h.ctx)).taken).toBe(true);
    cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur.rows.map((r: { points: number; rank: number }) => [r.points, r.rank])).toEqual([[730, 1], [50, 2]]);
    const board2 = (await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(sara.token) })).json();
    expect(board2.me.level.level).toBe(2); // 730 ≥ 500
    expect(await ledgerCount(h)).toBe(before + 4); // only the test's own inserts
  });

  it('withdrawing the community consent leaves everything; granting it there is refused', async () => {
    const tmp = await makeUser(h, 'Khaled');
    await optIn(h, tmp.token, { leagues: true, leaderboard: true });
    await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(tmp.token) });
    const res = await h.app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(tmp.token), payload: { kind: 'community', granted: false, source: 'settings' } });
    expect(res.statusCode).toBe(200);
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/community', headers: auth(tmp.token) })).json()).toMatchObject({ leagues: false, leaderboard: false });
    const left = await h.db.execute(sql`select left_at from league_members where user_id = ${tmp.id}`);
    expect(left.rows[0]!.left_at).not.toBeNull();
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/consents', headers: auth(tmp.token) })).json().community).toBe(false);
    const events = await consentEventsFor(h, tmp.id);
    expect(events.at(-1)).toMatchObject({ granted: false, source: 'settings' });
    const grant = await h.app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(tmp.token), payload: { kind: 'community', granted: true, source: 'settings' } });
    expect(grant.json().error.code).toBe('use_community_settings');
  });

  it('settings changed mid-week apply from the next week; this week keeps its zones', async () => {
    const mk = await makeAdmin(h, 'marketing');
    const bad = await h.app.inject({ method: 'PUT', url: '/admin/competitions/leagues/settings', headers: auth(mk.token), payload: { groupSize: 10, promote: 5, demote: 5 } });
    expect(bad.json().error.code).toBe('settings_invalid');
    const put = await h.app.inject({ method: 'PUT', url: '/admin/competitions/leagues/settings', headers: auth(mk.token), payload: { groupSize: 20, promote: 2, demote: 3 } });
    expect(put.statusCode).toBe(200);
    const audit = await h.db.execute(sql`select 1 from audit_log where admin_id = ${mk.id} and action = 'leagues.settings'`);
    expect(audit.rows).toHaveLength(1);
    const thisWeek = await h.db.execute<{ settings: { promote: number; groupSize: number } }>(sql`select settings from league_weeks where starts_on = '2026-11-07'`);
    expect(thisWeek.rows[0]!.settings).toMatchObject({ promote: 5, groupSize: 30 });
    const stats = (await h.app.inject({ method: 'GET', url: '/admin/competitions/leagues/stats', headers: auth(mk.token) })).json();
    expect(stats.settingsInForce).toMatchObject({ promote: 5, demote: 5, groupSize: 30 });
    expect(stats.members.find((m: { division: number }) => m.division === 1).count).toBeNull(); // < 20 suppressed
    const next = await ensureWeek(h.db, h.ctx, '2026-11-14', true);
    expect(next).toMatchObject({ groupSize: 20, promote: 2, demote: 3 });
  });

  it('at Saturday 00:01 before the job: closing, not placed; after the close: placed with last week’s result', async () => {
    h.setNow('2026-11-13T22:01:00Z'); // Saturday 2026-11-14 00:01 Cairo
    const before = await ledgerCount(h);
    expect((await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json()).toEqual({ state: 'closing' });
    const none = await h.db.execute(sql`select 1 from league_members where starts_on = '2026-11-14'`);
    expect(none.rows).toHaveLength(0);

    const r1 = await runCommunity(h.ctx);
    expect(r1).toMatchObject({ weeksClosed: 1, groupsClosed: 1 });
    const cur = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(omar.token) })).json();
    expect(cur).toMatchObject({ state: 'joined', startsOn: '2026-11-14', division: 1 });
    // Two members → no zones; finals from the whole week (Omar 50, Sara 730).
    expect(cur.lastWeek).toMatchObject({ startsOn: '2026-11-07', division: 1, newDivision: 1, rank: 2, outcome: 'stay', badge: null });
    const finals = await h.db.execute<{ user_id: string; final_points: number; final_rank: number }>(sql`
      select user_id, final_points, final_rank from league_members where starts_on = '2026-11-07' and left_at is null order by final_rank`);
    expect(finals.rows.map((x) => [x.user_id, x.final_points, x.final_rank])).toEqual([[sara.id, 730, 1], [omar.id, 50, 2]]);

    // Running the job again changes nothing; the ledger is untouched by competitions.
    const r2 = await runCommunity(h.ctx);
    expect(r2).toMatchObject({ weeksClosed: 0, groupsClosed: 0 });
    expect(await ledgerCount(h)).toBe(before);
    const history = (await h.app.inject({ method: 'GET', url: '/v1/leagues/history', headers: auth(omar.token) })).json();
    expect(history).toEqual([{ startsOn: '2026-11-07', division: 1, rank: 2, size: 2, points: 50, outcome: 'stay' }]);
  });
});

describe.skipIf(!TEST_DB_URL)('community: closing a week (Postgres)', () => {
  let h: Harness;
  beforeAll(async () => {
    h = await setup('2026-11-08T08:00:00Z'); // Sunday of the week of 2026-11-07; the week of 10-31 is due
    await setFlags(h, ALL_ON);
  });
  afterAll(async () => h?.close());

  const users: Record<string, string> = {};

  async function seedGroup(division: number, members: [string, number][]) {
    const g = await h.db.execute<{ id: string }>(sql`
      insert into league_groups (starts_on, division, size) values ('2026-10-31', ${division}, ${members.length}) returning id`);
    for (const [name, pts] of members) {
      const u = await makeUser(h, name, { attested: true });
      users[name] = u.id;
      await h.db.execute(sql`insert into community_members (user_id, leagues, division) values (${u.id}, true, ${division})`);
      await h.db.execute(sql`insert into public_profiles (user_id, handle, display_name, show) values (${u.id}, ${name.toLowerCase()}, ${name}, '{}'::jsonb)`);
      await h.db.execute(sql`
        insert into league_members (starts_on, user_id, group_id, division) values ('2026-10-31', ${u.id}, ${g.rows[0]!.id}, ${division})`);
      if (pts > 0) await earn(h, u.id, pts, '2026-11-02T10:00:00Z');
    }
  }

  it('boundary ties promote together, the bottom goes down, a solo group never moves; resumable and idempotent', async () => {
    await h.db.execute(sql`
      insert into league_weeks (starts_on, starts_at, ends_at, settings)
      values ('2026-10-31', ${cairoMidnight('2026-10-31')}, ${cairoMidnight('2026-11-07')}, ${JSON.stringify({ groupSize: 30, promote: 5, demote: 5 })}::jsonb)`);
    // Size 7 → each zone capped at floor(7/3) = 2.
    await seedGroup(3, [['aa', 90], ['bb', 50], ['cc', 50], ['dd', 40], ['ee', 30], ['ff', 20], ['gg', 10]]);
    await seedGroup(2, [['solo', 500]]);
    const before = await ledgerCount(h);

    // A "crash" after the first group: the week stays open and the next run finishes it.
    expect(await closeDueWeeks(h.ctx, { maxGroups: 1 })).toEqual({ weeks: 0, groups: 1 });
    const open = await h.db.execute<{ status: string }>(sql`select status from league_weeks where starts_on = '2026-10-31'`);
    expect(open.rows[0]!.status).toBe('open');
    expect(await closeDueWeeks(h.ctx)).toEqual({ weeks: 1, groups: 1 });

    const rows = await h.db.execute<{ user_id: string; final_rank: number | null; outcome: string }>(sql`
      select user_id, final_rank, outcome from league_members where starts_on = '2026-10-31'`);
    const by = new Map(rows.rows.map((r) => [r.user_id, r]));
    const out = (n: string) => [by.get(users[n]!)!.final_rank, by.get(users[n]!)!.outcome];
    expect(out('aa')).toEqual([1, 'up']);
    expect(out('bb')).toEqual([2, 'up']);
    expect(out('cc')).toEqual([2, 'up']); // tied at the boundary: both go up
    expect(out('dd')).toEqual([4, 'stay']);
    expect(out('ee')).toEqual([5, 'stay']);
    expect(out('ff')).toEqual([6, 'down']);
    expect(out('gg')).toEqual([7, 'down']);
    expect(out('solo')).toEqual([1, 'stay']);

    const divs = await h.db.execute<{ user_id: string; division: number }>(sql`select user_id, division from community_members`);
    const d = new Map(divs.rows.map((r) => [r.user_id, Number(r.division)]));
    expect([d.get(users.aa!), d.get(users.cc!), d.get(users.dd!), d.get(users.gg!), d.get(users.solo!)]).toEqual([4, 4, 3, 2, 2]);

    const badges = await h.db.execute<{ user_id: string; kind: string; ref_key: string }>(sql`select user_id, kind, ref_key from user_badges order by kind, ref_key`);
    const has = (n: string) => badges.rows.filter((b) => b.user_id === users[n]).map((b) => `${b.kind}:${b.ref_key}`).sort();
    expect(has('aa')).toEqual(['division_reached:division:4', 'league_first:league:2026-10-31']);
    expect(has('cc')).toEqual(['division_reached:division:4', 'league_top3:league:2026-10-31']);
    expect(has('ff')).toEqual([]);
    expect(has('solo')).toEqual([]); // a solo group earns no first/top 3

    // Continuing members are packed into next week at their new division.
    const next = await h.db.execute<{ division: number; n: number }>(sql`
      select division, count(*)::int as n from league_members where starts_on = '2026-11-07' group by division order by division`);
    expect(next.rows.map((r) => [Number(r.division), r.n])).toEqual([[2, 3], [3, 2], [4, 3]]);

    // A late qada (claimed now, after the close) never changes the frozen finals; a second run is a no-op.
    await earn(h, users.gg!, 300, '2026-11-08T08:00:00Z', 'qada');
    expect(await closeDueWeeks(h.ctx)).toEqual({ weeks: 0, groups: 0 });
    const gg = await h.db.execute<{ final_points: number; outcome: string }>(sql`
      select final_points, outcome from league_members where starts_on = '2026-10-31' and user_id = ${users.gg!}`);
    expect(gg.rows[0]).toMatchObject({ final_points: 10, outcome: 'down' });
    const badgeCount = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from user_badges`);
    expect(badgeCount.rows[0]!.n).toBe(badges.rows.length);
    expect(await ledgerCount(h)).toBe(before + 1);
  });

  it('concurrent placements fill a group of 30 before opening another', async () => {
    const ids: string[] = [];
    for (let i = 0; i < 35; i++) {
      const u = await makeUser(h, `Member ${i}`, { attested: true });
      await h.db.execute(sql`insert into community_members (user_id, leagues, division) values (${u.id}, true, 5)`);
      ids.push(u.id);
    }
    const results = await Promise.all(ids.map((id) => ensurePlacement(h.ctx, id)));
    expect(results.every((r) => r.state === 'placed')).toBe(true);
    const groups = await h.db.execute<{ size: number; n: number }>(sql`
      select g.size, (select count(*) from league_members m where m.group_id = g.id)::int as n
      from league_groups g where g.starts_on = '2026-11-07' and g.division = 5 order by g.size desc`);
    expect(groups.rows.map((g) => [Number(g.size), g.n])).toEqual([[30, 30], [5, 5]]);
  });
});

describe.skipIf(!TEST_DB_URL)('community: tournaments (Postgres)', () => {
  let h: Harness;
  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
    await setFlags(h, ALL_ON);
  });
  afterAll(async () => h?.close());

  it('create → publish → join → snapshot → batched close with badges and consent; cancel recomputes consent', async () => {
    const mk = await makeAdmin(h, 'marketing');
    const sup = await makeAdmin(h, 'support');
    const base = { slug: 'nov-cup', titleAr: 'كأس نوفمبر', titleEn: 'November cup', bodyAr: '', bodyEn: '', badgeAr: 'كأس', badgeEn: 'Cup', minPoints: 10 };
    const wrong = await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, startsOn: '2026-11-12', lastDay: '2026-11-10' } });
    expect(wrong.json().error.code).toBe('tournament_dates');
    expect((await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(sup.token), payload: base })).statusCode).toBe(403);
    const created = await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, startsOn: '2026-11-10', lastDay: '2026-11-12' } });
    expect(created.statusCode).toBe(200);
    const t = created.json();
    // Whole Cairo days: start and end are Cairo midnights, the end exclusive.
    expect(t).toMatchObject({ status: 'draft', startsAt: '2026-11-09T22:00:00.000Z', endsAt: '2026-11-12T22:00:00.000Z', joinUntil: '2026-11-12T22:00:00.000Z' });
    const dup = await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, startsOn: '2026-11-10', lastDay: '2026-11-12' } });
    expect(dup.json().error.code).toBe('slug_taken');

    const u1 = await makeUser(h, 'Huda');
    expect((await h.app.inject({ method: 'GET', url: '/v1/tournaments', headers: auth(u1.token) })).json()).toEqual([]);
    await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${t.id}/publish`, headers: auth(mk.token), payload: {} });
    const list = (await h.app.inject({ method: 'GET', url: '/v1/tournaments', headers: auth(u1.token) })).json();
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ phase: 'live', joined: false, me: null, participants: 0 });

    // A live tournament may only end later, with a reason.
    const noReason = await h.app.inject({ method: 'PATCH', url: `/admin/competitions/tournaments/${t.id}`, headers: auth(mk.token), payload: { lastDay: '2026-11-13' } });
    expect(noReason.json().error.code).toBe('reason_required');
    const earlier = await h.app.inject({ method: 'PATCH', url: `/admin/competitions/tournaments/${t.id}`, headers: auth(mk.token), payload: { titleEn: 'x', reason: 'typo fix' } });
    expect(earlier.json().error.code).toBe('tournament_not_editable');

    expect((await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t.id}/join`, headers: auth(u1.token), payload: {} })).json().error.code).toBe('ack_required');
    expect((await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t.id}/join`, headers: auth(u1.token), payload: { acknowledge: true } })).json().error.code).toBe('attestation_required');
    const joined = await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t.id}/join`, headers: auth(u1.token), payload: { acknowledge: true, attestAdult: true } });
    expect(joined.statusCode).toBe(200);
    expect(joined.json()).toMatchObject({ joined: true, participants: 1, me: { rank: null, points: 0 } });
    expect(await consentEventsFor(h, u1.id)).toEqual([{ granted: true, source: 'settings', attested_adult: true, policy_version: POLICY_VERSION }]);

    const others: { id: string; token: string }[] = [];
    for (let i = 0; i < 11; i++) {
      const u = await makeUser(h, `Player ${i}`, { attested: true });
      await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t.id}/join`, headers: auth(u.token), payload: { acknowledge: true } });
      others.push(u);
      await earn(h, u.id, 10 * (i + 1), '2026-11-10T10:00:00Z');
    }
    await earn(h, u1.id, 500, '2026-11-10T11:00:00Z');
    await earn(h, u1.id, 999, '2026-11-09T11:00:00Z'); // before the window: never counts
    // Leaving hides at once; the leaver gets no badge.
    await h.app.inject({ method: 'DELETE', url: `/v1/tournaments/${t.id}/join`, headers: auth(others[0]!.token) });
    expect((await consentEventsFor(h, others[0]!.id)).at(-1)).toMatchObject({ granted: false, source: 'settings', attested_adult: null });

    expect((await h.app.inject({ method: 'GET', url: `/v1/tournaments/${t.id}/standings`, headers: auth(u1.token) })).json().rows.every((r: { rank: number | null }) => r.rank === null)).toBe(true);
    await takeNightlySnapshot(h.ctx);
    const st = (await h.app.inject({ method: 'GET', url: `/v1/tournaments/${t.id}/standings`, headers: auth(u1.token) })).json();
    expect(st.total).toBe(11);
    expect(st.rows[0]).toMatchObject({ points: 500, rank: 1, me: true });
    expect(st.me).toMatchObject({ points: 500, rank: 1 });
    const adminSt = (await h.app.inject({ method: 'GET', url: `/admin/competitions/tournaments/${t.id}/standings?limit=5`, headers: auth(sup.token) })).json();
    expect(adminSt.rows).toHaveLength(5);
    expect(adminSt.rows[0].userId).toBe(u1.id);
    const stats = (await h.app.inject({ method: 'GET', url: `/admin/competitions/tournaments/${t.id}/stats`, headers: auth(mk.token) })).json();
    expect(stats.participants).toBeNull(); // 11 < 20: suppressed
    expect(stats.median).toBeNull();

    // Batched close: one batch of one entry, then a "crash", then the rest.
    h.setNow('2026-11-12T23:00:00Z');
    const before = await ledgerCount(h);
    expect(await closeDueTournaments(h.ctx, { batchSize: 1, maxBatches: 1 })).toEqual({ closed: 0, batches: 1 });
    const half = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from tournament_entries where tournament_id = ${t.id} and final_points is not null`);
    expect(half.rows[0]!.n).toBe(1);
    expect((await closeDueTournaments(h.ctx, { batchSize: 4 })).closed).toBe(1);
    expect((await closeDueTournaments(h.ctx)).closed).toBe(0);
    expect(await ledgerCount(h)).toBe(before);
    const badges = await h.db.execute<{ user_id: string; kind: string }>(sql`select user_id, kind from user_badges where ref_key = ${`tournament:${t.id}`}`);
    const kinds = new Map(badges.rows.map((b) => [b.user_id, b.kind]));
    expect(kinds.get(u1.id)).toBe('tournament_podium'); // 11 joiners, rank 1
    expect(kinds.get(others[10]!.id)).toBe('tournament_podium'); // 110 points, rank 2
    expect(kinds.get(others[9]!.id)).toBe('tournament_podium'); // 100, rank 3
    expect(kinds.get(others[8]!.id)).toBe('tournament_finisher'); // rank 4 > ceil(1.1) = 2… podium covers 1–3
    expect(kinds.has(others[0]!.id)).toBe(false); // left
    const closed = (await h.app.inject({ method: 'GET', url: `/v1/tournaments/${t.id}`, headers: auth(u1.token) })).json();
    expect(closed).toMatchObject({ phase: 'ended', closed: true, me: { rank: 1, points: 500 } });
    expect((await consentEventsFor(h, u1.id)).at(-1)).toMatchObject({ granted: false, source: 'system' });
    const myBadges = (await h.app.inject({ method: 'GET', url: '/v1/me/badges', headers: auth(u1.token) })).json();
    expect(myBadges.map((b: { kind: string }) => b.kind)).toContain('tournament_podium');

    // Cancel: no badges, every entrant's consent recomputed (source system).
    h.setNow('2026-11-13T08:00:00Z');
    const t2 = (await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, slug: 'dec-cup', startsOn: '2026-11-14', lastDay: '2026-11-20' } })).json();
    await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${t2.id}/publish`, headers: auth(mk.token), payload: {} });
    await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t2.id}/join`, headers: auth(u1.token), payload: { acknowledge: true } });
    expect((await consentEventsFor(h, u1.id)).at(-1)).toMatchObject({ granted: true, attested_adult: true });
    const cancel = await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${t2.id}/cancel`, headers: auth(mk.token), payload: { reason: 'season moved' } });
    expect(cancel.json()).toMatchObject({ status: 'cancelled' });
    expect((await consentEventsFor(h, u1.id)).at(-1)).toMatchObject({ granted: false, source: 'system' });
    const audits = await h.db.execute<{ action: string }>(sql`select action from audit_log where admin_id = ${mk.id} order by created_at`);
    expect(new Set(audits.rows.map((a) => a.action))).toEqual(new Set(['tournament.create', 'tournament.publish', 'tournament.cancel']));
    expect((await h.app.inject({ method: 'POST', url: `/v1/tournaments/${t2.id}/join`, headers: auth(u1.token), payload: { acknowledge: true } })).json().error.code).toBe('tournament_not_open');

    // A live tournament may end later (with a reason); an early close ends it at the next Cairo
    // midnight (today still counts). Both audited.
    const t3 = (await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, slug: 'fri-cup', startsOn: '2026-11-13', lastDay: '2026-11-20' } })).json();
    await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${t3.id}/publish`, headers: auth(mk.token), payload: {} });
    const longer = await h.app.inject({ method: 'PATCH', url: `/admin/competitions/tournaments/${t3.id}`, headers: auth(mk.token), payload: { lastDay: '2026-11-21', reason: 'one more day' } });
    expect(longer.json()).toMatchObject({ endsAt: '2026-11-21T22:00:00.000Z' });
    const early = await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${t3.id}/close`, headers: auth(mk.token), payload: { reason: 'ending early' } });
    expect(early.json()).toMatchObject({ endsAt: '2026-11-13T22:00:00.000Z', status: 'published' });
    const t3Audit = await h.db.execute<{ action: string; reason: string | null }>(sql`
      select action, reason from audit_log where target_id = ${t3.id} order by created_at`);
    expect(t3Audit.rows.map((a) => [a.action, a.reason])).toEqual([
      ['tournament.create', null],
      ['tournament.publish', null],
      ['tournament.update', 'one more day'],
      ['tournament.close', 'ending early'],
    ]);
  });
});
