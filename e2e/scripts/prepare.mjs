// Fresh database for the browser tests: drop everything, run the real migrations and seed, create a
// super admin (its TOTP secret is captured from the seed's one-time output) and one published public
// card with a medal tag. Writes e2e/.auth/fixture.json for the tests. Never point this at real data.
import { execFileSync } from 'node:child_process';
import { createHash, createHmac } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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

const email = 'e2e-admin@yaqeenarabia.com';
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

const competitions = await seedCompetitions();
const recitations = await seedRecitations(competitions.runner, competitions.removed);
const cardRecitations = await seedCardRecitations();
await db.end();

mkdirSync(join(here, '..', '.auth'), { recursive: true });
writeFileSync(join(here, '..', '.auth', 'fixture.json'), JSON.stringify({ email, password, totpSecret, handle, tagCode, ...competitions, recitations, cardRecitations }, null, 2));
console.log(`e2e database ready: ${dbName} (admin ${email}, card /u/${handle}, tag /t/${tagCode}, tournament ${competitions.tournamentId})`);

/** HS256 admin session token, as the API signs it (dev secret; staff roles without a TOTP login each). */
function adminToken(sub, role) {
  const secret = process.env.ADMIN_JWT_SECRET ?? 'dev-only-admin-secret-change-me-dev-only';
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const body = `${b64({ alg: 'HS256' })}.${b64({ role, sub, iss: 'yaqeen-api', aud: 'admin', iat: now, exp: now + 8 * 3600 })}`;
  return `${body}.${createHmac('sha256', secret).update(body).digest('base64url')}`;
}

/**
 * «المسابقات» (design §11): staff in the other roles; an opted-in, attested member (preset m03, ledger
 * task rows, published card) in a live tournament, this league week and the level board; a member
 * whose photo support removed a day ago; a card owner with an active, attested photo and one open
 * report against it. Standings are snapshot values, as the nightly job would leave them.
 */
