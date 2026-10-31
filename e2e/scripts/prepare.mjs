// Fresh database for the browser tests: drop everything, run the real migrations and seed, create a
// super admin (its TOTP secret is captured from the seed's one-time output) and one published public
// card with a medal tag. Writes e2e/.auth/fixture.json for the tests. Never point this at real data.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const url = process.env.E2E_DATABASE_URL ?? 'postgres://yq:yq@127.0.0.1:5432/yqe2e';
const dbName = new URL(url).pathname.slice(1);
if (!/e2e/.test(dbName)) throw new Error(`refusing to reset "${dbName}": the e2e database name must contain "e2e"`);

// Create the database if needed, then wipe it.
const admin = new pg.Client({ connectionString: url.replace(/\/[^/]+$/, '/postgres') });
await admin.connect();
const { rowCount } = await admin.query('select 1 from pg_database where datname = $1', [dbName]);
if (!rowCount) await admin.query(`create database "${dbName}"`);
await admin.end();
const db = new pg.Client({ connectionString: url });
await db.connect();
await db.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');

const env = { ...process.env, DATABASE_URL: url, REDIS_URL: '', NODE_ENV: 'development' };
// pnpm is a .cmd shim on Windows, which only a shell can start (the args are fixed strings).
const run = (args, extra = {}) =>
  execFileSync('pnpm', ['--filter', '@yaqeen/api', ...args], { cwd: repo, env: { ...env, ...extra }, encoding: 'utf8', shell: process.platform === 'win32' });
run(['db:migrate']);

const email = 'e2e-admin@yaqin-brand.com';
const password = 'e2e-password-not-secret';
const seedOut = run(['db:seed'], { SEED_ADMIN_EMAIL: email, SEED_ADMIN_PASSWORD: password });
const totpSecret = /secret=([A-Z2-7]+)/.exec(seedOut)?.[1];
if (!totpSecret) throw new Error(`seed did not print a TOTP secret:\n${seedOut}`);

// One member with a published card (the bio carries markup that must render as text) and a medal.
const handle = 'e2e_card';
const tagCode = 'E2ETAG23'; // from TAG_ALPHABET (no 0, 1, I or O)
const {
  rows: [user],
} = await db.query(`insert into users (display_name, email, locale) values ('E2E Member', 'member@example.com', 'ar') returning id`);
await db.query(
  `insert into public_profiles (user_id, handle, published, display_name, bio, links, show, theme)
   values ($1, $2, true, 'عبد الله', $3, '[]', $4, 'sky')`,
  [user.id, handle, '<img src=x onerror="window.__xss=1">نسأل الله الثبات', JSON.stringify({ level: true, streak: true, challengeDay: false, badges: false, memberSince: true })],
);
await db.query(`insert into tag_batches (batch, kind, status) values ('e2e', 'medal', 'on_sale')`);
await db.query(`insert into profile_tags (code, kind, batch, user_id, linked_at) values ($1, 'medal', 'e2e', $2, now())`, [tagCode, user.id]);
await db.end();

mkdirSync(join(here, '..', '.auth'), { recursive: true });
writeFileSync(join(here, '..', '.auth', 'fixture.json'), JSON.stringify({ email, password, totpSecret, handle, tagCode }, null, 2));
console.log(`e2e database ready: ${dbName} (admin ${email}, card /u/${handle}, tag /t/${tagCode})`);
