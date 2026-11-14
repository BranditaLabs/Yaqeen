/**
 * Guest → existing account merge and the derived rollups (design §1.6): the guest's earned days move
 * to the account in the same transaction (summing on a shared day), the merge `grant` counts once for
 * the level and never for week/tournament points, and `yq_rebuild_points_rollups()` gives the same
 * result as the trigger. Skipped without TEST_DATABASE_URL.
 */
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { sql } from 'drizzle-orm';
import * as s from '../src/db/schema.js';
import { type Harness, TEST_DB_URL, auth, earn, makeUser, setup } from './community.helpers.js';

// ID tokens are verified against Google/Apple JWKS in production; here the token *is* the subject.
vi.mock('../src/integrations/oidc.js', () => ({
  verifyGoogleIdToken: async (t: string) => ({ subject: t, email: `${t}@gmail.com`, name: 'Linked User' }),
  verifyAppleIdToken: async (t: string) => ({ subject: t, email: null, name: null }),
}));

describe.skipIf(!TEST_DB_URL)('guest merge and rollups (Postgres)', () => {
  let h: Harness;
  // Wednesday 2026-11-11, 10:00 Cairo — week of Saturday 2026-11-07.
  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
  });
  afterAll(async () => h?.close());

  type Daily = { user_id: string; day: string; earned: number };
  type Totals = { user_id: string; lifetime_earned: number };
  const dailies = async () =>
    (await h.db.execute<Daily>(sql`select user_id, day::text as day, earned from points_earned_daily order by user_id, day`)).rows.map((r) => ({ ...r, earned: Number(r.earned) }));
  const totals = async () =>
    (await h.db.execute<Totals>(sql`select user_id, lifetime_earned from user_point_totals order by user_id`)).rows.map((r) => ({ ...r, lifetime_earned: Number(r.lifetime_earned) }));

  it('a mid-week merge keeps the week points, gives the right level and counts nothing twice', async () => {
    const owner = await makeUser(h, 'Owner');
    await h.db.insert(s.authIdentities).values({ userId: owner.id, provider: 'google', subject: 'sub-account-owner' });
    await earn(h, owner.id, 300, '2026-11-08T10:00:00Z'); // Sunday
    await earn(h, owner.id, 100, '2026-10-20T10:00:00Z'); // an older week

    const guest = (await h.app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'guest' } })).json();
    const gid = guest.user.id as string;
    await earn(h, gid, 50, '2026-11-08T12:00:00Z'); // same Cairo day as the owner's 300
    await earn(h, gid, 200, '2026-11-10T09:00:00Z', 'qada'); // Tuesday

    const res = await h.app.inject({ method: 'POST', url: '/v1/auth/link', headers: auth(guest.accessToken), payload: { provider: 'google', idToken: 'sub-account-owner' } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.id).toBe(owner.id);

    // The guest's days moved over (summed on the shared day); none are left on the guest.
    const days = (await dailies()).filter((d) => d.user_id === owner.id || d.user_id === gid);
    expect(days).toEqual([
      { user_id: owner.id, day: '2026-10-20', earned: 100 },
      { user_id: owner.id, day: '2026-11-08', earned: 350 },
      { user_id: owner.id, day: '2026-11-10', earned: 200 },
    ]);

    // Week points (live, self) = 300 + 50 + 200 — the 250 grant is not an earned reason.
    const me = (await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(res.json().accessToken) })).json();
    expect(me.weekPoints).toBe(550);
    // Level: own earned 400 + the merge grant 250 = 650 ≥ 500 → level 2; counted once.
    expect(me.lifetimePoints).toBe(650);
    expect(me.level.level).toBe(2);
    const ownerTotals = (await totals()).find((t) => t.user_id === owner.id);
    expect(ownerTotals?.lifetime_earned).toBe(650);
  });

  it('yq_rebuild_points_rollups() reproduces what the trigger and the merge left', async () => {
    const before = { d: await dailies(), t: await totals() };
    await h.db.execute(sql`select yq_rebuild_points_rollups()`);
    const after = { d: await dailies(), t: await totals() };
    expect(after.d).toEqual(before.d);
    // The rebuild may drop all-zero guest rows; every positive lifetime must match.
    const positive = (t: Totals[]) => t.filter((x) => x.lifetime_earned > 0);
    expect(positive(after.t)).toEqual(positive(before.t));
  });
});
