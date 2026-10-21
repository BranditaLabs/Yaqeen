import { desc, eq, lt } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AdminRole, ConfigPatch, HijriAdjustRequest } from '@yaqeen/contracts';
import { adminUsers, appConfig, auditLog, hijriAdjustments } from '../../db/schema.js';
import { localToday } from '../../domain/points.js';
import { audit } from '../../lib/audit.js';
import { generateTotpSecret, hashPassword } from '../../lib/crypto.js';
import { badRequest } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';
import { previewAdjustment } from '../../services/calendar.service.js';
import { readConfig } from '../public/app.routes.js';

export const adminSettingsRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const superOnly = app.requireAdmin([]);
  const calendarRoles = app.requireAdmin(['religious_reviewer']);

  /* -------------------------------------------------------- remote config */
  app.get('/config', { preHandler: app.requireAdmin(['marketing', 'content_editor', 'religious_reviewer', 'support']) }, async () =>
    readConfig(app),
  );

  app.patch('/config', { preHandler: superOnly }, async (req) => {
    const patch = ConfigPatch.parse(req.body);
    if (patch.hijri) throw badRequest('use_hijri_endpoint', 'Hijri offset is changed via /admin/settings/hijri');
    if (patch.points) throw badRequest('use_program_endpoint', 'Points settings are changed via /admin/rewards/program');
    await db.transaction(async (tx) => {
      const before = await readConfig(app);
      for (const [key, value] of Object.entries(patch)) {
        await tx
          .insert(appConfig)
          .values({ key, value, updatedBy: adminOf(req).sub })
          .onConflictDoUpdate({ target: appConfig.key, set: { value, updatedBy: adminOf(req).sub, updatedAt: app.ctx.now() } });
      }
      await audit(tx, req, { action: 'config.patch', targetType: 'config', before, after: patch });
    });
    return readConfig(app);
  });

  /* ---------------------------------------------------------------- hijri */
  app.post('/hijri/preview', { preHandler: calendarRoles }, async (req) => {
    const body = HijriAdjustRequest.parse(req.body);
    return previewAdjustment(app.ctx, { ...body, createdAt: app.ctx.now() }, localToday(app.ctx.now()));
  });

  /** Saves only if the preview has no impossible month lengths. */
  app.post('/hijri', { preHandler: calendarRoles }, async (req) => {
    const body = HijriAdjustRequest.parse(req.body);
    const preview = await previewAdjustment(app.ctx, { ...body, createdAt: app.ctx.now() }, localToday(app.ctx.now()));
    if (preview.warnings.length) throw badRequest('hijri_invalid_sequence', preview.warnings.join(' · '), preview.warnings);
    await db.transaction(async (tx) => {
      const [row] = await tx.insert(hijriAdjustments).values({ ...body, createdBy: adminOf(req).sub }).returning();
      await audit(tx, req, { action: 'hijri.adjust', targetType: 'hijri', targetId: row!.id, after: body });
    });
    return { ok: true, firstOfMonths: preview.firstOfMonths };
  });

  /* ---------------------------------------------------------------- audit */
  app.get('/audit', { preHandler: superOnly }, async (req) => {
    const q = z.object({ cursor: z.iso.datetime().optional() }).parse(req.query);
    return db
      .select({
        id: auditLog.id,
        action: auditLog.action,
        targetType: auditLog.targetType,
        targetId: auditLog.targetId,
        reason: auditLog.reason,
        createdAt: auditLog.createdAt,
        admin: adminUsers.name,
      })
      .from(auditLog)
      .leftJoin(adminUsers, eq(adminUsers.id, auditLog.adminId))
      .where(q.cursor ? lt(auditLog.createdAt, new Date(q.cursor)) : undefined)
      .orderBy(desc(auditLog.createdAt))
      .limit(100);
  });

  /* ----------------------------------------------------------------- team */
  app.get('/team', { preHandler: superOnly }, async () =>
    db
      .select({ id: adminUsers.id, name: adminUsers.name, email: adminUsers.email, role: adminUsers.role, active: adminUsers.active, lastLoginAt: adminUsers.lastLoginAt })
      .from(adminUsers)
      .orderBy(adminUsers.name),
  );

  /** Returns the TOTP secret ONCE so the new admin can add it to an authenticator app. */
  app.post('/team', { preHandler: superOnly }, async (req) => {
    const body = z.object({ name: z.string().min(2), email: z.email(), role: AdminRole, password: z.string().min(12) }).parse(req.body);
    const totpSecret = generateTotpSecret();
    const row = await db.transaction(async (tx) => {
      const [a] = await tx
        .insert(adminUsers)
        .values({ name: body.name, email: body.email, role: body.role, passwordHash: await hashPassword(body.password), totpSecret })
        .returning({ id: adminUsers.id });
      await audit(tx, req, { action: 'admin.create', targetType: 'admin', targetId: a!.id, after: { email: body.email, role: body.role } });
      return a!;
    });
    return { id: row.id, totpSecret, otpauthUrl: `otpauth://totp/Yaqeen:${encodeURIComponent(body.email)}?secret=${totpSecret}&issuer=Yaqeen` };
  });

  app.patch('/team/:id', { preHandler: superOnly }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = z.object({ role: AdminRole.optional(), active: z.boolean().optional() }).parse(req.body);
    if (id === adminOf(req).sub) throw badRequest('cannot_edit_self');
    await db.transaction(async (tx) => {
      await tx.update(adminUsers).set(body).where(eq(adminUsers.id, id));
      await audit(tx, req, { action: 'admin.update', targetType: 'admin', targetId: id, after: body });
    });
    return { ok: true };
  });
};
