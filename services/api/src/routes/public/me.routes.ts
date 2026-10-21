import { desc, eq } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import {
  type ConsentKind,
  ConsentKind as ConsentKindSchema,
  ConsentUpdate,
  type ConsentsResponse,
  RegisterDeviceRequest,
  UpdateSettingsRequest,
} from '@yaqeen/contracts';
import { consentEvents, consents, devices, pointsLedger, redemptions, taskCompletions, users } from '../../db/schema.js';
import { notFound } from '../../lib/errors.js';
import { userId } from '../../plugins/auth.js';

/** Bump when the privacy policy text changes; stored with every consent event. */
export const POLICY_VERSION = '2026-10-01';

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

  /** PDPL right of access: everything we hold about the user, as JSON. */
  app.get('/export', async (req) => {
    const uid = userId(req);
    const [profile] = await db.select().from(users).where(eq(users.id, uid));
    return {
      exportedAt: app.ctx.now().toISOString(),
      profile,
      consents: await db.select().from(consentEvents).where(eq(consentEvents.userId, uid)),
      devices: await db.select({ platform: devices.platform, appVersion: devices.appVersion, lastSeenAt: devices.lastSeenAt }).from(devices).where(eq(devices.userId, uid)),
      taskCompletions: await db.select().from(taskCompletions).where(eq(taskCompletions.userId, uid)),
      pointsLedger: await db.select().from(pointsLedger).where(eq(pointsLedger.userId, uid)),
      redemptions: await db.select().from(redemptions).where(eq(redemptions.userId, uid)),
    };
  });

  /** PDPL right to erasure: mark for deletion; a job hard-deletes after the grace period. */
  app.delete('/', async (req, reply) => {
    await db.update(users).set({ status: 'deletion_requested', updatedAt: app.ctx.now() }).where(eq(users.id, userId(req)));
    return reply.status(202).send({ status: 'deletion_requested', graceDays: 14 });
  });
};