async function seedCompetitions() {
  const {
    rows: [boss],
  } = await db.query('select id, password_hash, totp_secret from admin_users where email = $1', [email]);
  const tokens = {};
  for (const role of ['marketing', 'support', 'content_editor']) {
    const {
      rows: [a],
    } = await db.query(`insert into admin_users (name, email, password_hash, totp_secret, role) values ($1, $2, $3, $4, $5) returning id`, [
      `E2E ${role}`,
      `e2e-${role.replace('_', '-')}@yaqeenarabia.com`,
      boss.password_hash,
      boss.totp_secret,
      role,
    ]);
    tokens[role] = adminToken(a.id, role);
  }

  // Cairo today and this league week's Saturday (DST-safe: Postgres does the zone maths).
  const {
    rows: [{ today, week }],
  } = await db.query(`select d::text as today, (d - ((extract(isodow from d)::int + 1) % 7))::text as week from (select (now() at time zone 'Africa/Cairo')::date as d) x`);
  const show = JSON.stringify({ level: true, streak: false, challengeDay: false, badges: false, memberSince: true });
  const member = async ({ name, mail, handle, published, preset }) => {
    const {
      rows: [u],
    } = await db.query(
      `insert into users (display_name, email, locale, avatar_kind, avatar_preset, adult_attested_at, country) values ($1, $2, 'ar', $3, $4, now(), 'EG') returning id`,
      [name, mail, preset ? 'preset' : 'initial', preset ?? null],
    );
    await db.query(`insert into public_profiles (user_id, handle, published, display_name, bio, links, show, theme) values ($1, $2, $3, $4, '', '[]', $5, 'sky')`, [
      u.id,
      handle,
      published,
      name,
      show,
    ]);
    return u.id;
  };
  const webp = readFileSync(join(repo, 'apps', 'mobile', 'assets', 'avatars', 'f05.webp'));
  const sha = createHash('sha256').update(webp).digest('hex');
  const photo = async (userId, extra) => {
    const {
      rows: [p],
    } = await db.query(
      `insert into avatar_photos (user_id, sha_small, sha_large, small, large, bytes, status, created_at, removed_at, removed_by, removed_reason)
       values ($1, $2, $2, $3, $3, $4, $5, now() - interval '2 days', $6, $7, $8) returning id`,
      [userId, sha, webp, webp.length, extra.status, extra.removedAt ?? null, extra.removedBy ?? null, extra.reason ?? null],
    );
    return p.id;
  };

  // Card handles follow PROFILE_HANDLE (letters, digits, _ and .). The competitor: preset m03, 600 earned points (level 2), card published so /u/<handle> draws the ring.
  const runner = { handle: 'e2e_runner', name: 'عمر المتسابق' };
  runner.id = await member({ ...runner, mail: 'runner@example.com', published: true, preset: 'm03' });
  for (let i = 1; i <= 6; i++) {
    await db.query(`insert into points_ledger (user_id, delta, reason, ref_key, created_at) values ($1, 100, 'task', $2, now() - make_interval(days => $3))`, [
      runner.id,
      `e2e-task-${i}`,
      i,
    ]);
  }
  await db.query(`update user_point_totals set public_lifetime = lifetime_earned, public_day = $2::date where user_id = $1`, [runner.id, today]);

  // Support removed this member's photo yesterday (restorable for 7 days).
  const removed = { handle: 'e2e_removed', name: 'ليلى' };
  removed.id = await member({ ...removed, mail: 'removed@example.com', published: false, preset: 'f02' });
  removed.photoId = await photo(removed.id, { status: 'removed', removedAt: new Date(Date.now() - 86_400_000), removedBy: boss.id, reason: 'e2e: صورة غير لائقة' });
  await db.query(`update users set photo_locked_at = now() - interval '1 day' where id = $1`, [removed.id]);

  // A published card with an active, attested photo, and one open report against it.
  const pictured = { handle: 'e2e_photo', name: 'هدى' };
  pictured.id = await member({ ...pictured, mail: 'photo@example.com', published: true });
  pictured.photoId = await photo(pictured.id, { status: 'active' });
  await db.query(`update users set avatar_kind = 'photo', avatar_photo_id = $2 where id = $1`, [pictured.id, pictured.photoId]);
  await db.query(`insert into community_reports (reporter_id, target_user_id, reason) values ($1, $2, 'photo')`, [runner.id, pictured.id]);

  await db.query(`insert into community_members (user_id, leagues, leaderboard) values ($1, true, true), ($2, true, false)`, [runner.id, removed.id]);
  await db.query(`insert into consents (user_id, kind, granted) values ($1, 'community', true), ($2, 'community', true)`, [runner.id, removed.id]);

  // A live tournament (whole Cairo days: started two days ago, last day in six days).
  const midnight = (expr) => `((${expr})::timestamp at time zone 'Africa/Cairo')`;
  const {
    rows: [tournament],
  } = await db.query(
    `insert into tournaments (slug, title_ar, title_en, body_ar, body_en, starts_at, ends_at, join_until, badge_ar, badge_en, min_points, status, created_by)
     values ('e2e-autumn', 'بطولة الخريف', 'Autumn tournament', 'أسبوع من المواظبة معاً.', 'A steady week together.',
       ${midnight('$1::date - 2')}, ${midnight('$1::date + 7')}, ${midnight('$1::date + 7')}, 'وسام الخريف', 'Autumn medal', 50, 'published', $2)
     returning id`,
    [today, boss.id],
  );
  await db.query(
    `insert into tournament_entries (tournament_id, user_id, snapshot_points, snapshot_rank) values ($1, $2, 240, 1), ($1, $3, 120, 2)`,
    [tournament.id, runner.id, removed.id],
  );

  // This league week, its settings and one division-1 group with snapshot values.
  await db.query(
    `insert into league_weeks (starts_on, starts_at, ends_at, settings, status) values ($1::date, ${midnight('$1::date')}, ${midnight('$1::date + 7')}, $2::jsonb, 'open')`,
    [week, JSON.stringify({ groupSize: 30, promote: 5, demote: 5 })],
  );
  const {
    rows: [group],
  } = await db.query(`insert into league_groups (starts_on, division, size) values ($1::date, 1, 2) returning id`, [week]);
  await db.query(
    `insert into league_members (starts_on, user_id, group_id, division, snapshot_points, snapshot_rank) values ($1::date, $2, $4, 1, 180, 1), ($1::date, $3, $4, 1, 0, null)`,
    [week, runner.id, removed.id, group.id],
  );

  // Tonight's snapshot of the level board.
  await db.query(`insert into leaderboard_snapshot (scope, country, user_id, rank, lifetime, day) values ('global', '', $1, 1, 600, $2::date)`, [runner.id, today]);
  await db.query(`insert into community_snapshot_days (day) values ($1::date)`, [today]);

  return { today, tokens, runner, removed, pictured, tournamentId: tournament.id, groupId: group.id };
}

/**
 * «التلاوات» (design doc §16): a recording the AI check sent to review (members, with a transcript), an
 * approved public recording held by 3 reports, and a comment on it hidden by reports. A religious
 * reviewer joins the staff. The audio is a stub MPEG-4 header (the admin player only needs the bytes).
 */
