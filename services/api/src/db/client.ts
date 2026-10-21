import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import pg from 'pg';
import * as schema from './schema.js';

export type Db = NodePgDatabase<typeof schema>;

export interface PoolOptions {
  /** Connections per API instance. Instances × max must stay below Postgres max_connections
   *  (or PgBouncer's pool) — see docs/OPERATIONS.md. */
  max?: number;
  /** Server-side cap so one slow query can't hold a connection forever under load. */
  statementTimeoutMs?: number;
}

export function createDb(databaseUrl: string, opts: PoolOptions = {}): { db: Db; pool: pg.Pool } {
  const pool = new pg.Pool({
    connectionString: databaseUrl,
    max: opts.max ?? 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    ...(opts.statementTimeoutMs ? { statement_timeout: opts.statementTimeoutMs } : {}),
    application_name: 'yaqeen-api',
  });
  const db = drizzle(pool, { schema });
  return { db, pool };
}

export { schema };
