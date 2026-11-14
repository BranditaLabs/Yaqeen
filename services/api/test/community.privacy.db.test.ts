/**
 * Community privacy and safety against Postgres (design §1.3–§1.5, §4.4, §13): blocks both ways,
 * reports (idempotent, DB rate limit), handle rotation on hide-name, ban and moderation audits, the
 * country board (separate switch, K = 20), erasure, erasure cancel and the purge of every 0017 table.
 * Skipped without TEST_DATABASE_URL.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { COMMUNITY_USER_TABLES, purgeDeleted } from '../src/jobs/purge-deleted.js';
import { takeNightlySnapshot } from '../src/services/snapshots.service.js';
import { type Harness, TEST_DB_URL, auth, consentEventsFor, earn, makeAdmin, makeUser, optIn, setFlags, setup } from './community.helpers.js';

describe.skipIf(!TEST_DB_URL)('community privacy and safety (Postgres)', () => {
  let h: Harness;
  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
    await setFlags(h, { leagues: true, tournaments: true, leaderboard: true });
  });
  afterAll(async () => h?.close());

  const handleOf = async (token: string) => (await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(token) })).json().handle as string;
  const leagueRows = async (token: string) =>
    (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(token) })).json().rows as { handle: string; name: string | null; me: boolean }[];

  /** A member with a handle and switches, created directly (fast, for the K tests). */
  async function quickMember(name: string, opts: { country?: string; board?: boolean; countryBoard?: boolean; points?: number } = {}) {
    const u = await makeUser(h, name, { attested: true, country: opts.country });
    await h.db.execute(sql`
      insert into community_members (user_id, leaderboard, leaderboard_country) values (${u.id}, ${opts.board ?? false}, ${opts.countryBoard ?? false})`);
    await h.db.execute(sql`
      insert into public_profiles (user_id, handle, display_name, show) values (${u.id}, ${`q-${name.toLowerCase().replace(/\s+/g, '-')}`}, ${name}, '{}'::jsonb)`);
    if (opts.points) await earn(h, u.id, opts.points, '2026-11-09T10:00:00Z');
    return u;
  }

  it('blocks hide users from each other both ways, are listed and exported, and can be lifted', async () => {
    const a = await makeUser(h, 'Adam');
    const b = await makeUser(h, 'Bilal');
    await optIn(h, a.token, { leagues: true });
    await optIn(h, b.token, { leagues: true });
    const ha = await handleOf(a.token);
    const hb = await handleOf(b.token);
    expect((await leagueRows(a.token)).map((r) => r.handle).sort()).toEqual([ha, hb].sort());

    expect((await h.app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(a.token), payload: { handle: `@${hb.toUpperCase()}` } })).statusCode).toBe(204);
    expect((await h.app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(a.token), payload: { handle: 'nobody-0000' } })).statusCode).toBe(404);
    expect((await leagueRows(a.token)).map((r) => r.handle)).toEqual([ha]);
    expect((await leagueRows(b.token)).map((r) => r.handle)).toEqual([hb]); // the blocked user no longer sees the blocker either
    const list = (await h.app.inject({ method: 'GET', url: '/v1/community/blocks', headers: auth(a.token) })).json();
    expect(list).toEqual([{ handle: hb, name: 'Bilal', avatar: { kind: 'initial' } }]);
    const exp = (await h.app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(a.token) })).json();
    expect(exp.community.blocksMade.map((x: { handle: string }) => x.handle)).toEqual([hb]);
    expect(exp.community.settings).toMatchObject({ leagues: true, attestedAdult: true });
    expect(exp.community.attestedAdultAt).toBeTruthy();

    expect((await h.app.inject({ method: 'DELETE', url: `/v1/community/blocks/${hb}`, headers: auth(a.token) })).statusCode).toBe(204);
    expect((await leagueRows(b.token)).length).toBe(2);
  });

  it('reports are idempotent while open and limited to 20 per reporter per rolling 24 h (in the DB)', async () => {
    const reporter = await makeUser(h, 'Reporter');
    const targets = [];
    for (let i = 0; i < 21; i++) targets.push(await quickMember(`Target ${i}`));
    const report = (handle: string) => h.app.inject({ method: 'POST', url: '/v1/community/reports', headers: auth(reporter.token), payload: { handle, reason: 'name' } });
    expect((await report('q-target-0')).statusCode).toBe(204);
    expect((await report('q-target-0')).statusCode).toBe(204); // same open report: no new row, not counted
    const one = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from community_reports where reporter_id = ${reporter.id}`);
    expect(one.rows[0]!.n).toBe(1);
    for (let i = 1; i < 20; i++) expect((await report(`q-target-${i}`)).statusCode).toBe(204);
    const over = await report('q-target-20');
    expect(over.statusCode).toBe(429);
    expect(over.json().error.code).toBe('rate_limited');
    expect((await report('no-such-handle')).statusCode).toBe(404);
    // A day later the window has moved on.
    h.setNow('2026-11-12T08:01:00Z');
    expect((await report('q-target-20')).statusCode).toBe(204);
    h.setNow('2026-11-11T08:00:00Z');
    const exp = (await h.app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(reporter.token) })).json();
    expect(exp.community.reportsFiled).toHaveLength(21);
  });

  it('hide-name hides the public name, locks renaming and rotates an unpublished handle; a published card keeps its handle', async () => {
    const sup = await makeAdmin(h, 'support');
    const d = await makeUser(h, 'Dina Hassan');
    await optIn(h, d.token, { leagues: true });
    const before = await handleOf(d.token);
    expect(before).toMatch(/^dina-\d{4}$/);
    const res = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${d.id}/hide-name`, headers: auth(sup.token), payload: { reason: 'offensive name' } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ nameHidden: true });
    const after = await handleOf(d.token);
    expect(after).toMatch(/^member-[a-z0-9]{6}$/);
    const audit = await h.db.execute<{ after: { handleFrom: string; handleTo: string } }>(sql`
      select after from audit_log where action = 'competitor.hide_name' and target_id = ${d.id}`);
    expect(audit.rows[0]!.after).toMatchObject({ handleFrom: before, handleTo: after });
    const mine = (await leagueRows(d.token)).find((r) => r.me)!;
    expect(mine.name).toBeNull();
    const rename = await h.app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: auth(d.token), payload: { displayName: 'Dina' } });
    expect(rename.json().error.code).toBe('name_locked');
    await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${d.id}/restore-name`, headers: auth(sup.token), payload: { reason: 'appeal accepted' } });
    expect(await handleOf(d.token)).toBe(after); // not rotated back
    expect((await h.app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: auth(d.token), payload: { displayName: 'Dina' } })).statusCode).toBe(200);

    const e = await makeUser(h, 'Ehab');
    const card = await h.app.inject({
      method: 'PUT',
      url: '/v1/me/public-profile',
      headers: auth(e.token),
      payload: { published: true, handle: 'ehab', displayName: 'Ehab', bio: '', links: [], show: { level: true, streak: false, challengeDay: false, badges: false, memberSince: false }, theme: 'sky' },
    });
    expect(card.statusCode).toBe(200);
    await optIn(h, e.token, { leagues: true });
    expect(await handleOf(e.token)).toBe('ehab'); // existing card handles are kept
    await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${e.id}/hide-name`, headers: auth(sup.token), payload: { reason: 'offensive name' } });
    expect(await handleOf(e.token)).toBe('ehab');
  });

  it('ban leaves everything (consent event source support) and refuses rejoining; every action is audited', async () => {
    const sup = await makeAdmin(h, 'support');
    const f = await makeUser(h, 'Fadi');
    await optIn(h, f.token, { leagues: true, leaderboard: true });
    await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(f.token) });
    const ban = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${f.id}/ban`, headers: auth(sup.token), payload: { reason: 'harassment' } });
    expect(ban.json()).toMatchObject({ banned: true, leagues: false, leaderboard: false });
    expect((await consentEventsFor(h, f.id)).at(-1)).toMatchObject({ granted: false, source: 'support' });
    expect((await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(f.token) })).json()).toEqual({ state: 'off' });
    expect((await optIn(h, f.token, { leagues: true })).json().error.code).toBe('community_banned');
    await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${f.id}/unban`, headers: auth(sup.token), payload: { reason: 'appeal accepted' } });
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/community', headers: auth(f.token) })).json()).toMatchObject({ banned: false, leagues: false });
    const nothing = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${f.id}/restore-photo`, headers: auth(sup.token), payload: { reason: 'try restore' } });
    expect(nothing.json().error.code).toBe('nothing_to_restore');
    const actions = await h.db.execute<{ action: string; reason: string }>(sql`select action, reason from audit_log where target_id = ${f.id} and admin_id is not null order by created_at`);
    expect(actions.rows.map((r) => r.action)).toEqual(['competitor.ban', 'competitor.unban']);

    // Reports reach support and resolve in one audited step.
    const rep = await makeUser(h, 'Witness');
    const fh = await handleOf(f.token);
    await h.app.inject({ method: 'POST', url: '/v1/community/reports', headers: auth(rep.token), payload: { handle: fh, reason: 'photo' } });
    const queue = (await h.app.inject({ method: 'GET', url: '/admin/competitions/reports', headers: auth(sup.token) })).json();
    const item = queue.items.find((x: { target: { userId: string } }) => x.target.userId === f.id);
    expect(item).toMatchObject({ reason: 'photo', count: 1, target: { banned: false, openReports: 1 } });
    expect(JSON.stringify(queue)).not.toMatch(/five_prayers|azkar|wird|task/);
    const done = await h.app.inject({ method: 'POST', url: `/admin/competitions/reports/${item.id}/resolve`, headers: auth(sup.token), payload: { resolution: 'dismissed', reason: 'no issue found' } });
    expect(done.json()).toMatchObject({ ok: true, resolved: 1 });
    const audit = await h.db.execute(sql`select 1 from audit_log where action = 'report.resolve' and target_id = ${f.id}`);
    expect(audit.rows).toHaveLength(1);
  });

  it('the country board is its own switch and exists only with at least 20 participants', async () => {
    const noCountry = await makeUser(h, 'Nomad');
    await optIn(h, noCountry.token, { leaderboard: true });
    expect((await h.app.inject({ method: 'GET', url: '/v1/leaderboard?scope=country', headers: auth(noCountry.token) })).json().error.code).toBe('country_unknown');

    const viewer = await makeUser(h, 'Viewer', { country: 'EG' });
    await optIn(h, viewer.token, { leaderboard: true }); // global only
    for (let i = 0; i < 19; i++) await quickMember(`Egy ${i}`, { country: 'EG', board: true, countryBoard: true, points: 10 + i });
    const small = await h.app.inject({ method: 'GET', url: '/v1/leaderboard?scope=country', headers: auth(viewer.token) });
    expect(small.statusCode).toBe(409);
    expect(small.json().error.code).toBe('country_too_small');

    await h.app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(viewer.token), payload: { leaderboardCountry: true } });
    await earn(h, viewer.id, 5, '2026-11-09T10:00:00Z');
    await takeNightlySnapshot(h.ctx);
    const board = (await h.app.inject({ method: 'GET', url: '/v1/leaderboard?scope=country', headers: auth(viewer.token) })).json();
    expect(board).toMatchObject({ scope: 'country', country: 'EG', joined: true, countryJoined: true });
    expect(board.rows).toHaveLength(20);
    expect(board.rows[0]).toMatchObject({ points: null, rank: 1 });
    expect(board.me).toMatchObject({ me: true, rank: 20 });

    // Turning the country switch off keeps the global board and drops the country row at once.
    await h.app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(viewer.token), payload: { leaderboardCountry: false } });
    const off = await h.app.inject({ method: 'GET', url: '/v1/leaderboard?scope=country', headers: auth(viewer.token) });
    expect(off.statusCode).toBe(409); // 19 left
    const global = (await h.app.inject({ method: 'GET', url: '/v1/leaderboard', headers: auth(viewer.token) })).json();
    expect(global).toMatchObject({ joined: true, countryJoined: false });
    expect(global.me).not.toBeNull();
  });

  it('erasure: out of everything, country/blocks/snapshots gone, consent event erasure; cancelling keeps the user out', async () => {
    const c = await makeUser(h, 'Camelia', { country: 'EG' });
    const other = await makeUser(h, 'Other');
    await optIn(h, c.token, { leagues: true, leaderboard: true, leaderboardCountry: true });
    await optIn(h, other.token, { leagues: true });
    await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(c.token) });
    const hc = await handleOf(c.token);
    const ho = await handleOf(other.token);
    await h.app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(c.token), payload: { handle: ho } });
    await h.app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(other.token), payload: { handle: hc } });
    await earn(h, c.id, 40, '2026-11-09T10:00:00Z');
    h.setNow('2026-11-11T23:00:00Z');
    await takeNightlySnapshot(h.ctx);
    const snap = await h.db.execute(sql`select 1 from leaderboard_snapshot where user_id = ${c.id}`);
    expect(snap.rows.length).toBeGreaterThan(0);

    expect((await h.app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(c.token) })).statusCode).toBe(202);
    const q = async (text: ReturnType<typeof sql>) => (await h.db.execute(text)).rows;
    expect(await q(sql`select 1 from community_blocks where user_id = ${c.id} or blocked_user_id = ${c.id}`)).toEqual([]);
    expect(await q(sql`select 1 from leaderboard_snapshot where user_id = ${c.id}`)).toEqual([]);
    expect(await q(sql`select 1 from league_members where user_id = ${c.id} and (left_at is null or snapshot_points is not null)`)).toEqual([]);
    const [u] = await q(sql`select country, avatar_kind from users where id = ${c.id}`);
    expect(u).toEqual({ country: null, avatar_kind: 'initial' });
    expect((await consentEventsFor(h, c.id)).at(-1)).toMatchObject({ granted: false, source: 'erasure' });
    expect((await leagueRows(other.token)).map((r) => r.handle)).not.toContain(hc);

    // Cancelling inside the grace period (signing in again) does not put the user back.
    await h.db.execute(sql`update users set status = 'active', deletion_requested_at = null where id = ${c.id}`);
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/community', headers: auth(c.token) })).json()).toMatchObject({ leagues: false, leaderboard: false, leaderboardCountry: false, country: null });
    expect((await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(c.token) })).json()).toEqual({ state: 'off' });
  });

  it('the purge removes every row of every 0017 table with a user FK (enumerated from the migration)', async () => {
    const migration = readFileSync(fileURLToPath(new URL('../drizzle/0017_community.sql', import.meta.url)), 'utf8');
    const created = [...migration.matchAll(/CREATE TABLE "([a-z_]+)"/g)].map((m) => m[1]!);
    const fks = await h.db.execute<{ tbl: string; col: string }>(sql`
      select c.conrelid::regclass::text as tbl, a.attname as col
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
      where c.contype = 'f' and c.confrelid = 'users'::regclass`);
    const expected = fks.rows.filter((r) => created.includes(r.tbl)).map((r) => `${r.tbl}.${r.col}`).sort();
    const covered = COMMUNITY_USER_TABLES.flatMap(([t, cols]) => cols.map((c) => `${t}.${c}`)).sort();
    expect(covered).toEqual(expected);

    // A user with a row in every one of them.
    const x = await makeUser(h, 'Xena', { country: 'EG', attested: true });
    const y = await quickMember('Yusuf');
    await optIn(h, x.token, { leagues: true, leaderboard: true });
    await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(x.token) });
    await earn(h, x.id, 70, '2026-11-09T10:00:00Z');
    await h.db.execute(sql`insert into avatar_photos (user_id, sha_small, sha_large, small, large, bytes) values (${x.id}, 'a', 'b', '\\x00'::bytea, '\\x00'::bytea, 2)`);
    await h.db.execute(sql`insert into community_blocks (user_id, blocked_user_id) values (${x.id}, ${y.id}), (${y.id}, ${x.id})`);
    await h.db.execute(sql`insert into community_reports (reporter_id, target_user_id, reason) values (${x.id}, ${y.id}, 'name'), (${y.id}, ${x.id}, 'photo')`);
    await h.db.execute(sql`insert into user_badges (user_id, kind, ref_key) values (${x.id}, 'league_first', 'league:2026-10-31')`);
    await h.db.execute(sql`insert into leaderboard_snapshot (scope, country, user_id, rank, lifetime, day) values ('global', '', ${x.id}, 1, 70, '2026-11-11')`);
    const t = await h.db.execute<{ id: string }>(sql`
      insert into tournaments (slug, title_ar, title_en, starts_at, ends_at, join_until, badge_ar, badge_en, status)
      values ('purge-cup', 'ك', 'C', '2026-11-09T22:00:00Z', '2026-11-12T22:00:00Z', '2026-11-12T22:00:00Z', 'ب', 'B', 'published') returning id`);
    await h.db.execute(sql`insert into tournament_entries (tournament_id, user_id) values (${t.rows[0]!.id}, ${x.id})`);
    for (const [table, cols] of COMMUNITY_USER_TABLES) {
      const where = cols.map((c) => `${c} = '${x.id}'`).join(' or ');
      const n = await h.db.execute<{ n: number }>(sql.raw(`select count(*)::int as n from ${table} where ${where}`));
      expect(n.rows[0]!.n, table).toBeGreaterThan(0);
    }

    await h.db.execute(sql`update users set status = 'deletion_requested', deletion_requested_at = '2026-09-01T00:00:00Z' where id = ${x.id}`);
    expect(await purgeDeleted(h.db, h.now())).toBeGreaterThanOrEqual(1);
    for (const [table, cols] of COMMUNITY_USER_TABLES) {
      const where = cols.map((c) => `${c} = '${x.id}'`).join(' or ');
      const n = await h.db.execute<{ n: number }>(sql.raw(`select count(*)::int as n from ${table} where ${where}`));
      expect(n.rows[0]!.n, table).toBe(0);
    }
    const [tomb] = (await h.db.execute(sql`
      select status, country, avatar_kind, avatar_preset, avatar_photo_id, name_hidden_at, photo_locked_at, adult_attested_at from users where id = ${x.id}`)).rows;
    expect(tomb).toEqual({ status: 'deleted', country: null, avatar_kind: 'initial', avatar_preset: null, avatar_photo_id: null, name_hidden_at: null, photo_locked_at: null, adult_attested_at: null });
  });
});
