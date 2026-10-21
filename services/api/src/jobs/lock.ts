import type pg from 'pg';

/**
 * Run `fn` only if no other process holds the job's lock (Postgres session advisory lock on a
 * dedicated connection). With several replicas or an overlapping cron run, exactly one does the
 * work and the others skip — so a campaign can never be sent twice in parallel.
 */
export async function withJobLock<T>(pool: pg.Pool, name: string, fn: () => Promise<T>): Promise<{ ran: true; result: T } | { ran: false }> {
  const client = await pool.connect();
  try {
    const { rows } = await client.query<{ ok: boolean }>('select pg_try_advisory_lock(hashtext($1)) as ok', [`job:${name}`]);
    if (!rows[0]?.ok) return { ran: false };
    try {
      return { ran: true, result: await fn() };
    } finally {
      await client.query('select pg_advisory_unlock(hashtext($1))', [`job:${name}`]);
    }
  } finally {
    client.release();
  }
}
