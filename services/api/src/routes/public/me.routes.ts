import { and, desc, eq, isNull, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { FastifyError, FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import {
  AVATAR_PHOTO,
  AttestRequest,
  BackupKind,
  BackupPutRequest,
  type ConsentKind,
  ConsentKind as ConsentKindSchema,
  ClaimTagRequest,
  CommunityUpdate,
  ConsentUpdate,
  type ConsentsResponse,
  ProductEventsBatch,
  PublicProfileUpdate,
  RegisterDeviceRequest,
  TagCode,
  UpdateProfileRequest,
  UpdateSettingsRequest,
} from '@yaqeen/contracts';
import {
  avatarPhotos,
  campaignDeliveries,
  campaigns,
  consentEvents,
  consents,
  devices,
  pointsLedger,
  profileTags,
  publicProfiles,
  redemptions,
  refreshTokens,
  taskCompletions,
  users,
} from '../../db/schema.js';
import type { Db } from '../../db/client.js';
import { AppError, errorHandler, forbidden, notFound } from '../../lib/errors.js';
import { userId } from '../../plugins/auth.js';
import * as avatar from '../../services/avatar.service.js';
import { listBadges } from '../../services/badges.service.js';
import * as community from '../../services/community.service.js';
import * as profile from '../../services/profile.service.js';
import * as tags from '../../services/tags.service.js';
import * as analytics from '../../services/product-analytics.service.js';
import * as backup from '../../services/backup.service.js';

/** Bump when the privacy policy text changes; stored with every consent event. */
export const POLICY_VERSION = community.POLICY_VERSION;

/** Days between an erasure request and the purge job anonymising the account. */
export const DELETION_GRACE_DAYS = 30;

/**
 * Profile identity and community data held about a user (design §1.3 export). The user's own export
 * also carries their active photo as base64 WebP; the admin export carries the metadata only.
 */
async function communityExport(db: Db, uid: string, opts: { includePhoto: boolean }) {
  const [u] = await db
    .select({ kind: users.avatarKind, preset: users.avatarPreset, photoId: users.avatarPhotoId, country: users.country, attestedAt: users.adultAttestedAt, nameHiddenAt: users.nameHiddenAt, photoLockedAt: users.photoLockedAt })
    .from(users)
    .where(eq(users.id, uid));
  const photos = await db
    .select({ id: avatarPhotos.id, status: avatarPhotos.status, bytes: avatarPhotos.bytes, createdAt: avatarPhotos.createdAt, removedAt: avatarPhotos.removedAt, removedBySupport: sql<boolean>`${avatarPhotos.removedBy} is not null` })
    .from(avatarPhotos)
    .where(eq(avatarPhotos.userId, uid))
    .orderBy(desc(avatarPhotos.createdAt));
  let photoWebp256Base64: string | null = null;
  if (opts.includePhoto) {
    const own = await avatar.ownPhotoBytes(db, uid, 256);
    photoWebp256Base64 = own ? own.bytes.toString('base64') : null;
  }
  const q = async <T extends Record<string, unknown>>(query: ReturnType<typeof sql>) => (await db.execute<T>(query)).rows;
  return {
    avatar: { kind: u?.kind ?? 'initial', preset: u?.preset ?? null, activePhotoId: u?.photoId ?? null, photos, ...(opts.includePhoto ? { photoWebp256Base64 } : {}) },
    community: {
      settings: await community.readSettings(db, uid),
      country: u?.country ?? null,
      attestedAdultAt: u?.attestedAt ?? null,
      nameHiddenAt: u?.nameHiddenAt ?? null,
      photoLockedAt: u?.photoLockedAt ?? null,
      leagueHistory: await q(sql`
        select starts_on::text as "startsOn", division, joined_at as "joinedAt", left_at as "leftAt", snapshot_points as "snapshotPoints",
          snapshot_rank as "snapshotRank", final_points as "finalPoints", final_rank as "finalRank", outcome
        from league_members where user_id = ${uid} order by starts_on desc`),
      tournamentEntries: await q(sql`
        select t.slug, t.title_ar as "titleAr", t.title_en as "titleEn", e.joined_at as "joinedAt", e.left_at as "leftAt",
          e.snapshot_points as "snapshotPoints", e.snapshot_rank as "snapshotRank", e.final_points as "finalPoints", e.final_rank as "finalRank"
        from tournament_entries e join tournaments t on t.id = e.tournament_id where e.user_id = ${uid} order by e.joined_at desc`),
      badges: await listBadges({ db }, uid),
      blocksMade: await q(sql`
        select pp.handle, b.created_at as "createdAt" from community_blocks b
        left join public_profiles pp on pp.user_id = b.blocked_user_id where b.user_id = ${uid} order by b.created_at desc`),
      reportsFiled: await q(sql`
        select pp.handle, r.reason, r.created_at as "createdAt", r.resolved_at as "resolvedAt", r.resolution
        from community_reports r left join public_profiles pp on pp.user_id = r.target_user_id where r.reporter_id = ${uid} order by r.created_at desc`),
    },
  };
}

/** Everything held about a user — shared by GET /v1/me/export and the admin export. */
export async function exportUser(db: Db, uid: string, opts: { includeWorship: boolean }) {
  const [profile] = await db.select().from(users).where(eq(users.id, uid));
  return {
    profile,
    // Admins get the photo metadata only, never the image (design §1.3).
    ...(await communityExport(db, uid, { includePhoto: opts.includeWorship })),
    consents: await db.select().from(consentEvents).where(eq(consentEvents.userId, uid)),
    devices: await db
      .select({ platform: devices.platform, appVersion: devices.appVersion, lastSeenAt: devices.lastSeenAt })
      .from(devices)
      .where(eq(devices.userId, uid)),
    // Worship history goes only to the user themself — never to an admin (CLAUDE.md rule 2).
    ...(opts.includeWorship
      ? { taskCompletions: await db.select().from(taskCompletions).where(eq(taskCompletions.userId, uid)) }
      : {}),
    // The ref key names the task ("2026-10-20:task:five_prayers"), so admins get the ledger without it.
    pointsLedger: opts.includeWorship
      ? await db.select().from(pointsLedger).where(eq(pointsLedger.userId, uid))
      : await db
          .select({ id: pointsLedger.id, delta: pointsLedger.delta, reason: pointsLedger.reason, note: pointsLedger.note, createdAt: pointsLedger.createdAt })
          .from(pointsLedger)
          .where(eq(pointsLedger.userId, uid)),
    redemptions: await db.select().from(redemptions).where(eq(redemptions.userId, uid)),
    publicProfile: (await db.select().from(publicProfiles).where(eq(publicProfiles.userId, uid)))[0] ?? null,
    tags: await db
      .select({ code: profileTags.code, kind: profileTags.kind, linkedAt: profileTags.linkedAt, disabledAt: profileTags.disabledAt, scans: profileTags.scans })
      .from(profileTags)
      .where(eq(profileTags.userId, uid)),
  };
}

export const meRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  app.addHook('preHandler', app.requireUser);

  app.get('/', async (req) => {
    const [u] = await db.select().from(users).where(eq(users.id, userId(req)));
    if (!u) throw notFound('user');
    return {
      id: u.id,
      displayName: u.displayName,
      isGuest: u.isGuest,
      settings: {
        locale: u.locale,
        city: u.city,
        timezone: u.timezone,
        prayerMethod: u.prayerMethod,
        asrSchool: u.asrSchool,
        hijriOffsetDays: u.hijriOffsetDays,
      },
    };
  });

  app.patch('/settings', async (req) => {
    const patch = UpdateSettingsRequest.parse(req.body);
    await db
      .update(users)
      .set({ ...patch, updatedAt: app.ctx.now() })
      .where(eq(users.id, userId(req)));
    // The country only refines the opt-in country board; a change moves the member at once.
    if (patch.country !== undefined) await app.ctx.cache.bumpNamespace('community');
    return { ok: true };
  });

  app.get('/consents', async (req): Promise<ConsentsResponse> => {
    const rows = await db.select().from(consents).where(eq(consents.userId, userId(req)));
    const out = Object.fromEntries(ConsentKindSchema.options.map((k) => [k, false])) as Record<ConsentKind, boolean>;
    for (const r of rows) out[r.kind] = r.granted;
    return out;
  });

  /**
   * Each change is stored as current state + an immutable event (PDPL evidence). Withdrawing
   * `cloud_backup` deletes the server copy in the same transaction; a guest can't grant it.
   */
  app.put('/consents', async (req) => {
    const body = ConsentUpdate.parse(req.body);
    const uid = userId(req);
    if (body.kind === 'community') {
      // Derived consent: granted only by joining (PUT /v1/me/community, tournament join); withdrawing
      // it here leaves everything in the same transaction.
      if (body.granted) throw forbidden('use_community_settings', 'Join a competition from its screen');
      const now = app.ctx.now();
      await db.transaction(async (tx) => {
        await community.leaveEverything(tx, uid, now);
        await community.recomputeCommunityConsent(tx, uid, body.source, { force: true });
      });
      await app.ctx.cache.bumpNamespace('community');
      await app.ctx.cache.bumpNamespace('profile');
      return { ok: true };
    }
    if (body.kind === 'cloud_backup' && body.granted) {
      const [u] = await db.select({ isGuest: users.isGuest }).from(users).where(eq(users.id, uid));
      if (!u || u.isGuest) throw forbidden('account_required', 'Sign in with Google or Apple to use cloud backup');
    }
    await db.transaction(async (tx) => {
      await tx
        .insert(consents)
        .values({ userId: uid, kind: body.kind, granted: body.granted })
        .onConflictDoUpdate({
          target: [consents.userId, consents.kind],
          set: { granted: body.granted, updatedAt: app.ctx.now() },
        });
      await tx.insert(consentEvents).values({
        userId: uid,
        kind: body.kind,
        granted: body.granted,
        source: body.source,
        policyVersion: POLICY_VERSION,
      });
      if (body.kind === 'cloud_backup' && !body.granted) await backup.wipe(tx, [uid]);
    });
    return { ok: true };
  });

  /* -------------------------------------------- opt-in cloud backup (consent cloud_backup) */

  /** Which kinds the server holds, with their versions — never the content. */
  app.get('/backup', async (req) => backup.manifest(app.ctx, userId(req)));

  app.get('/backup/:kind', async (req) => {
    const { kind } = z.object({ kind: BackupKind }).parse(req.params);
    return backup.get(app.ctx, userId(req), kind);
  });

  app.put('/backup/:kind', { bodyLimit: 512 * 1024, config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req) => {
    const { kind } = z.object({ kind: BackupKind }).parse(req.params);
    return backup.put(app.ctx, userId(req), kind, BackupPutRequest.parse(req.body));
  });

  app.post('/devices', async (req) => {
    const body = RegisterDeviceRequest.parse(req.body);
    await db
      .insert(devices)
      .values({ userId: userId(req), platform: body.platform, fcmToken: body.fcmToken, appVersion: body.appVersion })
      .onConflictDoUpdate({
        target: devices.fcmToken,
        set: { userId: userId(req), appVersion: body.appVersion, lastSeenAt: app.ctx.now(), invalidatedAt: null },
      });
    return { ok: true };
  });

  /** A push from a campaign was opened. Idempotent: only the first open counts. */
  app.post('/campaigns/:id/opened', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const uid = userId(req);
    const counted = await db.transaction(async (tx) => {
      const rows = await tx
        .update(campaignDeliveries)
        .set({ openedAt: app.ctx.now() })
        .where(and(eq(campaignDeliveries.campaignId, id), eq(campaignDeliveries.userId, uid), isNull(campaignDeliveries.openedAt)))
        .returning({ c: campaignDeliveries.campaignId });
      if (rows.length) await tx.update(campaigns).set({ openCount: sql`${campaigns.openCount} + 1` }).where(eq(campaigns.id, id));
      return rows.length > 0;
    });
    return { counted };
  });

  app.get('/redemptions', async (req) =>
    db.select().from(redemptions).where(eq(redemptions.userId, userId(req))).orderBy(desc(redemptions.createdAt)),
  );

  app.get('/ledger', async (req) =>
    db
      .select({ id: pointsLedger.id, delta: pointsLedger.delta, reason: pointsLedger.reason, note: pointsLedger.note, createdAt: pointsLedger.createdAt })
      .from(pointsLedger)
      .where(eq(pointsLedger.userId, userId(req)))
      .orderBy(desc(pointsLedger.createdAt))
      .limit(200),
  );

  /* ------------------------------------------------- public profile card (NFC / QR) */

  /** The owner's card settings (a suggested draft before the first save), its URL and scan count. */
  app.get('/public-profile', async (req) => profile.settings(app.ctx, userId(req)));

  app.put('/public-profile', async (req) =>
    profile.update(app.ctx, userId(req), req.user?.guest ?? true, PublicProfileUpdate.parse(req.body)),
  );

  /** The owner's journey for the Profile tab: level, streak, challenge day and dated milestones. */
  app.get('/journey', async (req) => profile.myJourney(app.ctx, userId(req)));

  /* ---------------------------------------- profile identity and community (§5.24, §5.31) */

  /** The caller's profile (own avatar as authed paths; live level and week points, self only). */
  app.get('/profile', async (req) => profile.meProfile(app.ctx, userId(req)));

  app.patch('/profile', async (req) =>
    profile.updateMe(app.ctx, userId(req), req.user?.guest ?? true, UpdateProfileRequest.parse(req.body)),
  );

  /** The owner's active photo (96 or 256), whatever its visibility; never a removed one. */
  app.get('/avatar/photo/:size', async (req, reply) => {
    const { size } = z.object({ size: z.enum(['96', '256']) }).parse(req.params);
    const photo = await avatar.ownPhotoBytes(db, userId(req), Number(size) as avatar.PhotoSize);
    if (!photo) throw notFound('photo');
    return sendPhoto(req, reply, photo, 'private, no-cache');
  });

  app.delete('/avatar/photo', async (req) => avatar.removeOwnPhoto(app.ctx, userId(req)));

  /** The 18+ (or guardian consent) attestation; audited with the user as the actor. */
  app.post('/attestation', async (req) => {
    AttestRequest.parse(req.body);
    if (req.user?.guest ?? true) throw forbidden('account_required', 'Sign in to take part in competitions');
    return community.attest(app.ctx, userId(req), req.ip);
  });

  app.get('/community', async (req) => community.readSettings(db, userId(req)));

  app.put('/community', async (req) => {
    const body = CommunityUpdate.parse(req.body);
    if (req.user?.guest ?? true) throw forbidden('account_required', 'Sign in to take part in competitions');
    const settings = await community.updateCommunity(app.ctx, userId(req), body, req.ip);
    return settings;
  });

  /** Earned badges (league, division, tournament) plus streak milestones and level crossings, newest first. */
  app.get('/badges', async (req) => listBadges(app.ctx, userId(req)));

  /** Consented product analytics (closed list, no worship, no account link). 202 even when dropped. */
  app.post('/events', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const batch = ProductEventsBatch.parse(req.body);
    const accepted = await analytics.ingest(app.ctx, userId(req), batch);
    return reply.status(202).send({ accepted });
  });

  /** Physical tags (key medals, cards): list, activate by code, switch off a lost one. */
  app.get('/tags', async (req) => tags.mine(app.ctx, userId(req)));

  app.post('/tags', { config: { rateLimit: { max: 10, timeWindow: '10 minutes' } } }, async (req) => {
    const { code } = ClaimTagRequest.parse(req.body);
    return tags.claim(app.ctx, userId(req), req.user?.guest ?? true, code);
  });

  app.delete('/tags/:code', async (req, reply) => {
    const { code } = z.object({ code: TagCode }).parse(req.params);
    await tags.disable(app.ctx, userId(req), code);
    return reply.status(204).send();
  });

  app.get('/public-profile/available', async (req) => {
    const { handle } = z.object({ handle: z.string().max(40) }).parse(req.query);
    return { available: await profile.handleAvailable(app.ctx, handle, userId(req)) };
  });

  /** PDPL right of access: everything we hold about the user, as JSON. */
  app.get('/export', async (req) => {
    const uid = userId(req);
    return {
      exportedAt: app.ctx.now().toISOString(),
      ...(await exportUser(db, uid, { includeWorship: true })),
      // The opt-in cloud backup, opened — only here, never in the admin export.
      backups: await backup.exportFor(app.ctx, uid),
    };
  });

  /**
   * PDPL right to erasure: mark for deletion and end every session now; the purge job
   * (jobs/purge-deleted.ts) anonymises the account after the grace period.
   */
  app.delete('/', async (req, reply) => {
    const uid = userId(req);
    const now = app.ctx.now();
    await db.transaction(async (tx) => {
      await tx.update(users).set({ status: 'deletion_requested', deletionRequestedAt: now, updatedAt: now }).where(eq(users.id, uid));
      await tx.update(refreshTokens).set({ revokedAt: now }).where(and(eq(refreshTokens.userId, uid), isNull(refreshTokens.revokedAt)));
      await tx.update(devices).set({ invalidatedAt: now }).where(and(eq(devices.userId, uid), isNull(devices.invalidatedAt)));
      await tx.update(publicProfiles).set({ published: false, updatedAt: now }).where(eq(publicProfiles.userId, uid));
      await tags.disableAllFor(tx, uid, now);
      // Community (design §1.3): out of every competition, photo removed, country and blocks and
      // snapshot rows gone now; the purge job deletes the rest at tombstone time.
      await community.leaveEverything(tx, uid, now);
      await tx
        .update(avatarPhotos)
        .set({ status: 'removed', removedAt: now, removedBy: null })
        .where(and(eq(avatarPhotos.userId, uid), eq(avatarPhotos.status, 'active')));
      await tx.update(users).set({ avatarKind: 'initial', avatarPhotoId: null, country: null }).where(eq(users.id, uid));
      await tx.execute(sql`delete from community_blocks where user_id = ${uid} or blocked_user_id = ${uid}`);
      await tx.execute(sql`delete from leaderboard_snapshot where user_id = ${uid}`);
      await tx.execute(sql`update league_members set snapshot_points = null, snapshot_rank = null where user_id = ${uid}`);
      await tx.execute(sql`update tournament_entries set snapshot_points = null, snapshot_rank = null where user_id = ${uid}`);
      await community.recomputeCommunityConsent(tx, uid, 'erasure');
    });
    await app.ctx.cache.bumpNamespace('profile'); // the public card disappears at once
    await app.ctx.cache.bumpNamespace('community');
    return reply.status(202).send({ status: 'deletion_requested', graceDays: DELETION_GRACE_DAYS });
  });
};

