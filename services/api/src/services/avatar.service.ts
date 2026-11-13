/**
 * Profile photos (design §5): the server re-encodes every upload with sharp into 96/256-px WebP
 * (EXIF and every other metadata dropped — `withMetadata()` is never called), stores the bytes in
 * Postgres `bytea` (no paid service) and serves them three ways:
 *   - the owner: their active photo only (authed paths in `MeProfile`);
 *   - the public: only when the photo is active, the owner active, attested 18+ and actually visible;
 *   - support: any status within the 7-day retention (admin route, never cached).
 * Upload limits are enforced in the database (10 per rolling hour), so they hold across replicas.
 */
import { createHash } from 'node:crypto';
import { and, desc, eq, sql } from 'drizzle-orm';
import sharp from 'sharp';
import { AVATAR_PHOTO, type Avatar, type SetAvatar } from '@yaqeen/contracts';
import { avatarPhotos, users } from '../db/schema.js';
import { AppError, conflict, forbidden } from '../lib/errors.js';
import { type CommunityCtx } from './community-settings.service.js';
import { type AvatarColumns, type DbOrTx, OWN_PHOTO, avatarOf, photoPublicSql } from './community.service.js';

/** Removed/replaced photos are kept this long (support review, restore), then purged daily. */
export const PHOTO_RETENTION_DAYS = 7;

export type PhotoSize = 96 | 256;
export type PhotoMime = (typeof AVATAR_PHOTO.mimes)[number];

/** Magic bytes must match the declared type. */
export function sniffMime(buf: Buffer): PhotoMime | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

const sha256 = (b: Buffer) => createHash('sha256').update(b).digest('hex');

/**
 * Decode → auto-orient → square crop on the most interesting region → WebP q80 at 256 and 96.
 * Throws `photo_unreadable` (422) for anything sharp can't decode or a picture under 128 px.
 */
export async function processPhoto(buf: Buffer): Promise<{ large: Buffer; small: Buffer }> {
  const input = () => sharp(buf, { limitInputPixels: 40_000_000, failOn: 'error' });
  try {
    const meta = await input().metadata();
    const w = meta.autoOrient?.width ?? meta.width ?? 0;
    const h = meta.autoOrient?.height ?? meta.height ?? 0;
    if (Math.min(w, h) < AVATAR_PHOTO.minPx) throw new AppError(422, 'photo_unreadable', `The photo must be at least ${AVATAR_PHOTO.minPx} px`);
    const encode = (px: number) =>
      input().rotate().resize(px, px, { fit: 'cover', position: 'attention' }).webp({ quality: 80 }).toBuffer();
    const [large, small] = await Promise.all([encode(256), encode(96)]);
    return { large, small };
  } catch (e) {
    if (e instanceof AppError) throw e;
    throw new AppError(422, 'photo_unreadable', 'The photo could not be read');
  }
}

/** The caller's own avatar (authed photo paths) from their user row. */
export async function ownAvatar(db: DbOrTx, uid: string): Promise<Avatar> {
  const r = await db.execute<AvatarColumns & { photo_active: boolean }>(sql`
    select u.avatar_kind, u.avatar_preset, u.avatar_photo_id, coalesce(ap.status = 'active', false) as photo_active
    from users u left join avatar_photos ap on ap.id = u.avatar_photo_id where u.id = ${uid}`);
  const row = r.rows[0];
  if (!row) return { kind: 'initial' };
  return avatarOf(row, row.photo_active, () => ({ ...OWN_PHOTO }));
}

async function bumpCaches(ctx: CommunityCtx) {
  await ctx.cache.bumpNamespace('community');
  await ctx.cache.bumpNamespace('profile');
}

