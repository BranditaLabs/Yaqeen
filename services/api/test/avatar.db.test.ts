/**
 * Profile photos against Postgres (design §5, §13): upload codes, EXIF stripped, own/public/admin
 * routes with per-size ETags, the public visibility rule (attested + visible), support hide/restore
 * (never a photo the user removed), the 10-per-hour DB limit, export, erasure.
 * Skipped without TEST_DATABASE_URL.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { sql } from 'drizzle-orm';
import { type Harness, TEST_DB_URL, auth, makeAdmin, makeUser, optIn, setFlags, setup } from './community.helpers.js';

const fixture = (name: string) => readFileSync(fileURLToPath(new URL(`./fixtures/avatar/${name}`, import.meta.url)));

describe.skipIf(!TEST_DB_URL)('avatar photos (Postgres)', () => {
  let h: Harness;
  beforeAll(async () => {
    h = await setup('2026-11-11T08:00:00Z');
    await setFlags(h, { leagues: true, tournaments: true, leaderboard: true });
  });
  afterAll(async () => h?.close());

  const upload = (token: string, body: Buffer, type = 'image/jpeg') =>
    h.app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { ...auth(token), 'content-type': type }, payload: body });
  const publicUrl = (id: string, size = 256) => `/v1/public/avatars/${id}/${size}.webp`;

  let u: { id: string; token: string };
  let photoId: string;

  it('re-encodes an upload (EXIF/GPS stripped) and serves the owner their active photo with per-size ETags', async () => {
    u = await makeUser(h, 'Umar');
    const res = await upload(u.token, fixture('gps.jpg'));
    expect(res.statusCode).toBe(200);
    const avatar = res.json();
    expect(avatar).toMatchObject({ kind: 'photo', url: '/v1/me/avatar/photo/256', smallUrl: '/v1/me/avatar/photo/96' });
    photoId = avatar.id;

    const large = await h.app.inject({ method: 'GET', url: '/v1/me/avatar/photo/256', headers: auth(u.token) });
    const small = await h.app.inject({ method: 'GET', url: '/v1/me/avatar/photo/96', headers: auth(u.token) });
    expect(large.headers['content-type']).toBe('image/webp');
    expect(large.headers['cache-control']).toBe('private, no-cache');
    const ml = await sharp(large.rawPayload).metadata();
    expect([ml.width, ml.height, ml.exif]).toEqual([256, 256, undefined]);
    expect((await sharp(small.rawPayload).metadata()).width).toBe(96);
    expect(large.rawPayload.toString('latin1')).not.toContain('YaqeenTestCam');
    expect(large.headers.etag).not.toBe(small.headers.etag);
    const again = await h.app.inject({ method: 'GET', url: '/v1/me/avatar/photo/256', headers: { ...auth(u.token), 'if-none-match': String(large.headers.etag) } });
    expect(again.statusCode).toBe(304);
    const row = await h.db.execute<{ sha_large: string }>(sql`select sha_large from avatar_photos where id = ${photoId}`);
    expect(large.headers.etag).toBe(`"${row.rows[0]!.sha_large}"`);

    const me = (await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(u.token) })).json();
    expect(me).toMatchObject({ avatar: { kind: 'photo', id: photoId }, photoHidden: false, photoPublic: false });
  });

  it('upload codes: 415 wrong magic bytes, 422 unreadable or too small', async () => {
    const png = await upload(u.token, fixture('photo.png'), 'image/jpeg');
    expect([png.statusCode, png.json().error.code]).toEqual([415, 'photo_type']);
    const tiny = await upload(u.token, fixture('tiny.jpg'));
    expect([tiny.statusCode, tiny.json().error.code]).toEqual([422, 'photo_unreadable']);
    const broken = await upload(u.token, Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(500, 7)]));
    expect([broken.statusCode, broken.json().error.code]).toEqual([422, 'photo_unreadable']);
  });

  it('public only when attested and visible; the projection falls back to the preset otherwise', async () => {
    expect((await h.app.inject({ method: 'GET', url: publicUrl(photoId) })).statusCode).toBe(404); // no card, no competitions

    // Visible (a published card) but not attested: still private; the card shows the preset.
    const w = await makeUser(h, 'Wafaa');
    await h.app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: auth(w.token), payload: { avatar: { kind: 'preset', id: 'f03' } } });
    const wp = (await upload(w.token, fixture('photo.png'), 'image/png')).json();
    await h.app.inject({
      method: 'PUT',
      url: '/v1/me/public-profile',
      headers: auth(w.token),
      payload: { published: true, handle: 'wafaa', displayName: 'Wafaa', bio: '', links: [], show: { level: true, streak: false, challengeDay: false, badges: false, memberSince: false }, theme: 'sky' },
    });
    expect((await h.app.inject({ method: 'GET', url: publicUrl(wp.id) })).statusCode).toBe(404);
    expect((await h.app.inject({ method: 'GET', url: '/v1/public/profiles/wafaa' })).json().avatar).toEqual({ kind: 'preset', id: 'f03' });
    const page = await h.app.inject({ method: 'GET', url: '/u/wafaa' });
    expect(page.body).toContain('/u/assets/avatars/f03.webp');

    await h.app.inject({ method: 'POST', url: '/v1/me/attestation', headers: auth(w.token), payload: { attestAdult: true } });
    const pub = await h.app.inject({ method: 'GET', url: publicUrl(wp.id) });
    expect(pub.statusCode).toBe(200);
    expect(pub.headers['cache-control']).toBe('public, max-age=300, stale-while-revalidate=60');
    const card = (await h.app.inject({ method: 'GET', url: '/v1/public/profiles/wafaa' })).json();
    expect(card.avatar).toEqual({ kind: 'photo', id: wp.id, url: `https://id.test${publicUrl(wp.id)}`, smallUrl: `https://id.test${publicUrl(wp.id, 96)}` });
    const audit = await h.db.execute(sql`select 1 from audit_log where actor_user_id = ${w.id} and action = 'user.attest_adult'`);
    expect(audit.rows).toHaveLength(1);

    // Umar joins the league (attesting): his photo becomes public with the same ETag as his own.
    await optIn(h, u.token, { leagues: true });
    await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(u.token) }); // placed this week
    const res = await h.app.inject({ method: 'GET', url: publicUrl(photoId) });
    expect(res.statusCode).toBe(200);
    const own = await h.app.inject({ method: 'GET', url: '/v1/me/avatar/photo/256', headers: auth(u.token) });
    expect(res.headers.etag).toBe(own.headers.etag);
    const v = await makeUser(h, 'Vera');
    await optIn(h, v.token, { leagues: true });
    const rows = (await h.app.inject({ method: 'GET', url: '/v1/leagues/current', headers: auth(v.token) })).json().rows;
    const umar = rows.find((r: { name: string }) => r.name === 'Umar');
    expect(umar.avatar).toEqual({ kind: 'photo', id: photoId, url: `https://id.test${publicUrl(photoId)}`, smallUrl: `https://id.test${publicUrl(photoId, 96)}` });
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(u.token) })).json().photoPublic).toBe(true);
  });

  it('support hides and restores a photo (audited, uploads locked); never restores one the user removed', async () => {
    const sup = await makeAdmin(h, 'support');
    const mk = await makeAdmin(h, 'marketing');
    const hide = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${u.id}/hide-photo`, headers: auth(sup.token), payload: { reason: 'inappropriate photo' } });
    expect(hide.json()).toMatchObject({ photoHidden: true, photoLocked: true, avatar: { kind: 'initial' } });
    expect(hide.json().photos[0]).toMatchObject({ id: photoId, status: 'removed', removedBySupport: true });
    expect((await h.app.inject({ method: 'GET', url: publicUrl(photoId) })).statusCode).toBe(404);
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/avatar/photo/256', headers: auth(u.token) })).statusCode).toBe(404);
    expect((await h.app.inject({ method: 'GET', url: '/v1/me/profile', headers: auth(u.token) })).json()).toMatchObject({ photoHidden: true, avatar: { kind: 'initial' } });
    const locked = await upload(u.token, fixture('gps.jpg'));
    expect([locked.statusCode, locked.json().error.code]).toEqual([409, 'photo_locked']);

    const adminPhoto = await h.app.inject({ method: 'GET', url: `/admin/competitions/competitors/${u.id}/photos/${photoId}/256`, headers: auth(sup.token) });
    expect(adminPhoto.statusCode).toBe(200);
    expect(adminPhoto.headers['cache-control']).toBe('private, no-store');
    expect((await h.app.inject({ method: 'GET', url: `/admin/competitions/competitors/${u.id}/photos/${photoId}/256`, headers: auth(mk.token) })).statusCode).toBe(403);
    // Past the 7-day retention support can't see it either.
    h.setNow('2026-11-19T08:00:00Z');
    expect((await h.app.inject({ method: 'GET', url: `/admin/competitions/competitors/${u.id}/photos/${photoId}/256`, headers: auth(sup.token) })).statusCode).toBe(404);
    h.setNow('2026-11-11T09:00:00Z');

    const restore = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${u.id}/restore-photo`, headers: auth(sup.token), payload: { reason: 'appeal accepted' } });
    expect(restore.json()).toMatchObject({ photoHidden: false, avatar: { kind: 'photo', id: photoId } });
    expect((await h.app.inject({ method: 'GET', url: publicUrl(photoId) })).statusCode).toBe(200);
    const actions = await h.db.execute<{ action: string }>(sql`select action from audit_log where target_id = ${u.id} and admin_id is not null order by created_at`);
    expect(actions.rows.map((r) => r.action)).toEqual(['competitor.hide_photo', 'competitor.restore_photo']);

    // The user removes it themselves: support cannot bring it back.
    const del = await h.app.inject({ method: 'DELETE', url: '/v1/me/avatar/photo', headers: auth(u.token) });
    expect(del.json()).toEqual({ kind: 'initial' });
    const none = await h.app.inject({ method: 'POST', url: `/admin/competitions/competitors/${u.id}/restore-photo`, headers: auth(sup.token), payload: { reason: 'try again' } });
    expect([none.statusCode, none.json().error.code]).toEqual([409, 'nothing_to_restore']);
  });

  it('at most 10 uploads per rolling hour, counted in the database', async () => {
    const r = await makeUser(h, 'Rana');
    for (let i = 0; i < 10; i++) expect((await upload(r.token, fixture('photo.png'), 'image/png')).statusCode).toBe(200);
    const over = await upload(r.token, fixture('photo.png'), 'image/png');
    expect([over.statusCode, over.json().error.code]).toEqual([429, 'rate_limited']);
    const states = await h.db.execute<{ status: string; n: number }>(sql`select status, count(*)::int as n from avatar_photos where user_id = ${r.id} group by status order by status`);
    expect(states.rows).toEqual([{ status: 'active', n: 1 }, { status: 'replaced', n: 9 }]);

    // Export: the user gets the 256-px WebP; support gets metadata only.
    const mine = (await h.app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(r.token) })).json();
    expect(mine.avatar.photos).toHaveLength(10);
    expect(Buffer.from(mine.avatar.photoWebp256Base64, 'base64').subarray(8, 12).toString('latin1')).toBe('WEBP');
    const sup = await makeAdmin(h, 'support');
    const adminExport = (await h.app.inject({ method: 'GET', url: `/admin/users/${r.id}/export`, headers: auth(sup.token) })).json();
    expect(adminExport.avatar.photos).toHaveLength(10);
    expect(adminExport.avatar).not.toHaveProperty('photoWebp256Base64');

    // Erasure removes the photo at once (not as a support removal).
    await h.app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(r.token) });
    const after = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from avatar_photos where user_id = ${r.id} and status = 'active'`);
    expect(after.rows[0]!.n).toBe(0);
    const removed = await h.db.execute<{ by: string | null }>(sql`select removed_by as by from avatar_photos where user_id = ${r.id} and status = 'removed'`);
    expect(removed.rows.every((x) => x.by === null)).toBe(true);
  });
});
