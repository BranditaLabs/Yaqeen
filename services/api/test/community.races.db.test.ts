/**
 * Community concurrency and privacy edges against Postgres: cancel vs. the tournament close, leave
 * vs. finalizing (row lock), the derived consent under concurrent join + close (no write skew),
 * league placement vs. a concurrent turn-off, closed standings after withdrawal / erasure / leave,
 * the photo projection matching the public route, hidden names never reaching a handle, support's
 * photo restore after the user moved on, and the nightly lifetime snapshot writing only changed rows.
 * Skipped without TEST_DATABASE_URL — run with --no-file-parallelism.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { sql } from 'drizzle-orm';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ensurePlacement } from '../src/services/leagues.service.js';
import { recomputeCommunityConsent, recomputeCommunityConsentMany } from '../src/services/community.service.js';
import { snapshotPublicLifetime } from '../src/services/snapshots.service.js';
import { closeDueTournaments } from '../src/services/tournaments.service.js';
import { type Harness, TEST_DB_URL, auth, earn, makeAdmin, makeUser, optIn, setFlags, setup } from './community.helpers.js';

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const fixture = (name: string) => readFileSync(fileURLToPath(new URL(`./fixtures/avatar/${name}`, import.meta.url)));

describe.skipIf(!TEST_DB_URL)('community races and privacy edges (Postgres)', () => {
  let h: Harness;
  let mk: { id: string; token: string };
  let sup: { id: string; token: string };
  const START = '2026-11-11T08:00:00Z';
  const base = { titleAr: 'كأس', titleEn: 'Cup', bodyAr: '', bodyEn: '', badgeAr: 'كأس', badgeEn: 'Cup', minPoints: 1 };

  beforeAll(async () => {
    h = await setup(START);
    await setFlags(h, { leagues: true, tournaments: true, leaderboard: true, publicCards: true });
    mk = await makeAdmin(h, 'marketing');
    sup = await makeAdmin(h, 'support');
  });
  afterAll(async () => h?.close());

  async function tournament(slug: string, startsOn: string, lastDay: string): Promise<string> {
    const c = await h.app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(mk.token), payload: { ...base, slug, startsOn, lastDay } });
    expect(c.statusCode).toBe(200);
    const id = c.json().id as string;
    expect((await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${id}/publish`, headers: auth(mk.token), payload: {} })).statusCode).toBe(200);
    return id;
  }
  const join = async (token: string, id: string) => {
    const r = await h.app.inject({ method: 'POST', url: `/v1/tournaments/${id}/join`, headers: auth(token), payload: { acknowledge: true, attestAdult: true } });
    expect(r.statusCode).toBe(200);
  };
  const standings = async (token: string, id: string) =>
    (await h.app.inject({ method: 'GET', url: `/v1/tournaments/${id}/standings`, headers: auth(token) })).json() as {
      rows: { handle: string; avatar: { kind: string; url?: string } }[];
      me: unknown;
    };
  const handleOf = async (uid: string) =>
    (await h.db.execute<{ handle: string }>(sql`select handle from public_profiles where user_id = ${uid}`)).rows[0]?.handle ?? null;
  const consentOf = async (uid: string) =>
    (await h.db.execute<{ granted: boolean }>(sql`select granted from consents where user_id = ${uid} and kind = 'community'`)).rows[0]?.granted ?? null;

  it('a cancel is refused once the close started finalizing; the close re-checks the status in every batch', async () => {
    h.setNow(START);
    const id = await tournament('fin-cup', '2026-11-10', '2026-11-12');
    for (let i = 0; i < 3; i++) {
      const u = await makeUser(h, `Fin ${i}`);
      await join(u.token, id);
      await earn(h, u.id, 10 * (i + 1), '2026-11-11T10:00:00Z');
    }
    h.setNow('2026-11-12T23:00:00Z');
    expect(await closeDueTournaments(h.ctx, { batchSize: 1, maxBatches: 1 })).toEqual({ closed: 0, batches: 1 });
    const cancel = await h.app.inject({ method: 'POST', url: `/admin/competitions/tournaments/${id}/cancel`, headers: auth(mk.token), payload: { reason: 'too late now' } });
    expect([cancel.statusCode, cancel.json().error?.code]).toEqual([409, 'tournament_closed']);
    expect((await closeDueTournaments(h.ctx)).closed).toBe(1);
    const t = await h.db.execute<{ status: string; closed: boolean }>(sql`select status, closed_at is not null as closed from tournaments where id = ${id}`);
    expect(t.rows[0]).toEqual({ status: 'published', closed: true });

    // A tournament no longer published between two batches (the job's list is read once) gets no
    // further finals, badges or closed_at.
    h.setNow(START);
    const id2 = await tournament('mid-cup', '2026-11-10', '2026-11-12');
    for (let i = 0; i < 3; i++) {
      const u = await makeUser(h, `Mid ${i}`);
      await join(u.token, id2);
      await earn(h, u.id, 10 * (i + 1), '2026-11-11T11:00:00Z');
    }
    h.setNow('2026-11-12T23:00:00Z');
    let calls = 0;
    const db = new Proxy(h.db, {
      get(target, prop) {
        if (prop === 'transaction') {
          return async (fn: Parameters<typeof target.transaction>[0]) => {
            if (calls++ === 1) await target.execute(sql`update tournaments set status = 'cancelled' where id = ${id2}`);
            return target.transaction(fn);
          };
        }
        const v = Reflect.get(target, prop) as unknown;
        return typeof v === 'function' ? (v as (...a: unknown[]) => unknown).bind(target) : v;
      },
    });
    expect((await closeDueTournaments({ ...h.ctx, db }, { batchSize: 1 })).closed).toBe(0);
    const after = await h.db.execute<{ finals: number; closed: boolean }>(sql`
      select (select count(*) from tournament_entries where tournament_id = ${id2} and final_points is not null)::int as finals,
        (select closed_at is not null from tournaments where id = ${id2}) as closed`);
    expect(after.rows[0]).toEqual({ finals: 1, closed: false });
    const badges = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from user_badges where ref_key = ${`tournament:${id2}`}`);
    expect(badges.rows[0]!.n).toBeLessThanOrEqual(1);
  });

  it('a leave racing the finalizing waits for it: still ranked in the frozen field, hidden, no badge', async () => {
    h.setNow(START);
    const id = await tournament('race-cup', '2026-11-10', '2026-11-12');
    const us = [];
    for (let i = 0; i < 3; i++) {
      const u = await makeUser(h, `Racer ${i}`);
      await join(u.token, id);
      await earn(h, u.id, 30 - 10 * i, '2026-11-11T12:00:00Z');
      us.push(u);
    }
    h.setNow('2026-11-12T23:00:00Z');
    const fin = new Date('2026-11-12T23:00:05Z'); // the job started a moment after the leave
    const client = new pg.Client({ connectionString: TEST_DB_URL });
    await client.connect();
    await client.query('begin');
    await client.query('update tournaments set finalizing_at = $1 where id = $2', [fin, id]);
    let done = false;
    const leaving = h.app.inject({ method: 'DELETE', url: `/v1/tournaments/${id}/join`, headers: auth(us[2]!.token) }).then((r) => {
      done = true;
      return r;
    });
    await sleep(400);
    const waited = !done;
    await client.query('commit');
    await client.end();
    expect((await leaving).statusCode).toBe(200);
    expect(waited).toBe(true);
    const e = await h.db.execute<{ left_at: Date }>(sql`select left_at from tournament_entries where tournament_id = ${id} and user_id = ${us[2]!.id}`);
    expect(new Date(e.rows[0]!.left_at).getTime()).toBeGreaterThanOrEqual(fin.getTime());

    expect((await closeDueTournaments(h.ctx)).closed).toBe(1);
    const finals = await h.db.execute<{ user_id: string; final_rank: number | null }>(sql`
      select user_id, final_rank from tournament_entries where tournament_id = ${id} order by final_rank`);
    expect(finals.rows.map((r) => r.final_rank)).toEqual([1, 2, 3]);
    const badges = await h.db.execute<{ user_id: string }>(sql`select user_id from user_badges where ref_key = ${`tournament:${id}`}`);
    expect(badges.rows.map((b) => b.user_id)).not.toContain(us[2]!.id);
    const st = await standings(us[0]!.token, id);
    expect(st.rows).toHaveLength(2);
    expect(st.rows.map((r) => r.handle)).not.toContain(await handleOf(us[2]!.id));
  });

  it('a closed tournament hides whoever withdrew the consent, asked for erasure (even cancelled) or left', async () => {
    h.setNow(START);
    const id = await tournament('hide-cup', '2026-11-10', '2026-11-12');
    const [a, b, c] = [await makeUser(h, 'Hana'), await makeUser(h, 'Bilal'), await makeUser(h, 'Camilia')];
    for (const [i, u] of [a, b, c].entries()) {
      await join(u.token, id);
      await earn(h, u.id, 10 + i, '2026-11-11T13:00:00Z');
    }
    h.setNow('2026-11-12T23:00:00Z');
    await closeDueTournaments(h.ctx);
    const [ha, hb, hc] = [await handleOf(a.id), await handleOf(b.id), await handleOf(c.id)];
    expect((await standings(a.token, id)).rows.map((r) => r.handle).sort()).toEqual([ha, hb, hc].sort());

    const withdraw = await h.app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(b.token), payload: { kind: 'community', granted: false, source: 'settings' } });
    expect(withdraw.statusCode).toBe(200);
    expect((await standings(a.token, id)).rows.map((r) => r.handle)).not.toContain(hb);

    expect((await h.app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(c.token) })).statusCode).toBe(202);
    // Signing in again within the grace period cancels the erasure (the account is active again).
    await h.db.execute(sql`update users set status = 'active', deletion_requested_at = null where id = ${c.id}`);
    await h.ctx.cache.bumpNamespace('community');
    expect((await standings(a.token, id)).rows.map((r) => r.handle)).not.toContain(hc);

    const left = await h.app.inject({ method: 'DELETE', url: `/v1/tournaments/${id}/join`, headers: auth(a.token) });
    expect(left.json()).toMatchObject({ joined: false, me: null });
    const st = await standings(a.token, id);
    expect(st.rows).toEqual([]);
    expect(st.me).toBeNull();
  });

  it('the derived consent: a join and a concurrent close serialise per user (no write skew)', async () => {
    h.setNow(START);
    const a = await tournament('skew-a', '2026-11-10', '2026-11-12');
    const b = await tournament('skew-b', '2026-11-10', '2026-11-20');
    const u = await makeUser(h, 'Yusuf');
    await join(u.token, a);
    expect(await consentOf(u.id)).toBe(true);

    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    let reached!: () => void;
    const atGate = new Promise<void>((r) => (reached = r));
    // The join of B (as tournaments.join does it): user row locked, entry written, consent recomputed.
    const joinB = h.db.transaction(async (tx) => {
      await tx.execute(sql`select 1 from users where id = ${u.id} for no key update`);
      await tx.execute(sql`insert into tournament_entries (tournament_id, user_id, joined_at) values (${b}, ${u.id}, now())`);
      await recomputeCommunityConsent(tx, u.id, 'settings');
      reached();
      await gate;
    });
    await atGate;
    // The close of A meanwhile: closed_at, then the set-based recompute of A's entrants.
    const closeA = h.db.transaction(async (tx) => {
      await tx.execute(sql`update tournaments set closed_at = now() where id = ${a}`);
      await recomputeCommunityConsentMany(tx, sql`select user_id from tournament_entries where tournament_id = ${a}`, 'system');
    });
    await sleep(300);
    release();
    await Promise.all([joinB, closeA]);
    expect(await consentOf(u.id)).toBe(true); // in B, a live tournament
  });

  it('league placement re-checks the switch under the user lock: a concurrent turn-off is never undone', async () => {
    h.setNow('2026-11-13T08:00:00Z');
    const u = await makeUser(h, 'Laila');
    expect((await optIn(h, u.token, { leagues: true })).statusCode).toBe(200);
    expect((await ensurePlacement(h.ctx, u.id)).state).toBe('placed');
    await optIn(h, u.token, { leagues: false });
    await optIn(h, u.token, { leagues: true }); // back on: the next read rejoins the same group
    const leftAt = async () =>
      (await h.db.execute<{ left: boolean }>(sql`select left_at is not null as left from league_members where user_id = ${u.id}`)).rows[0]!.left;
    expect(await leftAt()).toBe(true);

    // A turn-off (as PUT /v1/me/community does it) holds the user row while the read places.
    const client = new pg.Client({ connectionString: TEST_DB_URL });
    await client.connect();
    await client.query('begin');
    await client.query('select 1 from users where id = $1 for no key update', [u.id]);
    await client.query('update community_members set leagues = false where user_id = $1', [u.id]);
    const placing = ensurePlacement(h.ctx, u.id);
    await sleep(300);
    await client.query('commit');
    await client.end();
    expect((await placing).state).toBe('off');
    expect(await leftAt()).toBe(true);
  });

  it('tournaments list: the shared part is cached; the caller’s own part is always fresh', async () => {
    h.setNow(START);
    const id = await tournament('list-cup', '2026-11-10', '2026-11-20');
    const [v1, v2, w] = [await makeUser(h, 'Viewer'), await makeUser(h, 'Second'), await makeUser(h, 'Walker')];
    const count = async (token: string) =>
      ((await h.app.inject({ method: 'GET', url: '/v1/tournaments', headers: auth(token) })).json() as { id: string; participants: number; joined: boolean }[]).find(
        (t) => t.id === id,
      )!;
    const first = await count(v1.token);
    await h.db.execute(sql`insert into tournament_entries (tournament_id, user_id, joined_at) values (${id}, ${w.id}, now()), (${id}, ${v2.id}, now())`);
    const second = await count(v2.token);
    expect(second.participants).toBe(first.participants); // the cached count (joins bump it)
    expect(second.joined).toBe(true); // the caller's own entry, read live
  });

  it('badge catalogue: the ledger-derived counts are a cached aggregate', async () => {
    const counts = async () =>
      new Map(
        ((await h.app.inject({ method: 'GET', url: '/admin/competitions/badges', headers: auth(sup.token) })).json().items as { kind: string; count: number | null }[]).map(
          (x) => [x.kind, x.count],
        ),
      );
    const before = (await counts()).get('streak');
    const u = await makeUser(h, 'Streaky');
    for (let d = 1; d <= 25; d++) {
      await h.db.execute(sql`insert into points_ledger (user_id, delta, reason, ref_key) values (${u.id}, 1, 'milestone', ${`milestone:${d}`})`);
    }
    expect((await counts()).get('streak')).toBe(before);
    await h.ctx.cache.bumpNamespace('catalogue');
    expect((await counts()).get('streak')).toBe(25);
  });

  it('a closed tournament’s standings never carry a photo URL the public route refuses', async () => {
    h.setNow(START);
    const id = await tournament('photo-cup', '2026-11-10', '2026-11-12');
    const p = await makeUser(h, 'Pictured');
    await join(p.token, id);
    const up = await h.app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { ...auth(p.token), 'content-type': 'image/png' }, payload: fixture('photo.png') });
    expect(up.statusCode).toBe(200);
    const live = (await standings(p.token, id)).rows[0]!;
    expect(live.avatar.kind).toBe('photo');
    expect((await h.app.inject({ method: 'GET', url: live.avatar.url!.replace('https://id.test', '') })).statusCode).toBe(200);

    h.setNow('2026-11-12T23:00:00Z');
    await closeDueTournaments(h.ctx);
    expect((await h.app.inject({ method: 'GET', url: live.avatar.url!.replace('https://id.test', '') })).statusCode).toBe(404);
    const st = await standings(p.token, id);
    expect(st.rows[0]!.avatar).toEqual({ kind: 'initial' });
    expect(st.me).toMatchObject({ avatar: { kind: 'initial' } });
  });

  it('a hidden name never becomes a handle: a later join gets member-…; the card editor keeps it neutral', async () => {
    h.setNow(START);
    const id = await tournament('name-cup', '2026-11-10', '2026-11-20');
    const z = await makeUser(h, 'Zubair Khan');
    const hide = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${z.id}/hide-name`, headers: auth(sup.token), payload: { reason: 'offensive name' } });
    expect(hide.statusCode).toBe(200);
    await join(z.token, id);
    expect(await handleOf(z.id)).toMatch(/^member-[a-z0-9]{6}$/);

    const o = await makeUser(h, 'Omar');
    await optIn(h, o.token, { leagues: true });
    expect(await handleOf(o.id)).toMatch(/^omar-\d{4}$/);
    await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${o.id}/hide-name`, headers: auth(sup.token), payload: { reason: 'offensive name' } });
    const rotated = await handleOf(o.id);
    expect(rotated).toMatch(/^member-/);
    const draft = (await h.app.inject({ method: 'GET', url: '/v1/me/public-profile', headers: auth(o.token) })).json();
    expect(draft.handle).toMatch(/^yaqeen_[0-9a-f]{6}/);
    const card = (handle: string) => ({ published: false, handle, displayName: 'Member', bio: '', links: [], show: { level: true, streak: false, challengeDay: false, badges: false, memberSince: false }, theme: 'sky' });
    const named = await h.app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(o.token), payload: card('omar_xx') });
    expect([named.statusCode, named.json().error?.code]).toEqual([409, 'name_locked']);
    expect(await handleOf(o.id)).toBe(rotated);
    expect((await h.app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(o.token), payload: card(draft.handle) })).statusCode).toBe(200);

    // Any new card handle passes the name filter: it is the @handle of every public row.
    const q = await makeUser(h, 'Qasim');
    const rude = await h.app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(q.token), payload: card('shit_happens') });
    expect([rude.statusCode, rude.json().error?.code]).toEqual([400, 'handle_reserved']);
  });

  it('support restores a photo only for an active account and only while the user kept the avatar the hide left', async () => {
    h.setNow(START);
    const upload = (token: string) => h.app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { ...auth(token), 'content-type': 'image/png' }, payload: fixture('photo.png') });
    const act = (uid: string, action: string) =>
      h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${uid}/${action}`, headers: auth(sup.token), payload: { reason: 'support review' } });
    const photoStatus = async (pid: string) => (await h.db.execute<{ status: string }>(sql`select status from avatar_photos where id = ${pid}`)).rows[0]!.status;

    // Moved on: picked a preset after the hide → the choice stands, uploads unlock, the photo stays removed.
    const m = await makeUser(h, 'Mover', { attested: true });
    const pm = (await upload(m.token)).json().id as string;
    expect((await act(m.id, 'hide-photo')).statusCode).toBe(200);
    expect((await h.app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: auth(m.token), payload: { avatar: { kind: 'preset', id: 'm03' } } })).statusCode).toBe(200);
    const r1 = await act(m.id, 'restore-photo');
    expect(r1.statusCode).toBe(200);
    expect(r1.json()).toMatchObject({ avatar: { kind: 'preset', id: 'm03' }, photoLocked: false });
    expect(await photoStatus(pm)).toBe('removed');
    const audit = await h.db.execute<{ after: { photoRestored?: boolean } }>(sql`
      select after from audit_log where action = 'competitor.restore_photo' and target_id = ${m.id}`);
    expect(audit.rows[0]!.after.photoRestored).toBe(false);

    // Kept what the hide left → the photo comes back.
    const k = await makeUser(h, 'Keeper', { attested: true });
    const pk = (await upload(k.token)).json().id as string;
    await act(k.id, 'hide-photo');
    expect((await act(k.id, 'restore-photo')).json()).toMatchObject({ avatar: { kind: 'photo', id: pk } });

    // Erasure requested → refused; the photo stays removed after a cancelled erasure.
    const e = await makeUser(h, 'Eraser', { attested: true });
    const pe = (await upload(e.token)).json().id as string;
    await act(e.id, 'hide-photo');
    expect((await h.app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(e.token) })).statusCode).toBe(202);
    const r3 = await act(e.id, 'restore-photo');
    expect([r3.statusCode, r3.json().error?.code]).toEqual([409, 'account_inactive']);
    expect(await photoStatus(pe)).toBe('removed');
  });

  it('the nightly lifetime snapshot pages by user_id and writes only rows whose value changed', async () => {
    const [x, y] = [await makeUser(h, 'Xena'), await makeUser(h, 'Yara')];
    await earn(h, x.id, 10, '2026-11-09T10:00:00Z');
    await earn(h, y.id, 9, '2026-11-09T10:00:00Z');
    await snapshotPublicLifetime(h.ctx, '2026-11-11', { batchSize: 2 });
    const state = async (uid: string) =>
      (await h.db.execute<{ xmin: string; v: number }>(sql`select xmin::text as xmin, public_lifetime as v from user_point_totals where user_id = ${uid}`)).rows[0]!;
    const x1 = await state(x.id);
    expect(x1.v).toBe(10);
    await earn(h, y.id, 5, '2026-11-12T10:00:00Z');
    const written = await snapshotPublicLifetime(h.ctx, '2026-11-13', { batchSize: 2 });
    expect(written).toBeGreaterThanOrEqual(1);
    expect(await state(x.id)).toEqual(x1); // unchanged value → the row was not rewritten
    expect((await state(y.id)).v).toBe(14);
    const wrong = await h.db.execute<{ n: number }>(sql`
      select count(*)::int as n from user_point_totals t
      where t.public_lifetime <> greatest(0, t.lifetime_earned - coalesce((select d.earned from points_earned_daily d where d.user_id = t.user_id and d.day = '2026-11-13'::date), 0))`);
    expect(wrong.rows[0]!.n).toBe(0);
  });
});
