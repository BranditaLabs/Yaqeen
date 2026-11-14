/**
 * «تلاواتي» against Postgres: upload → processing → approved / rejected / needs_review with a fake ASR,
 * the visibility gates (account, 18+ attestation, community, blocks), limits, reactions, comments
 * (filter, rate limit, reports → auto-hide), owner delete, the web card, export/erasure and the admin
 * queue (roles, audit). Skipped without TEST_DATABASE_URL — see integration.db.test.ts.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { and, eq, sql } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import type { AsrVerifyResponse } from '@yaqeen/contracts';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { type AsrClient, AsrUnavailable } from '../src/integrations/asr.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { buildMultipart } from '../src/lib/multipart.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';
import { resetActivityCache } from '../src/services/activity.service.js';
import * as rec from '../src/services/recordings.service.js';
import { runCommunity } from '../src/jobs/community.js';
import { buildM4a } from './helpers/m4a.js';

const url = process.env.TEST_DATABASE_URL;
let now = new Date('2026-11-14T08:00:00Z');

const cases = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../../packages/contracts/fixtures/recitation-match/cases.json', import.meta.url)), 'utf8'),
) as { name: string; surah: number; fromAyah: number; toAyah: number; heard: AsrVerifyResponse['words']; durationMs: number; speechMs: number }[];
const sample = (name: string) => cases.find((c) => c.name === name)!;

/** A programmable ASR: answers with the next queued response (or throws), counting calls. */
class FakeAsr implements AsrClient {
  calls = 0;
  next: (AsrVerifyResponse | Error)[] = [];
  async verify(): Promise<AsrVerifyResponse> {
    this.calls++;
    const r = this.next.shift();
    if (!r) throw new AsrUnavailable('no response queued');
    if (r instanceof Error) throw r;
    return r;
  }
  answer(name: string) {
    const c = sample(name);
    this.next.push({ durationMs: c.durationMs, speechMs: c.speechMs, transcript: c.heard.map((w) => w.text).join(' '), words: c.heard });
  }
}