async function seedRecitations(runner, removed) {
  const {
    rows: [boss],
  } = await db.query('select password_hash, totp_secret from admin_users where email = $1', [email]);
  const {
    rows: [reviewer],
  } = await db.query(
    `insert into admin_users (name, email, password_hash, totp_secret, role) values ('E2E religious_reviewer', 'e2e-religious-reviewer@yaqeenarabia.com', $1, $2, 'religious_reviewer') returning id`,
    [boss.password_hash, boss.totp_secret],
  );
  const audio = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypM4A ', 'latin1'), Buffer.alloc(4), Buffer.from('M4A mp42', 'latin1'), Buffer.alloc(2048, 0x21)]);
  const rec = async (status, visibility, extra = {}) => {
    const {
      rows: [r],
    } = await db.query(
      `insert into recordings (user_id, surah, from_ayah, to_ayah, duration_ms, audio, bytes, status, visibility, position, score, speech, transcript, held_at, verified_at)
       values ($1, $2, $3, $4, 12000, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) returning id`,
      [extra.user ?? runner.id, extra.surah, extra.from, extra.to, audio, audio.length, status, visibility, extra.position ?? 1, extra.score ?? null, 0.7, extra.transcript ?? null, extra.held ? new Date() : null, status === 'approved' ? new Date() : null],
    );
    return r.id;
  };
  const flagged = await rec('needs_review', 'members', { surah: 112, from: 1, to: 4, score: 0.56, transcript: 'نص تجريبي من الفحص الآلي' });
  const held = await rec('approved', 'public', { surah: 1, from: 1, to: 7, score: 0.95, held: true, position: 2 });
  const {
    rows: [comment],
  } = await db.query(`insert into recording_comments (recording_id, user_id, text, status) values ($1, $2, 'تعليق مُبلَّغ عنه للاختبار', 'hidden') returning id`, [held, removed.id]);
  for (const reason of ['spam', 'inappropriate']) {
    await db.query(`insert into recording_reports (target, target_id, reporter_id, reason) values ('comment', $1, $2, $3) on conflict do nothing`, [comment.id, reason === 'spam' ? runner.id : removed.id, reason]);
  }
  await db.query(`insert into recording_reports (target, target_id, reporter_id, reason) values ('recording', $1, $2, 'not_recitation')`, [held, removed.id]);
  return { flagged, held, comment: comment.id, reviewerToken: adminToken(reviewer.id, 'religious_reviewer') };
}

/**
 * «تلاواتي» on the web card: a member (attested, in the community) with a published card and two public,
 * approved recordings carrying verified word timings, with the `recordings` switch on. The stored audio
 * is a stub; the browser test routes the audio to a short generated tone.
 */
async function seedCardRecitations() {
  await db.query(
    `insert into app_config (key, value) values ('features', '{"recordings": true}'::jsonb)
     on conflict (key) do update set value = app_config.value || excluded.value`,
  );
  const owner = { handle: 'e2e_reciter', name: 'يوسف القارئ' };
  const {
    rows: [u],
  } = await db.query(`insert into users (display_name, email, locale, adult_attested_at, country) values ($1, 'reciter@example.com', 'ar', now(), 'EG') returning id`, [owner.name]);
  const show = JSON.stringify({ level: true, streak: false, challengeDay: false, badges: false, memberSince: false });
  await db.query(`insert into public_profiles (user_id, handle, published, display_name, bio, links, show, theme) values ($1, $2, true, $3, '', '[]', $4, 'sky')`, [u.id, owner.handle, owner.name, show]);
  await db.query(`insert into consents (user_id, kind, granted) values ($1, 'community', true)`, [u.id]);
  // 800 earned points (level 2, part way to 3) in the public snapshot, so the card draws its level ring.
  for (let i = 1; i <= 8; i++) {
    await db.query(`insert into points_ledger (user_id, delta, reason, ref_key, created_at) values ($1, 100, 'task', $2, now() - make_interval(days => $3))`, [u.id, `e2e-reciter-task-${i}`, i]);
  }
  await db.query(`update user_point_totals set public_lifetime = lifetime_earned, public_day = (now() at time zone 'Africa/Cairo')::date where user_id = $1`, [u.id]);
  const audio = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypM4A ', 'latin1'), Buffer.alloc(4), Buffer.from('M4A mp42', 'latin1'), Buffer.alloc(1024, 0x21)]);
  const rec = async (surah, from, to, position) => {
    // One word per ayah, 350 ms apart: the lit ayah number moves within the 1.6 s test tone.
    const words = Array.from({ length: to - from + 1 }, (_, i) => ({ ayah: from + i, index: 0, startMs: i * 350, endMs: i * 350 + 300 }));
    const {
      rows: [r],
    } = await db.query(
      `insert into recordings (user_id, surah, from_ayah, to_ayah, duration_ms, audio, bytes, status, visibility, position, score, speech, words, verified_at)
       values ($1, $2, $3, $4, 1600, $5, $6, 'approved', 'public', $7, 0.97, 0.8, $8::jsonb, now()) returning id`,
      [u.id, surah, from, to, audio, audio.length, position, JSON.stringify(words)],
    );
    return r.id;
  };
  const first = await rec(112, 1, 4, 1);
  const second = await rec(113, 1, 5, 2);
  return { handle: owner.handle, first, second };
}
