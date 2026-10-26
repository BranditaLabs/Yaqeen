import { randomUUID } from 'node:crypto';
import { and, desc, eq, ilike, lt, or, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AdjustPointsRequest, type AdminUserRow, UserStatus } from '@yaqeen/contracts';
import { authIdentities, challengeEnrollments, pointsLedger, publicProfiles, redemptions, users } from '../../db/schema.js';
import { challengeDayNumber, localToday } from '../../domain/points.js';
import { audit } from '../../lib/audit.js';
import { maskEmail } from '../../lib/crypto.js';
import { badRequest, notFound } from '../../lib/errors.js';
import { DELETION_GRACE_DAYS, exportUser } from '../public/me.routes.js';
import { adminOf } from '../../plugins/auth.js';

export const adminUsersRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const read = app.requireAdmin(['support', 'marketing']);
  const write = app.requireAdmin(['support']);

  const balanceExpr = sql<string>`coalesce((select sum(${pointsLedger.delta}) from ${pointsLedger} where ${pointsLedger.userId} = ${users.id}), 0)`;

  /** Cursor = ISO createdAt of the last row. */
  app.get('/', { preHandler: read }, async (req) => {
    const q = z
      .object({
        search: z.string().max(80).optional(),
        status: UserStatus.optional(),
        cursor: z.iso.datetime().optional(),
        limit: z.coerce.number().int().min(1).max(100).default(25),
      })
      .parse(req.query);
    const conds = [];
    if (q.status) conds.push(eq(users.status, q.status));
    if (q.search) conds.push(or(ilike(users.displayName, `%${q.search}%`), ilike(users.email, `%${q.search}%`))!);
    if (q.cursor) conds.push(lt(users.createdAt, new Date(q.cursor)));

    const rows = await db
      .select({
        id: users.id,
        displayName: users.displayName,
        email: users.email,
        status: users.status,
        createdAt: users.createdAt,
        provider: authIdentities.provider,
        startedOn: challengeEnrollments.startedOn,
        balance: balanceExpr,
      })
      .from(users)
      .leftJoin(authIdentities, eq(authIdentities.userId, users.id))
      .leftJoin(challengeEnrollments, eq(challengeEnrollments.userId, users.id))
      .where(conds.length ? and(...conds) : undefined)
      .orderBy(desc(users.createdAt))
      .limit(q.limit + 1);

    const today = localToday(app.ctx.now());
    const items: AdminUserRow[] = rows.slice(0, q.limit).map((r) => ({
      id: r.id,
      displayName: r.displayName,
      emailMasked: maskEmail(r.email),
      provider: r.provider ?? 'guest',
      status: r.status,
      joinedAt: r.createdAt.toISOString(),
      challengeDay: r.startedOn ? (challengeDayNumber(r.startedOn, today) ?? 0) : 0,
      balance: Number(r.balance),
    }));
    const nextCursor = rows.length > q.limit ? items.at(-1)!.joinedAt : null;
    return { items, nextCursor };
  });

  /** Support detail: account, points ledger, redemptions. No worship history by design. */
  app.get('/:id', { preHandler: read }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const [u] = await db.select().from(users).where(eq(users.id, id));
    if (!u) throw notFound('user');
    const ledger = await db
      .select()
      .from(pointsLedger)
      .where(eq(pointsLedger.userId, id))
      .orderBy(desc(pointsLedger.createdAt))
      .limit(50);
    const reds = await db.select().from(redemptions).where(eq(redemptions.userId, id)).orderBy(desc(redemptions.createdAt));
    const [card] = await db
      .select({ handle: publicProfiles.handle, published: publicProfiles.published, views: publicProfiles.views })
      .from(publicProfiles)
      .where(eq(publicProfiles.userId, id));
    return {
      id: u.id,
      displayName: u.displayName,
      emailMasked: maskEmail(u.email),
      status: u.status,
      city: u.city,
      joinedAt: u.createdAt,
      lastSeenAt: u.lastSeenAt,
      deletionRequestedAt: u.deletionRequestedAt,
      deletionDueAt: u.deletionRequestedAt ? new Date(u.deletionRequestedAt.getTime() + DELETION_GRACE_DAYS * 86_400_000) : null,
      balance: ledger.length ? Number((await db.select({ s: sql<string>`sum(${pointsLedger.delta})` }).from(pointsLedger).where(eq(pointsLedger.userId, id)))[0]?.s ?? 0) : 0,
      ledger: ledger.map((l) => ({ id: l.id, delta: l.delta, reason: l.reason, note: l.note, createdAt: l.createdAt })),
      redemptions: reds,
      // The public card's identity only (what anyone scanning it already sees) — for moderation.
      publicProfile: card ? { ...card, url: `${app.ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '')}/u/${card.handle}` } : null,
    };
  });

  /**
   * PDPL access request handled by support: account, consents, ledger, redemptions.
   * Worship history is deliberately left out — only the user can export that, from the app.
   */
  app.get('/:id/export', { preHandler: write }, async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const [u] = await db.select({ id: users.id }).from(users).where(eq(users.id, id));
    if (!u) throw notFound('user');
    const data = await db.transaction(async (tx) => {
      await audit(tx, req, { action: 'user.export', targetType: 'user', targetId: id });
      return exportUser(db, id, { includeWorship: false });
    });
    reply.header('Content-Disposition', `attachment; filename="yaqeen-user-${id.slice(0, 8)}.json"`);
    return { exportedAt: app.ctx.now().toISOString(), exportedBy: 'support', worshipHistory: 'excluded — available to the user in the app', ...data };
  });

  /** Manual points adjustment — reason is mandatory and the action is audited. */
  app.post('/:id/points', { preHandler: write }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = AdjustPointsRequest.parse(req.body);
    if (Math.abs(body.delta) > 5000) throw badRequest('delta_too_large', 'Adjustments over 5,000 need super_admin via SQL runbook');
    await db.transaction(async (tx) => {
      const [u] = await tx.select({ id: users.id }).from(users).where(eq(users.id, id));
      if (!u) throw notFound('user');
      await tx.insert(pointsLedger).values({
        userId: id,
        delta: body.delta,
        reason: 'admin_adjustment',
        refKey: `admin:${adminOf(req).sub}:${randomUUID()}`,
        note: [body.reason, body.note].filter(Boolean).join(' — '),
      });
      await audit(tx, req, { action: 'user.points.adjust', targetType: 'user', targetId: id, reason: body.reason, after: body });
    });
    return { ok: true };
  });

  /** Moderation: hide a public card (abusive name, bio or links). The owner can edit and republish. */
  app.post('/:id/public-profile/unpublish', { preHandler: write }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = z.object({ reason: z.string().min(3).max(200) }).parse(req.body);
    await db.transaction(async (tx) => {
      const [before] = await tx.select({ handle: publicProfiles.handle, published: publicProfiles.published }).from(publicProfiles).where(eq(publicProfiles.userId, id));
      if (!before) throw notFound('public_profile');
      await tx.update(publicProfiles).set({ published: false, updatedAt: app.ctx.now() }).where(eq(publicProfiles.userId, id));
      await audit(tx, req, { action: 'user.public_profile.unpublish', targetType: 'user', targetId: id, reason: body.reason, before, after: { published: false } });
    });
    await app.ctx.cache.bumpNamespace('profile');
    return { ok: true };
  });

  app.post('/:id/status', { preHandler: write }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = z.object({ status: UserStatus, reason: z.string().min(3).max(200) }).parse(req.body);
    await db.transaction(async (tx) => {
      const [before] = await tx.select({ status: users.status }).from(users).where(eq(users.id, id));
      if (!before) throw notFound('user');
      await tx.update(users).set({ status: body.status, updatedAt: app.ctx.now() }).where(eq(users.id, id));
      await audit(tx, req, { action: 'user.status', targetType: 'user', targetId: id, reason: body.reason, before, after: { status: body.status } });
    });
    return { ok: true };
  });
};
