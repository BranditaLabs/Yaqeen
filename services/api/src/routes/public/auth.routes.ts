import { randomUUID } from 'node:crypto';
import { and, eq, gt, isNull } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { SignInRequest, type SessionResponse } from '@yaqeen/contracts';
import { authIdentities, refreshTokens, users } from '../../db/schema.js';
import { verifyAppleIdToken, verifyGoogleIdToken } from '../../integrations/oidc.js';
import { badRequest, unauthorized } from '../../lib/errors.js';
import { opaqueToken, sha256 } from '../../lib/crypto.js';
import { ACCESS_TTL_SEC, REFRESH_TTL_DAYS, signUserToken } from '../../lib/tokens.js';
import { userId } from '../../plugins/auth.js';

export const authRoutes: FastifyPluginAsync = async (app) => {
  const { db, env } = app.ctx;

  async function issueSession(user: { id: string; displayName: string | null; isGuest: boolean }): Promise<SessionResponse> {
    const refresh = opaqueToken();
    await db.insert(refreshTokens).values({
      userId: user.id,
      tokenHash: sha256(refresh),
      expiresAt: new Date(app.ctx.now().getTime() + REFRESH_TTL_DAYS * 86_400_000),
    });
    return {
      accessToken: await signUserToken({ sub: user.id, guest: user.isGuest }, env.JWT_SECRET),
      refreshToken: refresh,
      expiresIn: ACCESS_TTL_SEC,
      user,
    };
  }

  /** Sign in with Google / Apple, or start as a guest (guest can be upgraded later by signing in). */
  app.post('/sign-in', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (req) => {
    const body = SignInRequest.parse(req.body);
    let identity: { subject: string; email: string | null; name: string | null };
    if (body.provider === 'guest') {
      identity = { subject: randomUUID(), email: null, name: body.displayName ?? null };
    } else {
      if (!body.idToken) throw badRequest('id_token_required');
      identity =
        body.provider === 'google'
          ? await verifyGoogleIdToken(body.idToken, env.GOOGLE_CLIENT_IDS)
          : await verifyAppleIdToken(body.idToken, env.APPLE_CLIENT_IDS);
      identity.name ??= body.displayName ?? null;
    }

    const [existing] = await db
      .select({ id: users.id, displayName: users.displayName, isGuest: users.isGuest, status: users.status })
      .from(authIdentities)
      .innerJoin(users, eq(users.id, authIdentities.userId))
      .where(and(eq(authIdentities.provider, body.provider), eq(authIdentities.subject, identity.subject)));

    if (existing) {
      if (existing.status === 'suspended') throw unauthorized('account_suspended');
      return issueSession(existing);
    }

    const user = await db.transaction(async (tx) => {
      const [u] = await tx
        .insert(users)
        .values({
          displayName: identity.name,
          email: identity.email,
          isGuest: body.provider === 'guest',
          locale: body.locale,
        })
        .returning({ id: users.id, displayName: users.displayName, isGuest: users.isGuest });
      await tx.insert(authIdentities).values({ userId: u!.id, provider: body.provider, subject: identity.subject });
      return u!;
    });
    return issueSession(user);
  });

  /** Rotate refresh token (old one is revoked; reuse of a revoked token is rejected). */
  app.post('/refresh', async (req) => {
    const { refreshToken } = z.object({ refreshToken: z.string().min(20) }).parse(req.body);
    const now = app.ctx.now();
    const [row] = await db
      .select()
      .from(refreshTokens)
      .where(
        and(eq(refreshTokens.tokenHash, sha256(refreshToken)), isNull(refreshTokens.revokedAt), gt(refreshTokens.expiresAt, now)),
      );
    if (!row) throw unauthorized('invalid_refresh_token');
    await db.update(refreshTokens).set({ revokedAt: now }).where(eq(refreshTokens.id, row.id));
    const [u] = await db
      .select({ id: users.id, displayName: users.displayName, isGuest: users.isGuest, status: users.status })
      .from(users)
      .where(eq(users.id, row.userId));
    if (!u || u.status === 'suspended') throw unauthorized('account_suspended');
    return issueSession(u);
  });

  app.post('/sign-out', { preHandler: app.requireUser }, async (req, reply) => {
    await db
      .update(refreshTokens)
      .set({ revokedAt: app.ctx.now() })
      .where(and(eq(refreshTokens.userId, userId(req)), isNull(refreshTokens.revokedAt)));
    return reply.status(204).send();
  });
};
