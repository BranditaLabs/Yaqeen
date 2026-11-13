/**
 * Migration 0017: the `yq_points_rollup` trigger keeps `points_earned_daily` (EARNED_REASONS, per
 * Africa/Cairo day) and `user_point_totals.lifetime_earned` (LEVEL_REASONS, delta > 0) in step with
 * the append-only ledger, and `yq_rebuild_points_rollups()` recomputes exactly the same rows. The
 * rebuild attributes a merged guest's earned days to the account. Skipped without TEST_DATABASE_URL.
 */
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { EARNED_REASONS, LEVEL_REASONS } from '@yaqeen/contracts';
import { createDb, type Db } from '../src/db/client.js';

const url = process.env.TEST_DATABASE_URL;

type Daily = { user_id: string; day: string; earned: number };
type Total = { user_id: string; lifetime_earned: number; public_lifetime: number };

describe.skipIf(!url)('points rollups (Postgres, migration 0017)', () => {
  let db: Db;
  let pool: pg.Pool;
  let seq = 0;

  const user = async (extra: { guest?: boolean } = {}): Promise<string> => {
    const r = await pool.query<{ id: string }>('insert into users (is_guest) values ($1) returning id', [extra.guest ?? false]);
    return r.rows[0]!.id;
  };
  const ledger = (userId: string, delta: number, reason: string, at: string) =>
    pool.query('insert into points_ledger (user_id, delta, reason, ref_key, created_at) values ($1, $2, $3, $4, $5)', [
      userId,
      delta,
      reason,
      `t:${++seq}`,
      at,
    ]);
  const daily = async (): Promise<Daily[]> =>
    (
      await pool.query<Daily>(
        `select user_id, to_char(day, 'YYYY-MM-DD') as day, earned from points_earned_daily order by user_id, day`,
      )
    ).rows;
  const totals = async (): Promise<Total[]> =>
    (await pool.query<Total>('select user_id, lifetime_earned, public_lifetime from user_point_totals order by user_id')).rows;

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });
  });

  afterAll(async () => {
    await pool?.end();
  });

  it('the SQL reason lists match the contracts constants', async () => {
    const src = (await pool.query<{ src: string }>(`select prosrc as src from pg_proc where proname = 'yq_points_rollup'`)).rows[0]!.src;
    expect(src).toContain(`IN (${EARNED_REASONS.map((r) => `'${r}'`).join(', ')})`);
    expect(src).toContain(`IN (${LEVEL_REASONS.map((r) => `'${r}'`).join(', ')})`);
  });

  it('the trigger equals the rebuild after mixed inserts (incl. a raw-SQL grant and a reversal)', async () => {
    const a = await user();
    const b = await user();
    // Cairo is UTC+2 in winter: 22:30Z on the 19th is 00:30 on the 20th in Cairo.
    await ledger(a, 20, 'task', '2026-11-19T21:30:00Z'); // Cairo 2026-11-19 23:30
    await ledger(a, 10, 'task', '2026-11-19T22:30:00Z'); // Cairo 2026-11-20 00:30
    await ledger(a, 15, 'qada', '2026-11-20T10:00:00Z');
    await ledger(a, 50, 'bonus', '2026-11-20T11:00:00Z');
    await ledger(a, 100, 'milestone', '2026-11-21T09:00:00Z');
    await ledger(a, -200, 'redemption', '2026-11-21T10:00:00Z');
    await ledger(a, 30, 'admin_adjustment', '2026-11-21T11:00:00Z');
    await ledger(a, -30, 'admin_adjustment', '2026-11-21T12:00:00Z');
    await ledger(a, 200, 'reversal', '2026-11-21T13:00:00Z'); // a refunded redemption never raises a level
    // The raw-SQL grant the rewards route writes (no ORM, still caught by the trigger).
    await pool.query(
      `insert into points_ledger (user_id, delta, reason, ref_key, note, created_at) values ($1, 500, 'grant', 'grant:raw', 'raw sql', '2026-11-21T14:00:00Z')`,
      [b],
    );
    await ledger(b, 25, 'task', '2026-11-22T08:00:00Z');

    const trigDaily = await daily();
    const trigTotals = await totals();

    expect(trigDaily.filter((r) => r.user_id === a)).toEqual([
      { user_id: a, day: '2026-11-19', earned: 20 },
      { user_id: a, day: '2026-11-20', earned: 75 },
      { user_id: a, day: '2026-11-21', earned: 100 },
    ]);
    expect(trigDaily.filter((r) => r.user_id === b)).toEqual([{ user_id: b, day: '2026-11-22', earned: 25 }]);
    const ta = trigTotals.find((r) => r.user_id === a)!;
    const tb = trigTotals.find((r) => r.user_id === b)!;
    expect(ta.lifetime_earned).toBe(20 + 10 + 15 + 50 + 100 + 30);
    expect(tb.lifetime_earned).toBe(525);
    // The public snapshot only moves when the nightly job (or a rebuild) runs.
    expect(ta.public_lifetime).toBe(0);

    await pool.query('select yq_rebuild_points_rollups()');
    expect(await daily()).toEqual(trigDaily);
    const rebuilt = await totals();
    expect(rebuilt.map(({ user_id, lifetime_earned }) => ({ user_id, lifetime_earned }))).toEqual(
      trigTotals.map(({ user_id, lifetime_earned }) => ({ user_id, lifetime_earned })),
    );
    expect(rebuilt.every((r) => r.public_lifetime === r.lifetime_earned)).toBe(true);
  });

  it("the rebuild attributes a merged guest's earned days to the account", async () => {
    const account = await user();
    const guest = await user({ guest: true });
    await ledger(guest, 20, 'task', '2026-11-23T08:00:00Z');
    await ledger(account, 10, 'task', '2026-11-23T09:00:00Z');
    await ledger(guest, 40, 'task', '2026-11-24T08:00:00Z');
    // Linking into an existing account marks the guest merged and grants its balance once.
    await pool.query('update users set merged_into = $1 where id = $2', [account, guest]);
    await ledger(account, 60, 'grant', '2026-11-24T09:00:00Z');

    await pool.query('select yq_rebuild_points_rollups()');
    const rows = await daily();
    expect(rows.filter((r) => r.user_id === guest)).toEqual([]);
    expect(rows.filter((r) => r.user_id === account)).toEqual([
      { user_id: account, day: '2026-11-23', earned: 30 },
      { user_id: account, day: '2026-11-24', earned: 40 },
    ]);
    // The merge grant counts once toward the level and never toward period points.
    const t = await totals();
    expect(t.find((r) => r.user_id === account)!.lifetime_earned).toBe(70);
  });
});