describe.skipIf(!url)('recordings «تلاواتي» (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const asr = new FakeAsr();
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip', PUBLIC_PROFILE_BASE_URL: 'https://id.test' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });
  let seq = 0;

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });
    resetActivityCache();
    await db.insert(s.appConfig).values({ key: 'features', value: { recordings: true } });
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      asr,
      now: () => now,
    });
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  beforeEach(() => {
    asr.next = [];
    asr.calls = 0;
    app.ctx.asr = asr;
  });

  /** A user; `member` = attested + community consent + handle (+ a published card when `card`). */
  async function makeUser(opts: { member?: boolean; attested?: boolean; community?: boolean; guest?: boolean; card?: boolean } = {}) {
    const n = ++seq;
    const attested = opts.attested ?? opts.member ?? false;
    const community = opts.community ?? opts.member ?? false;
    const [u] = await db
      .insert(s.users)
      .values({ displayName: `User ${n}`, isGuest: opts.guest ?? false, adultAttestedAt: attested ? now : null })
      .returning();
    const handle = `member${n}x`;
    if (community || opts.card) {
      await db.insert(s.publicProfiles).values({
        userId: u!.id,
        handle,
        published: opts.card ?? false,
        displayName: `User ${n}`,
        show: { level: true, streak: false, challengeDay: false, badges: false, memberSince: false },
      });
    }
    if (community) await db.insert(s.consents).values({ userId: u!.id, kind: 'community', granted: true });
    return { id: u!.id, handle, token: await signUserToken({ sub: u!.id, guest: opts.guest ?? false }, env.JWT_SECRET) };
  }

  async function upload(token: string, meta: Record<string, unknown>, audio: Buffer = buildM4a(), contentType = 'audio/mp4') {
    const boundary = `yq${Math.random().toString(36).slice(2)}`;
    const body = buildMultipart(boundary, [
      { name: 'meta', contentType: 'application/json', data: JSON.stringify(meta) },
      { name: 'audio', filename: 'r.m4a', contentType, data: audio },
    ]);
    return app.inject({ method: 'POST', url: '/v1/me/recordings', headers: { ...auth(token), 'content-type': `multipart/form-data; boundary=${boundary}` }, payload: body });
  }

  const meta = (c: string, visibility = 'members') => {
    const x = sample(c);
    return { surah: x.surah, fromAyah: x.fromAyah, toAyah: x.toAyah, durationMs: 12_000, visibility };
  };

  async function approvedRecording(owner: { token: string }, visibility = 'members') {
    asr.answer('exact_recitation');
    const r = await upload(owner.token, meta('exact_recitation', visibility));
    expect(r.statusCode).toBe(202);
    await rec.drain(app.ctx);
    return r.json().id as string;
  }

  async function adminToken(role: 'religious_reviewer' | 'support' | 'marketing') {
    const [a] = await db
      .insert(s.adminUsers)
      .values({ name: role, email: `${role}${++seq}@x.com`, role, passwordHash: 'x', totpSecret: 'x' })
      .returning();
    return { id: a!.id, token: await signAdminToken({ sub: a!.id, role }, env.ADMIN_JWT_SECRET) };
  }

  it('private upload: private_ready, owner-only playback with byte ranges, never sent to the AI check', async () => {
    const u = await makeUser();
    const audio = buildM4a({ durationMs: 9_500 });
    const r = await upload(u.token, { surah: 1, fromAyah: 1, toAyah: 4, durationMs: 9_400 }, audio);
    expect(r.statusCode).toBe(202);
    const body = r.json();
    expect(body).toMatchObject({ status: 'private_ready', visibility: 'private', durationMs: 9_500, position: 1, words: null, audioPath: `/v1/me/recordings/${body.id}/audio` });
    await rec.drain(app.ctx);
    expect(asr.calls).toBe(0);
    const full = await app.inject({ method: 'GET', url: body.audioPath, headers: auth(u.token) });
    expect(full.statusCode).toBe(200);
    expect(full.headers['content-type']).toBe('audio/mp4');
    expect(full.rawPayload.equals(audio)).toBe(true);
    const part = await app.inject({ method: 'GET', url: body.audioPath, headers: { ...auth(u.token), range: 'bytes=0-99' } });
    expect(part.statusCode).toBe(206);
    expect(part.headers['content-range']).toBe(`bytes 0-99/${audio.length}`);
    const other = await makeUser({ member: true });
    expect((await app.inject({ method: 'GET', url: body.audioPath, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${body.id}/audio`, headers: auth(other.token) })).statusCode).toBe(404);
  });

  it('upload validation: size, format, duration, range', async () => {
    const u = await makeUser();
    const m = { surah: 112, fromAyah: 1, toAyah: 4, durationMs: 9_000 };
    const code = async (res: Promise<{ statusCode: number; json: () => { error: { code: string } } }>) => (await res).json().error.code;
    expect(await code(upload(u.token, m, buildM4a({ payload: 210_000 })))).toBe('recording_too_large');
    expect(await code(upload(u.token, m, Buffer.from('not audio at all, definitely not')))).toBe('recording_bad_format');
    expect(await code(upload(u.token, m, buildM4a({ channels: 2 })))).toBe('recording_bad_format');
    expect(await code(upload(u.token, m, buildM4a(), 'audio/ogg'))).toBe('recording_bad_format');
    expect(await code(upload(u.token, m, buildM4a({ durationMs: 31_000 })))).toBe('recording_too_long');
    expect(await code(upload(u.token, { ...m, durationMs: 40_000 }))).toBe('recording_too_long');
    expect(await code(upload(u.token, { ...m, toAyah: 5 }))).toBe('recording_invalid_range');
    expect(await code(upload(u.token, { ...m, fromAyah: 3, toAyah: 2 }))).toBe('recording_invalid_range');
    const plain = await app.inject({ method: 'POST', url: '/v1/me/recordings', headers: { ...auth(u.token), 'content-type': 'application/json' }, payload: m });
    expect(plain.json().error.code).toBe('recording_bad_format');
  });

  it('sharing gates: account, attestation, community', async () => {
    const guest = await makeUser({ guest: true });
    expect((await upload(guest.token, meta('exact_recitation'))).json().error.code).toBe('account_required');
    expect((await upload(guest.token, { ...meta('exact_recitation'), visibility: 'private' })).json().error.code).toBe('account_required');
    const unattested = await makeUser({ community: true, attested: false });
    expect((await upload(unattested.token, meta('exact_recitation'))).json().error.code).toBe('attestation_required');
    const outsider = await makeUser({ attested: true, community: false });
    expect((await upload(outsider.token, meta('exact_recitation', 'public'))).json().error.code).toBe('community_required');
    const banned = await makeUser({ member: true });
    await db.insert(s.communityMembers).values({ userId: banned.id, bannedAt: now });
    expect((await upload(banned.token, meta('exact_recitation'))).json().error.code).toBe('community_banned');
    // A private one is fine without the community.
    expect((await upload(outsider.token, { ...meta('exact_recitation'), visibility: 'private' })).statusCode).toBe(202);
    expect(asr.calls).toBe(0);
  });

  it('AI check: correct → approved with karaoke words; wrong verses / silence → rejected; partial → needs_review', async () => {
    const u = await makeUser({ member: true });
    const ok = await approvedRecording(u);
    for (const [c, status, reason] of [
      ['wrong_verses', 'rejected', 'not_matching'],
      ['silence', 'rejected', 'silence'],
    ] as const) {
      asr.answer(c);
      const r = await upload(u.token, meta(c));
      expect(r.json().status).toBe('processing');
      await rec.drain(app.ctx);
      const row = (await rec.listMine(app.ctx, u.id)).items.find((x) => x.id === r.json().id)!;
      expect(row).toMatchObject({ status, rejectReason: reason, words: null });
      await app.inject({ method: 'DELETE', url: `/v1/me/recordings/${row.id}`, headers: auth(u.token) });
    }
    asr.answer('partial_recitation');
    const p = await upload(u.token, meta('partial_recitation'));
    await rec.drain(app.ctx);
    const mine = await rec.listMine(app.ctx, u.id);
    const approved = mine.items.find((x) => x.id === ok)!;
    expect(approved.status).toBe('approved');
    expect(approved.words!.length).toBeGreaterThan(5);
    expect(approved.words![0]).toMatchObject({ ayah: 1, index: 0 });
    const partial = mine.items.find((x) => x.id === p.json().id)!;
    expect(partial).toMatchObject({ status: 'needs_review', words: null });
    const [stored] = await db.select().from(s.recordings).where(eq(s.recordings.id, partial.id));
    expect(stored!.transcript).toBeTruthy(); // kept for the reviewer while queued
    const [okRow] = await db.select().from(s.recordings).where(eq(s.recordings.id, ok));
    expect(okRow!.transcript).toBeNull();
    expect(okRow!.score).toBe(1);
    expect(asr.calls).toBe(4);
  });

  it('without ASR_URL shared recordings wait for a reviewer; failures retry, then the sweeper sends them to review', async () => {
    const u = await makeUser({ member: true });
    app.ctx.asr = null;
    const r = await upload(u.token, meta('exact_recitation'));
    await rec.drain(app.ctx);
    expect((await rec.listMine(app.ctx, u.id)).items[0]!.status).toBe('needs_review');
    app.ctx.asr = asr;
    const r2 = await upload(u.token, meta('exact_recitation'));
    await rec.drain(app.ctx); // first attempt fails (nothing queued) → retry scheduled, cancelled by drain
    const [row] = await db.select({ attempts: s.recordings.asrAttempts, status: s.recordings.status }).from(s.recordings).where(eq(s.recordings.id, r2.json().id));
    expect(row).toEqual({ attempts: 1, status: 'processing' });
    now = new Date(now.getTime() + 11 * 60_000);
    await rec.sweep(app.ctx); // attempt 2 fails
    now = new Date(now.getTime() + 11 * 60_000);
    const out = await rec.sweep(app.ctx); // attempt 3 fails → needs_review
    expect(out.toReview).toBe(1);
    const [after] = await db.select({ status: s.recordings.status }).from(s.recordings).where(eq(s.recordings.id, r2.json().id));
    expect(after!.status).toBe('needs_review');
    expect(r.statusCode).toBe(202);
  });

  it('limits: 3 per profile, 10 uploads/verifications per Cairo day', async () => {
    const u = await makeUser();
    for (let i = 0; i < 3; i++) expect((await upload(u.token, { surah: 112, fromAyah: 1, toAyah: 1, durationMs: 3000 })).statusCode).toBe(202);
    expect((await upload(u.token, { surah: 112, fromAyah: 1, toAyah: 1, durationMs: 3000 })).json().error.code).toBe('recordings_limit');
    const list = (await app.inject({ method: 'GET', url: '/v1/me/recordings', headers: auth(u.token) })).json();
    expect(list.items.map((x: { position: number }) => x.position)).toEqual([1, 2, 3]);
    expect(list.leftToday).toBe(7);
    await db.update(s.recordingDaily).set({ count: 10 }).where(eq(s.recordingDaily.userId, u.id));
    await app.inject({ method: 'DELETE', url: `/v1/me/recordings/${list.items[0].id}`, headers: auth(u.token) });
    const r = await upload(u.token, { surah: 112, fromAyah: 1, toAyah: 1, durationMs: 3000 });
    expect(r.statusCode).toBe(429);
    expect(r.json().error.code).toBe('recording_daily_limit');
  });

  it('patch: private → members verifies; back to private keeps approved; reorder; rejected cannot be shared', async () => {
    const u = await makeUser({ member: true });
    const a = (await upload(u.token, { surah: 1, fromAyah: 1, toAyah: 4, durationMs: 8000 })).json();
    const b = (await upload(u.token, { surah: 112, fromAyah: 1, toAyah: 4, durationMs: 8000 })).json();
    asr.answer('exact_recitation');
    const shared = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${a.id}`, headers: auth(u.token), payload: { visibility: 'public' } });
    expect(shared.json()).toMatchObject({ status: 'processing', visibility: 'public' });
    await rec.drain(app.ctx);
    const back = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${a.id}`, headers: auth(u.token), payload: { visibility: 'private', commentsOn: false } });
    expect(back.json()).toMatchObject({ status: 'approved', visibility: 'private', commentsOn: false });
    const again = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${a.id}`, headers: auth(u.token), payload: { visibility: 'members' } });
    expect(again.json().status).toBe('approved');
    expect(asr.calls).toBe(1); // no second check
    const moved = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${b.id}`, headers: auth(u.token), payload: { position: 1 } });
    expect(moved.json().position).toBe(1);
    asr.answer('wrong_verses');
    await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${b.id}`, headers: auth(u.token), payload: { visibility: 'members' } });
    await rec.drain(app.ctx);
    await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${b.id}`, headers: auth(u.token), payload: { visibility: 'private' } });
    const refused = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${b.id}`, headers: auth(u.token), payload: { visibility: 'members' } });
    expect(refused.json().error.code).toBe('recording_not_public');
    // A pending check is abandoned when switched back to private.
    const c = (await upload(u.token, { surah: 112, fromAyah: 1, toAyah: 2, durationMs: 4000 })).json();
    app.ctx.asr = null;
    await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${c.id}`, headers: auth(u.token), payload: { visibility: 'members' } });
    await rec.drain(app.ctx);
    const priv = await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${c.id}`, headers: auth(u.token), payload: { visibility: 'private' } });
    expect(priv.json().status).toBe('private_ready');
  });

  it('members: approved shared recordings, blocks both ways, owner gates', async () => {
    const owner = await makeUser({ member: true });
    const viewer = await makeUser();
    const id = await approvedRecording(owner);
    const view = await app.inject({ method: 'GET', url: `/v1/community/members/${owner.handle}/recordings`, headers: auth(viewer.token) });
    expect(view.statusCode).toBe(200);
    expect(view.json()).toMatchObject({ owner: { handle: owner.handle, points: null, rank: null, me: false }, items: [{ id, visibility: 'members', mine: false }] });
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(200);
    await db.insert(s.communityBlocks).values({ userId: owner.id, blockedUserId: viewer.id });
    expect((await app.inject({ method: 'GET', url: `/v1/community/members/${owner.handle}/recordings`, headers: auth(viewer.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(404);
    await db.delete(s.communityBlocks);
    // The owner leaves the community: hidden from members.
    await db.update(s.consents).set({ granted: false }).where(eq(s.consents.userId, owner.id));
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(404);
    await db.update(s.consents).set({ granted: true }).where(eq(s.consents.userId, owner.id));
  });

  it('guests (a token minted without signing in) cannot list, hear or read the comments of members recordings', async () => {
    const owner = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const guest = await makeUser({ guest: true });
    for (const url of [`/v1/community/members/${owner.handle}/recordings`, `/v1/recordings/${id}/audio`, `/v1/recordings/${id}/comments`]) {
      const r = await app.inject({ method: 'GET', url, headers: auth(guest.token) });
      expect(r.statusCode, url).toBe(403);
      expect(r.json().error.code, url).toBe('account_required');
    }
    // An inactive account neither.
    const gone = await makeUser();
    await db.update(s.users).set({ status: 'suspended' }).where(eq(s.users.id, gone.id));
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(gone.token) })).statusCode).toBe(403);
  });

  it('reactions: idempotent, changeable, removable; need the community opt-in; blocked → blocked', async () => {
    const owner = await makeUser({ member: true });
    const fan = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const put = (kind: string, t = fan.token) => app.inject({ method: 'PUT', url: `/v1/recordings/${id}/reaction`, headers: auth(t), payload: { kind } });
    expect((await put('mashallah')).json()).toEqual({ reactions: { mashallah: 1, barakallah: 0, ahsant: 0 }, myReaction: 'mashallah' });
    expect((await put('mashallah')).json().reactions.mashallah).toBe(1);
    expect((await put('ahsant')).json()).toEqual({ reactions: { mashallah: 0, barakallah: 0, ahsant: 1 }, myReaction: 'ahsant' });
    const del = await app.inject({ method: 'DELETE', url: `/v1/recordings/${id}/reaction`, headers: auth(fan.token) });
    expect(del.json()).toEqual({ reactions: { mashallah: 0, barakallah: 0, ahsant: 0 }, myReaction: null });
    expect((await app.inject({ method: 'DELETE', url: `/v1/recordings/${id}/reaction`, headers: auth(fan.token) })).statusCode).toBe(200);
    const listener = await makeUser();
    expect((await put('mashallah', listener.token)).json().error.code).toBe('attestation_required');
    await db.insert(s.communityBlocks).values({ userId: fan.id, blockedUserId: owner.id });
    expect((await put('mashallah')).json().error.code).toBe('blocked');
    await db.delete(s.communityBlocks);
    await put('barakallah');
    expect((await rec.listMine(app.ctx, owner.id)).items[0]!.reactions.barakallah).toBe(1);
    // Others react — the owner's own reaction is refused and never counted.
    const self = await put('mashallah', owner.token);
    expect(self.statusCode).toBe(403);
    expect(self.json().error.code).toBe('own_recording');
    expect((await rec.listMine(app.ctx, owner.id)).items[0]!.reactions).toEqual({ mashallah: 0, barakallah: 1, ahsant: 0 });
  });

  it('comments: filter, mentions, rate limit, comments off, pagination, owner/author delete, 3 reports hide', async () => {
    const owner = await makeUser({ member: true });
    const fan = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const post = (text: string, t = fan.token) => app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments`, headers: auth(t), payload: { text } });
    const first = await post('ما شاء الله، تلاوة خاشعة');
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({ text: 'ما شاء الله، تلاوة خاشعة', mine: true, canDelete: true, author: { handle: fan.handle } });
    for (const [t, problem] of [
      ['يا كلب', 'blocked_word'],
      ['visit spam.com', 'link'],
      ['01001234567', 'phone'],
      ['ب', 'too_short'],
      [`hi @nobody_here`, 'mention'],
    ]) {
      const r = await post(t!);
      expect(r.json().error, t).toMatchObject({ code: 'comment_rejected', details: { problem } });
    }
    expect((await post(`well done @${owner.handle}`)).statusCode).toBe(201);
    for (let i = 0; i < 3; i++) expect((await post(`جزاك الله خيرا ${i}`)).statusCode).toBe(201);
    const limited = await post('بارك الله فيك');
    expect(limited.statusCode).toBe(429);
    expect(limited.json().error.code).toBe('comment_rate_limited');
    now = new Date(now.getTime() + 61_000);
    // Pagination: 5 comments, newest first, 20 per page → one page here; cursor round-trip on a page of 2 by count.
    const page = (await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments`, headers: auth(owner.token) })).json();
    expect(page.items).toHaveLength(5);
    expect(page.items[0].canDelete).toBe(true); // the owner may delete any
    expect(page.items[0].mine).toBe(false);
    expect(page.nextCursor).toBeNull();
    // Owner deletes one, the author deletes another.
    expect((await app.inject({ method: 'DELETE', url: `/v1/recordings/${id}/comments/${page.items[0].id}`, headers: auth(owner.token) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'DELETE', url: `/v1/recordings/${id}/comments/${page.items[1].id}`, headers: auth(fan.token) })).statusCode).toBe(204);
    const stranger = await makeUser({ member: true });
    expect((await app.inject({ method: 'DELETE', url: `/v1/recordings/${id}/comments/${page.items[2].id}`, headers: auth(stranger.token) })).statusCode).toBe(404);
    const [wiped] = await db.select().from(s.recordingComments).where(eq(s.recordingComments.id, page.items[0].id));
    expect(wiped).toMatchObject({ status: 'removed', text: '' });
    // 3 distinct reports hide a comment.
    const target = page.items[2].id;
    for (let i = 0; i < 3; i++) {
      const r = await makeUser({ member: true });
      const rep = await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments/${target}/report`, headers: auth(r.token), payload: { reason: 'inappropriate' } });
      expect(rep.statusCode).toBe(204);
      if (i === 0) await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments/${target}/report`, headers: auth(r.token), payload: { reason: 'spam' } });
    }
    const [hidden] = await db.select({ status: s.recordingComments.status }).from(s.recordingComments).where(eq(s.recordingComments.id, target));
    expect(hidden!.status).toBe('hidden');
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments`, headers: auth(owner.token) })).json().items).toHaveLength(2);
    // Comments off.
    await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${id}`, headers: auth(owner.token), payload: { commentsOn: false } });
    expect((await post('جميل جدا')).json().error.code).toBe('comments_off');
    const off = (await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments`, headers: auth(fan.token) })).json();
    expect(off.commentsOn).toBe(false);
  });

  it('comments of an author who left the community, was banned or lost the attestation are hidden (and not counted)', async () => {
    const owner = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const authors = [await makeUser({ member: true }), await makeUser({ member: true }), await makeUser({ member: true })];
    for (const a of authors) expect((await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments`, headers: auth(a.token), payload: { text: 'ما شاء الله' } })).statusCode).toBe(201);
    const list = async () => (await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments`, headers: auth(owner.token) })).json().items.map((c: { author: { handle: string } }) => c.author.handle);
    expect((await list()).sort()).toEqual(authors.map((a) => a.handle).sort());
    // Left the community (consent withdrawn), banned, attestation gone.
    await db.update(s.consents).set({ granted: false }).where(eq(s.consents.userId, authors[0]!.id));
    await db.insert(s.communityMembers).values({ userId: authors[1]!.id, bannedAt: now });
    await db.update(s.users).set({ adultAttestedAt: null }).where(eq(s.users.id, authors[2]!.id));
    expect(await list()).toEqual([]);
    expect((await rec.listMine(app.ctx, owner.id)).items[0]!.commentCount).toBe(0);
    const view = (await app.inject({ method: 'GET', url: `/v1/community/members/${owner.handle}/recordings`, headers: auth(owner.token) })).json();
    expect(view.items[0].commentCount).toBe(0);
  });

  it('comment rate limit holds under a burst of parallel posts', async () => {
    const owner = await makeUser({ member: true });
    const fan = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const res = await Promise.all(
      Array.from({ length: 12 }, (_, i) =>
        app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments`, headers: auth(fan.token), payload: { text: `جزاك الله خيرا ${i}` } }),
      ),
    );
    expect(res.filter((r) => r.statusCode === 201)).toHaveLength(5);
    expect(res.filter((r) => r.statusCode === 429)).toHaveLength(7);
    const [{ n }] = (await db.execute<{ n: number }>(sql`select count(*)::int as n from recording_comments where user_id = ${fan.id}`)).rows as [{ n: number }];
    expect(n).toBe(5);
  });

  it('comment pagination with a cursor', async () => {
    const owner = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    for (let i = 0; i < 22; i++) {
      await db.insert(s.recordingComments).values({ recordingId: id, userId: owner.id, text: `تعليق ${i}`, createdAt: new Date(now.getTime() - i * 1000) });
    }
    const p1 = (await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments`, headers: auth(owner.token) })).json();
    expect(p1.items).toHaveLength(20);
    expect(p1.items[0].text).toBe('تعليق 0');
    const p2 = (await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments?cursor=${p1.nextCursor}`, headers: auth(owner.token) })).json();
    expect(p2.items.map((c: { text: string }) => c.text)).toEqual(['تعليق 20', 'تعليق 21']);
    expect(p2.nextCursor).toBeNull();
    // A malformed cursor id is a 400, never a Postgres cast error.
    for (const bad of ['-'.repeat(36), 'a'.repeat(36), 'zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz']) {
      const cursor = Buffer.from(`2026-01-01T00:00:00.000Z|${bad}`, 'utf8').toString('base64url');
      const r = await app.inject({ method: 'GET', url: `/v1/recordings/${id}/comments?cursor=${cursor}`, headers: auth(owner.token) });
      expect(r.statusCode, bad).toBe(400);
      expect(r.json().error.code).toBe('invalid_cursor');
    }
  });

  it('3 reports hold a recording out of every view; support dismisses or removes (audited); reviewer approves needs_review', async () => {
    const owner = await makeUser({ member: true, card: true });
    const viewer = await makeUser();
    const id = await approvedRecording(owner, 'public');
    for (let i = 0; i < 3; i++) {
      const r = await makeUser({ member: true });
      await app.inject({ method: 'POST', url: `/v1/recordings/${id}/report`, headers: auth(r.token), payload: { reason: 'not_recitation' } });
    }
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(404);
    const support = await adminToken('support');
    const reviewer = await adminToken('religious_reviewer');
    const marketing = await adminToken('marketing');
    expect((await app.inject({ method: 'GET', url: '/admin/recordings/queue', headers: auth(marketing.token) })).statusCode).toBe(403);
    const q = (await app.inject({ method: 'GET', url: '/admin/recordings/queue', headers: auth(support.token) })).json();
    const item = q.recordings.find((x: { id: string }) => x.id === id);
    expect(item).toMatchObject({ held: true, reports: 3, reasons: ['not_recitation'], status: 'approved', audioPath: `/admin/recordings/${id}/audio` });
    expect((await app.inject({ method: 'GET', url: item.audioPath, headers: auth(support.token) })).statusCode).toBe(200);
    // Roles per action.
    const decide = async (t: string, body: unknown, rid: string = id) =>
      app.inject({ method: 'POST', url: `/admin/recordings/${rid}/decision`, headers: auth(t), payload: body as Record<string, unknown> });
    expect((await decide(reviewer.token, { action: 'dismiss', reason: 'reports unfounded' })).statusCode).toBe(403);
    expect((await decide(support.token, { action: 'dismiss', reason: 'reports unfounded' })).statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(200);
    // Out of the queue → its audio is closed to admins.
    expect((await app.inject({ method: 'GET', url: item.audioPath, headers: auth(support.token) })).statusCode).toBe(404);
    // Report again → remove → restore.
    await db.insert(s.recordingReports).values({ target: 'recording', targetId: id, reporterId: viewer.id, reason: 'inappropriate' }).onConflictDoNothing();
    expect((await decide(support.token, { action: 'remove', reason: 'not a recitation' })).statusCode).toBe(204);
    expect((await rec.listMine(app.ctx, owner.id)).items.find((x) => x.id === id)).toMatchObject({ status: 'removed', rejectReason: 'removed_by_moderator' });
    expect((await decide(support.token, { action: 'restore', reason: 'removed by mistake' })).statusCode).toBe(204);
    const audits = await db.select({ action: s.auditLog.action }).from(s.auditLog).where(eq(s.auditLog.targetId, id));
    expect(audits.map((a) => a.action).sort()).toEqual(['recording.dismiss', 'recording.remove', 'recording.restore']);
    // A needs_review recording: the reviewer approves (support cannot).
    app.ctx.asr = null;
    const nr = (await upload(owner.token, meta('exact_recitation'))).json().id as string;
    await rec.drain(app.ctx);
    expect((await decide(support.token, { action: 'approve', reason: 'listened, matches' }, nr)).statusCode).toBe(403);
    expect((await decide(reviewer.token, { action: 'reject', reason: 'x' }, nr)).statusCode).toBe(400);
    expect((await decide(reviewer.token, { action: 'approve', reason: 'listened, matches' }, nr)).statusCode).toBe(204);
    const [approved] = await db.select({ status: s.recordings.status, transcript: s.recordings.transcript }).from(s.recordings).where(eq(s.recordings.id, nr));
    expect(approved).toEqual({ status: 'approved', transcript: null });
  });

  it('admin comment decisions: remove / restore / dismiss, audited', async () => {
    const owner = await makeUser({ member: true });
    const fan = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const c = (await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments`, headers: auth(fan.token), payload: { text: 'تعليق للاختبار' } })).json();
    await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments/${c.id}/report`, headers: auth(owner.token), payload: { reason: 'spam' } });
    const support = await adminToken('support');
    const reviewer = await adminToken('religious_reviewer');
    const q = (await app.inject({ method: 'GET', url: '/admin/recordings/queue', headers: auth(reviewer.token) })).json();
    expect(q.comments.find((x: { id: string }) => x.id === c.id)).toMatchObject({ status: 'visible', reports: 1, text: 'تعليق للاختبار', authorHandle: fan.handle });
    const decide = (t: string, action: string) => app.inject({ method: 'POST', url: `/admin/recordings/comments/${c.id}/decision`, headers: auth(t), payload: { action, reason: 'moderation test' } });
    expect((await decide(reviewer.token, 'remove')).statusCode).toBe(403);
    expect((await decide(support.token, 'remove')).statusCode).toBe(204);
    expect((await decide(support.token, 'restore')).statusCode).toBe(204);
    expect((await decide(support.token, 'dismiss')).statusCode).toBe(204);
    const audits = await db.select({ action: s.auditLog.action }).from(s.auditLog).where(eq(s.auditLog.targetId, c.id));
    expect(audits.map((a) => a.action).sort()).toEqual(['recording_comment.dismiss', 'recording_comment.remove', 'recording_comment.restore']);
  });

  it('web card: only public + approved recordings, with a same-origin player and audio', async () => {
    const owner = await makeUser({ member: true, card: true });
    const pub = await approvedRecording(owner, 'public');
    const membersOnly = await approvedRecording(owner, 'members');
    const html = (await app.inject({ method: 'GET', url: `/u/${owner.handle}` })).body;
    expect(html).toContain('تلاواتي');
    // A same-origin path (CSP media-src 'self', CORP same-origin), never an absolute URL on another host.
    expect(html).toContain(`src="/u/${owner.handle}/r/${pub}.m4a"`);
    expect(html).not.toContain(`https://id.test/u/${owner.handle}/r/`);
    expect(html).not.toContain(membersOnly);
    expect(html).toContain('سورة الفاتحة · الآيات 1–4');
    expect(html).toContain('<script src="/u/assets/recitations.js" defer></script>');
    const page = await app.inject({ method: 'GET', url: `/u/${owner.handle}` });
    expect(String(page.headers['content-security-policy'])).toContain("default-src 'self'");
    expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${pub}.m4a` })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${membersOnly}.m4a` })).statusCode).toBe(404);
    const js = await app.inject({ method: 'GET', url: '/u/assets/recitations.js' });
    expect(js.headers['content-type']).toContain('text/javascript');
    // The cards kill switch takes the recordings' audio down with `/u/:handle`.
    await db.update(s.appConfig).set({ value: { recordings: true, publicCards: false } }).where(eq(s.appConfig.key, 'features'));
    await app.ctx.cache.bumpNamespace('config');
    try {
      expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}` })).statusCode).toBe(404);
      expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${pub}.m4a` })).statusCode).toBe(404);
    } finally {
      await db.update(s.appConfig).set({ value: { recordings: true } }).where(eq(s.appConfig.key, 'features'));
      await app.ctx.cache.bumpNamespace('config');
    }
    expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${pub}.m4a` })).statusCode).toBe(200);
    // Unpublished card → nothing.
    await db.update(s.publicProfiles).set({ published: false }).where(eq(s.publicProfiles.userId, owner.id));
    expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${pub}.m4a` })).statusCode).toBe(404);
  });

  it('feature flag off: no uploads, no member or web views', async () => {
    const owner = await makeUser({ member: true, card: true });
    const id = await approvedRecording(owner, 'public');
    await db.update(s.appConfig).set({ value: { recordings: false } }).where(eq(s.appConfig.key, 'features'));
    await app.ctx.cache.bumpNamespace('config');
    try {
      expect((await upload(owner.token, { surah: 112, fromAyah: 1, toAyah: 1, durationMs: 2000 })).json().error.code).toBe('feature_off');
      expect((await app.inject({ method: 'GET', url: `/v1/recordings/${id}/audio`, headers: auth(owner.token) })).statusCode).toBe(404);
      expect((await app.inject({ method: 'GET', url: `/u/${owner.handle}/r/${id}.m4a` })).statusCode).toBe(404);
      // The owner still sees and can delete their own.
      expect((await app.inject({ method: 'GET', url: '/v1/me/recordings', headers: auth(owner.token) })).json().items).toHaveLength(1);
    } finally {
      await db.update(s.appConfig).set({ value: { recordings: true } }).where(eq(s.appConfig.key, 'features'));
      await app.ctx.cache.bumpNamespace('config');
    }
  });

  it('export includes the recordings with audio; erasure deletes recordings, reactions, comments and reports', async () => {
    const owner = await makeUser({ member: true });
    const fan = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    const theirs = await approvedRecording(fan);
    await app.inject({ method: 'PUT', url: `/v1/recordings/${theirs}/reaction`, headers: auth(owner.token), payload: { kind: 'ahsant' } });
    await app.inject({ method: 'POST', url: `/v1/recordings/${theirs}/comments`, headers: auth(owner.token), payload: { text: 'أحسنت يا أخي' } });
    await app.inject({ method: 'POST', url: `/v1/recordings/${theirs}/report`, headers: auth(owner.token), payload: { reason: 'other' } });
    await app.inject({ method: 'POST', url: `/v1/recordings/${id}/comments`, headers: auth(fan.token), payload: { text: 'ما شاء الله' } });
    const exp = (await app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(owner.token) })).json();
    expect(exp.recitations.recordings).toHaveLength(1);
    expect(Buffer.from(exp.recitations.recordings[0].audioBase64, 'base64').subarray(4, 8).toString('latin1')).toBe('ftyp');
    expect(exp.recitations.reactions).toEqual([expect.objectContaining({ recordingId: theirs, kind: 'ahsant' })]);
    expect(exp.recitations.comments).toHaveLength(1);
    expect(exp.recitations.reports).toHaveLength(1);
    expect((await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(owner.token) })).statusCode).toBe(202);
    const count = async (table: string) => (await db.execute<{ n: number }>(sql`select count(*)::int as n from ${sql.raw(table)} where user_id = ${owner.id}`)).rows[0]!.n;
    expect(await count('recordings')).toBe(0);
    expect(await count('recording_comments')).toBe(0);
    expect(await count('recording_reactions')).toBe(0);
    expect((await db.select().from(s.recordingReports).where(eq(s.recordingReports.reporterId, owner.id))).length).toBe(0);
    // Comments others left on the erased recording went with it.
    expect((await db.select().from(s.recordingComments).where(and(eq(s.recordingComments.userId, fan.id), eq(s.recordingComments.recordingId, id)))).length).toBe(0);
  });

  it('sweeper deletes recordings removed more than 7 days ago', async () => {
    const owner = await makeUser({ member: true });
    const id = await approvedRecording(owner);
    await db.update(s.recordings).set({ status: 'removed', removedAt: new Date(now.getTime() - 8 * 86_400_000) }).where(eq(s.recordings.id, id));
    const out = await rec.sweep(app.ctx);
    expect(out.purged).toBeGreaterThanOrEqual(1);
    expect((await db.select().from(s.recordings).where(eq(s.recordings.id, id))).length).toBe(0);
  });
  it('real community paths: join (attest + level board) to share, block via the API, leave hides, the job sweeps', async () => {
    await db.update(s.appConfig).set({ value: { recordings: true, leaderboard: true } }).where(eq(s.appConfig.key, 'features'));
    await app.ctx.cache.bumpNamespace('config');
    try {
      const owner = await makeUser();
      await db.update(s.users).set({ displayName: 'Omar Farouk' }).where(eq(s.users.id, owner.id));
      const viewer = await makeUser();
      // Not in the community yet: sharing refused with the stable codes.
      expect((await upload(owner.token, meta('exact_recitation'))).json().error.code).toBe('attestation_required');
      const join = await app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(owner.token), payload: { attestAdult: true, leaderboard: true, source: 'settings' } });
      expect(join.statusCode).toBe(200);
      const [card] = await db.select({ handle: s.publicProfiles.handle }).from(s.publicProfiles).where(eq(s.publicProfiles.userId, owner.id));
      expect(card!.handle).toMatch(/^omar-\d{4}$/); // the community's competitor handle, not a recordings one
      asr.answer('exact_recitation');
      const up = await upload(owner.token, meta('exact_recitation'));
      expect(up.statusCode).toBe(202);
      await rec.drain(app.ctx);
      const view = await app.inject({ method: 'GET', url: `/v1/community/members/${card!.handle}/recordings`, headers: auth(viewer.token) });
      expect(view.statusCode).toBe(200);
      // The owner is the community's public competitor projection (name, level ring, no points/rank).
      expect(view.json().owner).toEqual({ handle: card!.handle, name: 'Omar Farouk', avatar: { kind: 'initial' }, level: { level: 1, progress: 0 }, points: null, rank: null, me: false });
      // A block through the community API hides both ways.
      expect((await app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(owner.token), payload: { handle: card!.handle } })).statusCode).toBe(400); // not self
      const viewerJoin = await app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(viewer.token), payload: { attestAdult: true, leaderboard: true, displayName: 'Viewer Two', source: 'settings' } });
      expect(viewerJoin.statusCode).toBe(200);
      const [vcard] = await db.select({ handle: s.publicProfiles.handle }).from(s.publicProfiles).where(eq(s.publicProfiles.userId, viewer.id));
      expect((await app.inject({ method: 'POST', url: '/v1/community/blocks', headers: auth(owner.token), payload: { handle: vcard!.handle } })).statusCode).toBe(204);
      expect((await app.inject({ method: 'GET', url: `/v1/community/members/${card!.handle}/recordings`, headers: auth(viewer.token) })).statusCode).toBe(404);
      expect((await app.inject({ method: 'PUT', url: `/v1/recordings/${up.json().id}/reaction`, headers: auth(viewer.token), payload: { kind: 'ahsant' } })).json().error.code).toBe('blocked');
      expect((await app.inject({ method: 'DELETE', url: `/v1/community/blocks/${vcard!.handle}`, headers: auth(owner.token) })).statusCode).toBe(204);
      expect((await app.inject({ method: 'PUT', url: `/v1/recordings/${up.json().id}/reaction`, headers: auth(viewer.token), payload: { kind: 'ahsant' } })).statusCode).toBe(200);
      // A public recording on a published card, live on the web while in the community.
      await db.update(s.publicProfiles).set({ published: true }).where(eq(s.publicProfiles.userId, owner.id));
      const pubRec = up.json().id as string;
      await app.inject({ method: 'PATCH', url: `/v1/me/recordings/${pubRec}`, headers: auth(owner.token), payload: { visibility: 'public' } });
      expect((await app.inject({ method: 'GET', url: `/u/${card!.handle}/r/${pubRec}.m4a` })).statusCode).toBe(200);
      // Leaving the community (derived consent off) hides the recordings from members and refuses sharing.
      const leave = await app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(owner.token), payload: { leaderboard: false, source: 'settings' } });
      expect(leave.statusCode).toBe(200);
      expect((await app.inject({ method: 'GET', url: `/v1/recordings/${up.json().id}/audio`, headers: auth(viewer.token) })).statusCode).toBe(404);
      expect((await upload(owner.token, meta('exact_recitation'))).json().error.code).toBe('community_required');
      // …and from the open web: the card section and its audio go too.
      expect((await app.inject({ method: 'GET', url: `/u/${card!.handle}/r/${pubRec}.m4a` })).statusCode).toBe(404);
      expect(await rec.forCard(app.ctx, card!.handle)).toEqual([]);
      // The hourly community job carries the recordings sweep (stuck AI checks → retried).
      const stuck = await upload(viewer.token, meta('exact_recitation'));
      await rec.drain(app.ctx); // attempt 1 fails (nothing queued)
      now = new Date(now.getTime() + 11 * 60_000);
      asr.answer('exact_recitation');
      const res = await runCommunity({ env: app.ctx.env, db, cache: app.ctx.cache, now: () => now, asr });
      expect(res.recordings.retried).toBe(0);
      const [after] = await db.select({ status: s.recordings.status }).from(s.recordings).where(eq(s.recordings.id, stuck.json().id));
      expect(after!.status).toBe('approved');
    } finally {
      await db.update(s.appConfig).set({ value: { recordings: true } }).where(eq(s.appConfig.key, 'features'));
      await app.ctx.cache.bumpNamespace('config');
    }
  });
});