/** PUT /v1/me/avatar/photo. */
export async function uploadPhoto(ctx: CommunityCtx, uid: string, isGuest: boolean, declared: string | undefined, body: unknown): Promise<Avatar> {
  if (isGuest) throw forbidden('account_required', 'Sign in to upload a photo');
  const mime = (declared ?? '').split(';')[0]!.trim().toLowerCase();
  if (!(AVATAR_PHOTO.mimes as readonly string[]).includes(mime) || !Buffer.isBuffer(body)) {
    throw new AppError(415, 'photo_type', 'Send a JPEG, PNG or WebP image');
  }
  const buf = body;
  if (buf.length > AVATAR_PHOTO.maxBytes) throw new AppError(413, 'photo_too_large', 'The photo is larger than 3 MB');
  if (sniffMime(buf) !== mime) throw new AppError(415, 'photo_type', 'The file is not the image type it claims to be');

  const now = ctx.now();
  const [u] = await ctx.db.select({ isGuest: users.isGuest, lockedAt: users.photoLockedAt }).from(users).where(eq(users.id, uid));
  if (!u || u.isGuest) throw forbidden('account_required', 'Sign in to upload a photo');
  if (u.lockedAt) throw conflict('photo_locked', 'Support removed your photo; choose a preset avatar');
  await assertUnderHourlyLimit(ctx.db, uid, now);

  const { large, small } = await processPhoto(buf);

  const id = await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select 1 from users where id = ${uid} for update`);
    const [fresh] = await tx.select({ lockedAt: users.photoLockedAt }).from(users).where(eq(users.id, uid));
    if (fresh?.lockedAt) throw conflict('photo_locked', 'Support removed your photo; choose a preset avatar');
    await assertUnderHourlyLimit(tx, uid, now);
    await tx
      .update(avatarPhotos)
      .set({ status: 'replaced', removedAt: now })
      .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')));
    const [row] = await tx
      .insert(avatarPhotos)
      .values({ userId: uid, shaSmall: sha256(small), shaLarge: sha256(large), small, large, bytes: small.length + large.length, createdAt: now })
      .returning({ id: avatarPhotos.id });
    await tx.update(users).set({ avatarKind: 'photo', avatarPhotoId: row!.id, updatedAt: now }).where(eq(users.id, uid));
    return row!.id;
  });
  await bumpCaches(ctx);
  return { kind: 'photo', id, ...OWN_PHOTO };
}

async function assertUnderHourlyLimit(db: DbOrTx, uid: string, now: Date) {
  const r = await db.execute<{ n: number }>(sql`
    select count(*)::int as n from avatar_photos where user_id = ${uid} and created_at > ${new Date(now.getTime() - 3_600_000)}`);
  if ((r.rows[0]?.n ?? 0) >= AVATAR_PHOTO.perHour) throw new AppError(429, 'rate_limited', 'Too many photos this hour');
}

/** DELETE /v1/me/avatar/photo → the preset if one is set, else the initial. */
export async function removeOwnPhoto(ctx: CommunityCtx, uid: string): Promise<Avatar> {
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    await tx
      .update(avatarPhotos)
      .set({ status: 'removed', removedAt: now, removedBy: null })
      .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')));
    await tx
      .update(users)
      .set({ avatarKind: sql`case when ${users.avatarPreset} is not null then 'preset' else 'initial' end`, avatarPhotoId: null, updatedAt: now })
      .where(eq(users.id, uid));
  });
  await bumpCaches(ctx);
  return ownAvatar(ctx.db, uid);
}

/** PATCH /v1/me/profile avatar: a preset or the initial (a photo goes through uploadPhoto). */
export async function setAvatar(tx: DbOrTx, uid: string, avatar: SetAvatar, now: Date): Promise<void> {
  // Choosing another avatar retires the photo so it can never be served again.
  await tx
    .update(avatarPhotos)
    .set({ status: 'replaced', removedAt: now })
    .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')));
  if (avatar.kind === 'preset') {
    await tx.update(users).set({ avatarKind: 'preset', avatarPreset: avatar.id, avatarPhotoId: null, updatedAt: now }).where(eq(users.id, uid));
  } else {
    await tx.update(users).set({ avatarKind: 'initial', avatarPhotoId: null, updatedAt: now }).where(eq(users.id, uid));
  }
}

/** Support hides the active photo (audited by the caller): removed, uploads locked until restored. */
export async function adminHidePhoto(tx: DbOrTx, uid: string, adminId: string, reason: string, now: Date) {
  const removed = await tx
    .update(avatarPhotos)
    .set({ status: 'removed', removedAt: now, removedBy: adminId, removedReason: reason })
    .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')))
    .returning({ id: avatarPhotos.id });
  await tx
    .update(users)
    .set({
      photoLockedAt: now,
      avatarPhotoId: null,
      avatarKind: sql`case when ${users.avatarKind} = 'photo' then (case when ${users.avatarPreset} is not null then 'preset' else 'initial' end) else ${users.avatarKind} end`,
      updatedAt: now,
    })
    .where(eq(users.id, uid));
  return { photoId: removed[0]?.id ?? null };
}

/**
 * Re-activate the most recent photo support removed (under 7 days old) and unlock uploads. Never a
 * photo the owner removed or replaced themselves → `nothing_to_restore`.
 */
export async function adminRestorePhoto(tx: DbOrTx, uid: string, now: Date) {
  const cutoff = new Date(now.getTime() - PHOTO_RETENTION_DAYS * 86_400_000);
  const [p] = await tx
    .select({ id: avatarPhotos.id })
    .from(avatarPhotos)
    .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'removed'), sql`${avatarPhotos.removedBy} is not null`, sql`${avatarPhotos.removedAt} > ${cutoff}`))
    .orderBy(desc(avatarPhotos.removedAt))
    .limit(1);
  if (!p) throw conflict('nothing_to_restore', 'No photo removed by support in the last 7 days');
  await tx
    .update(avatarPhotos)
    .set({ status: 'replaced', removedAt: now })
    .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')));
  await tx
    .update(avatarPhotos)
    .set({ status: 'active', removedAt: null, removedBy: null, removedReason: null })
    .where(eq(avatarPhotos.id, p.id));
  await tx.update(users).set({ photoLockedAt: null, avatarKind: 'photo', avatarPhotoId: p.id, updatedAt: now }).where(eq(users.id, uid));
  return { photoId: p.id };
}

export interface PhotoBytes {
  bytes: Buffer;
  etag: string;
}

/** The owner's own active photo (never a removed one). */
export async function ownPhotoBytes(db: DbOrTx, uid: string, size: PhotoSize): Promise<PhotoBytes | null> {
  const r = await db.execute<{ small: Buffer; large: Buffer; sha_small: string; sha_large: string }>(sql`
    select ap.small, ap.large, ap.sha_small, ap.sha_large
    from users u join avatar_photos ap on ap.id = u.avatar_photo_id
    where u.id = ${uid} and ap.user_id = ${uid} and ap.status = 'active'`);
  return pick(r.rows[0], size);
}

/** A public photo — only under the rule in design §3.3. */
export async function publicPhotoBytes(db: DbOrTx, photoId: string, size: PhotoSize): Promise<PhotoBytes | null> {
  const r = await db.execute<{ small: Buffer; large: Buffer; sha_small: string; sha_large: string }>(sql`
    select ap.small, ap.large, ap.sha_small, ap.sha_large
    from avatar_photos ap
    join users u on u.id = ap.user_id
    left join community_members cm on cm.user_id = u.id
    where ap.id = ${photoId} and u.avatar_photo_id = ap.id and ${photoPublicSql()}`);
  return pick(r.rows[0], size);
}

/** Support's view of a photo they moderate: any status, within the 7-day retention. */
export async function adminPhotoBytes(db: DbOrTx, uid: string, photoId: string, size: PhotoSize, now: Date): Promise<PhotoBytes | null> {
  const cutoff = new Date(now.getTime() - PHOTO_RETENTION_DAYS * 86_400_000);
  const r = await db.execute<{ small: Buffer; large: Buffer; sha_small: string; sha_large: string }>(sql`
    select small, large, sha_small, sha_large from avatar_photos
    where id = ${photoId} and user_id = ${uid} and (status = 'active' or coalesce(removed_at, created_at) > ${cutoff})`);
  return pick(r.rows[0], size);
}

function pick(row: { small: Buffer; large: Buffer; sha_small: string; sha_large: string } | undefined, size: PhotoSize): PhotoBytes | null {
  if (!row) return null;
  return size === 96 ? { bytes: row.small, etag: `"${row.sha_small}"` } : { bytes: row.large, etag: `"${row.sha_large}"` };
}

/** Daily: drop replaced/removed photos past the retention. */
export async function purgeOldPhotos(db: DbOrTx, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - PHOTO_RETENTION_DAYS * 86_400_000);
  const r = await db.execute(sql`
    delete from avatar_photos where status in ('replaced', 'removed') and coalesce(removed_at, created_at) < ${cutoff}`);
  return r.rowCount ?? 0;
}
