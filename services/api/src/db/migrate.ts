/**
 * Production migrator (no drizzle-kit needed in the image): `node dist/db/migrate.js`.
 * Takes an advisory lock so two release pipelines can never migrate at once.
 */
import { fileURLToPath } from 'node:url';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { loadEnv } from '../config/env.js';
import { withJobLock } from '../jobs/lock.js';
import { createDb } from './client.js';

const env = loadEnv();
const { db, pool } = createDb(env.DATABASE_URL, { max: 2 });
const folder = fileURLToPath(new URL('../../drizzle', import.meta.url));
const res = await withJobLock(pool, 'migrate', () => migrate(db, { migrationsFolder: folder }));
console.log(res.ran ? `[migrate] up to date (${folder})` : '[migrate] another migration holds the lock — nothing done');
await pool.end();
if (!res.ran) process.exit(1);