/** Send WebP bytes with a per-size ETag (sha256 of that size); 304 when the client has it. */
export function sendPhoto(req: FastifyRequest, reply: FastifyReply, photo: avatar.PhotoBytes, cacheControl: string) {
  reply.header('ETag', photo.etag);
  reply.header('Cache-Control', cacheControl);
  reply.header('X-Content-Type-Options', 'nosniff');
  if (req.headers['if-none-match'] === photo.etag) return reply.code(304).send();
  reply.type('image/webp');
  return reply.code(200).send(photo.bytes);
}

/**
 * PUT /v1/me/avatar/photo — an encapsulated plugin (registered by app.ts under /v1/me) so the raw
 * image parsers and the 3 MiB body limit apply to this route only. Stable codes: 413
 * `photo_too_large`, 415 `photo_type`, 422 `photo_unreadable`, 409 `photo_locked`, 429 `rate_limited`.
 */
export const avatarUploadRoutes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.requireUser);
  for (const mime of AVATAR_PHOTO.mimes) {
    app.addContentTypeParser(mime, { parseAs: 'buffer', bodyLimit: AVATAR_PHOTO.maxBytes }, (_req, body, done) => done(null, body));
  }
  app.setErrorHandler((err: FastifyError | Error, req, reply) => {
    const status = (err as FastifyError).statusCode;
    if (!(err instanceof AppError) && status === 413) return errorHandler(new AppError(413, 'photo_too_large', 'The photo is larger than 3 MB'), req, reply);
    if (!(err instanceof AppError) && status === 415) return errorHandler(new AppError(415, 'photo_type', 'Send a JPEG, PNG or WebP image'), req, reply);
    return errorHandler(err, req, reply);
  });
  app.put(
    '/avatar/photo',
    { bodyLimit: AVATAR_PHOTO.maxBytes, config: { rateLimit: { max: 20, timeWindow: '1 hour' } } },
    async (req) => avatar.uploadPhoto(app.ctx, userId(req), req.user?.guest ?? true, req.headers['content-type'], req.body),
  );
};
