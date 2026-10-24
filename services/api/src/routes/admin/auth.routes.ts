import { eq, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { AdminLoginRequest, TestDevicesUpdate } from '@yaqeen/contracts';
import { adminUsers } from '../../db/schema.js';
import { verifyPassword, verifyTotp } from '../../lib/crypto.js';
import { audit } from '../../lib/audit.js';
import { notFound, unauthorized } from '../../lib/errors.js';
import { ADMIN_TTL_SEC, signAdminToken } from '../../lib/tokens.js';
import { adminOf } from '../../plugins/auth.js';

export const adminAuthRoutes: FastifyPluginAsync = async (app) => {
  const { db, env } = app.ctx;

  /** Email + password + TOTP. Same error for every failure to avoid account enumeration. */
  app.post('/login', { config: { rateLimit: { max: 5, timeWindow: '5 minutes' } } }, async (req) => {
    const body = AdminLoginRequest.parse(req.body);
    const [a] = await db
      .select()
      .from(adminUsers)
      .where(eq(sql`lower(${adminUsers.email})`, body.email.toLowerCase()));
    const ok =
      a !== undefined &&
      a.active &&
      (await verifyPassword(body.password, a.passwordHash)) &&
      verifyTotp(a.totpSecret, body.totp, app.ctx.now().getTime());
    if (!ok || !a) throw unauthorized('invalid_credentials');
    await db.update(adminUsers).set({ lastLoginAt: app.ctx.now() }).where(eq(adminUsers.id, a.id));
    return {
      token: await signAdminToken({ sub: a.id, role: a.role }, env.ADMIN_JWT_SECRET),
      expiresIn: ADMIN_TTL_SEC,
      admin: { id: a.id, name: a.name, email: a.email, role: a.role },
    };
  });

  const anyAdmin = app.requireAdmin(['content_editor', 'religious_reviewer', 'marketing', 'support']);

  app.get('/me', { preHandler: anyAdmin }, async (req) => {
    const [a] = await db
      .select({ id: adminUsers.id, name: adminUsers.name, email: adminUsers.email, role: adminUsers.role, testDevices: sql<number>`cardinality(${adminUsers.testDeviceTokens})` })
      .from(adminUsers)
      .where(eq(adminUsers.id, adminOf(req).sub));
    if (!a) throw notFound('admin');
    return a;
  });

  /** FCM tokens of the admin's own phones (copied from the app's debug screen) for test sends. */
  app.put('/me/test-devices', { preHandler: anyAdmin }, async (req) => {
    const body = TestDevicesUpdate.parse(req.body);
    await db.transaction(async (tx) => {
      await tx.update(adminUsers).set({ testDeviceTokens: body.tokens }).where(eq(adminUsers.id, adminOf(req).sub));
      await audit(tx, req, { action: 'admin.test_devices', targetType: 'admin', targetId: adminOf(req).sub, after: { count: body.tokens.length } });
    });
    return { ok: true, count: body.tokens.length };
  });
};
