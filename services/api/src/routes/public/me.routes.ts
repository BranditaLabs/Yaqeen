import { and, desc, eq, isNull, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { FastifyPluginAsync } from 'fastify';
import {
  type ConsentKind,
  ConsentKind as ConsentKindSchema,
  ClaimTagRequest,
  ConsentUpdate,
  type ConsentsResponse,
  PublicProfileUpdate,
  RegisterDeviceRequest,
  TagCode,
  UpdateSettingsRequest,
} from '@yaqeen/contracts';
import {
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
import { notFound } from '../../lib/errors.js';
import { userId } from '../../plugins/auth.js';
import * as profile from '../../services/profile.service.js';
import * as tags from '../../services/tags.service.js';

/** Bump when the privacy policy text changes; stored with every consent event. */
export const POLICY_VERSION = '2026-10-01';

/** Days between an erasure request and the purge job anonymising the account. */
export const DELETION_GRACE_DAYS = 30;

/** Everything held about a user — shared by GET /v1/me/export and the admin export. */
export async function exportUser(db: Db, uid: string, opts: { includeWorship: boolean }) {
  const [profile] = await db.select().from(users).where(eq(users.id, uid));
  return {
    profile,
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
    return { ok: true };
  });

  app.get('/consents', async (req): Promise<ConsentsResponse> => {
    const rows = await db.select().from(consents).where(eq(consents.userId, userId(req)));
    const out = Object.fromEntries(ConsentKindSchema.options.map((k) => [k, false])) as Record<ConsentKind, boolean>;
    for (const r of rows) out[r.kind] = r.granted;
    return out;
  });

  /** Each change is stored as current state + an immutable event (PDPL evidence). */
  app.put('/consents', async (req) => {
    const body = ConsentUpdate.parse(req.body);
    const uid = userId(req);
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
    });
    return { ok: true };
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
    return { exportedAt: app.ctx.now().toISOString(), ...(await exportUser(db, userId(req), { includeWorship: true })) };
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
    });
    await app.ctx.cache.bumpNamespace('profile'); // the public card disappears at once
    return reply.status(202).send({ status: 'deletion_requested', graceDays: DELETION_GRACE_DAYS });
  });
};
