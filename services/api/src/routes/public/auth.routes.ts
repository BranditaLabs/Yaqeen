import { randomUUID } from 'node:crypto';
import { and, eq, gt, isNull, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { LinkRequest, SignInRequest, type SessionResponse } from '@yaqeen/contracts';
import { auditLog, authIdentities, pointsLedger, refreshTokens, users } from '../../db/schema.js';
import { verifyAppleIdToken, verifyGoogleIdToken } from '../../integrations/oidc.js';
import { badRequest, conflict, unauthorized } from '../../lib/errors.js';
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

  const verify = (provider: 'google' | 'apple', idToken: string) =>
    provider === 'google' ? verifyGoogleIdToken(idToken, env.GOOGLE_CLIENT_IDS) : verifyAppleIdToken(idToken, env.APPLE_CLIENT_IDS);

  /** Sign in with Google / Apple, or start as a guest (guest can be upgraded later via /link). */
  app.post('/sign-in', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req) => {
    const body = SignInRequest.parse(req.body);
    let identity: { subject: string; email: string | null; name: string | null };
    if (body.provider === 'guest') {
      identity = { subject: randomUUID(), email: null, name: body.displayName ?? null };
    } else {
      if (!body.idToken) throw badRequest('id_token_required');
      identity = await verify(body.provider, body.idToken);
      identity.name ??= body.displayName ?? null;
    }

    const [existing] = await db
      .select({ id: users.id, displayName: users.displayName, isGuest: users.isGuest, status: users.status })
      .from(authIdentities)
      .innerJoin(users, eq(users.id, authIdentities.userId))
      .where(and(eq(authIdentities.provider, body.provider), eq(authIdentities.subject, identity.subject)));

    if (existing) {
      if (existing.status === 'suspended' || existing.status === 'deleted') throw unauthorized('account_suspended');
      if (existing.status === 'deletion_requested') {
        // Signing in again within the grace period cancels the erasure request.
        await db.update(users).set({ status: 'active', deletionRequestedAt: null, updatedAt: app.ctx.now() }).where(eq(users.id, existing.id));
      }
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

  /**
   * Link the signed-in guest to a Google/Apple identity, keeping the guest's points.
   *  - New identity → the guest account itself becomes the real account (same user id).
   *  - Identity already has an account → keep that account; the guest's balance moves over
   *    as two ledger rows (out of the guest, into the account) — never by editing a balance.
   * Both cases run in one transaction with an audit row (actor = the user).
   */
  app.post('/link', { preHandler: app.requireUser, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req) => {
    const body = LinkRequest.parse(req.body);
    const guestId = userId(req);
    const [guest] = await db.select().from(users).where(eq(users.id, guestId));
    if (!guest) throw unauthorized();
    if (!guest.isGuest) throw conflict('not_a_guest');
    const identity = await verify(body.provider, body.idToken);
    const name = identity.name ?? body.displayName ?? guest.displayName;

    const target = await db.transaction(async (tx) => {
      await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${guestId}))`);
      const [existing] = await tx
        .select({ id: users.id, displayName: users.displayName, isGuest: users.isGuest, status: users.status })
        .from(authIdentities)
        .innerJoin(users, eq(users.id, authIdentities.userId))
        .where(and(eq(authIdentities.provider, body.provider), eq(authIdentities.subject, identity.subject)));

      if (!existing) {
        await tx.insert(authIdentities).values({ userId: guestId, provider: body.provider, subject: identity.subject });
        const [u] = await tx
          .update(users)
          .set({ isGuest: false, email: identity.email, displayName: name, updatedAt: app.ctx.now() })
          .where(eq(users.id, guestId))
          .returning({ id: users.id, displayName: users.displayName, isGuest: users.isGuest });
        await tx.insert(auditLog).values({ actorUserId: guestId, action: 'auth.link', targetType: 'user', targetId: guestId, after: { provider: body.provider, merged: false }, ip: req.ip });
        return u!;
      }

      if (existing.status === 'suspended' || existing.status === 'deleted') throw unauthorized('account_suspended');
      const [b] = await tx
        .select({ total: sql<string>`coalesce(sum(${pointsLedger.delta}), 0)` })
        .from(pointsLedger)
        .where(eq(pointsLedger.userId, guestId));
      const points = Number(b?.total ?? 0);
      if (points > 0) {
        await tx.insert(pointsLedger).values([
          { userId: guestId, delta: -points, reason: 'reversal', refKey: `merge-out:${existing.id}`, note: 'Merged into account' },
          { userId: existing.id, delta: points, reason: 'grant', refKey: `merge:${guestId}`, note: 'Points from guest session' },
        ]);
      }
      await tx.update(users).set({ mergedInto: existing.id, updatedAt: app.ctx.now() }).where(eq(users.id, guestId));
      await tx.update(refreshTokens).set({ revokedAt: app.ctx.now() }).where(and(eq(refreshTokens.userId, guestId), isNull(refreshTokens.revokedAt)));
      await tx.insert(auditLog).values({ actorUserId: guestId, action: 'auth.link', targetType: 'user', targetId: existing.id, after: { provider: body.provider, merged: true, points }, ip: req.ip });
      return { id: existing.id, displayName: existing.displayName, isGuest: existing.isGuest };
    });
    return issueSession(target);
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
    if (!u || u.status === 'suspended' || u.status === 'deleted') throw unauthorized('account_suspended');
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
