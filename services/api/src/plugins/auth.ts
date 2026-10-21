import type { FastifyInstance, FastifyRequest, preHandlerHookHandler } from 'fastify';
import fp from 'fastify-plugin';
import type { AdminRole } from '@yaqeen/contracts';
import { forbidden, unauthorized } from '../lib/errors.js';
import { type AdminClaims, type UserClaims, verifyAdminToken, verifyUserToken } from '../lib/tokens.js';

declare module 'fastify' {
  interface FastifyRequest {
    user?: UserClaims;
    admin?: AdminClaims;
  }
  interface FastifyInstance {
    requireUser: preHandlerHookHandler;
    /** Allow only the listed roles. super_admin is always allowed. */
    requireAdmin: (roles: AdminRole[]) => preHandlerHookHandler;
  }
}

function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization;
  if (h?.startsWith('Bearer ')) return h.slice(7);
  // Admin dashboard (Next.js) forwards an httpOnly cookie as a header from the server side.
  const c = req.headers['x-admin-session'];
  return typeof c === 'string' ? c : null;
}

export const authPlugin = fp(async (app: FastifyInstance, opts: { jwtSecret: string; adminJwtSecret: string }) => {
  app.decorate('requireUser', async (req: FastifyRequest) => {
    const token = bearer(req);
    if (!token) throw unauthorized();
    try {
      req.user = await verifyUserToken(token, opts.jwtSecret);
    } catch {
      throw unauthorized('invalid_token');
    }
  });

  app.decorate('requireAdmin', (roles: AdminRole[]) => async (req: FastifyRequest) => {
    const token = bearer(req);
    if (!token) throw unauthorized();
    let claims: AdminClaims;
    try {
      claims = await verifyAdminToken(token, opts.adminJwtSecret);
    } catch {
      throw unauthorized('invalid_token');
    }
    if (claims.role !== 'super_admin' && !roles.includes(claims.role)) throw forbidden('role_not_allowed');
    req.admin = claims;
  });
});

/** Narrowing helpers for handlers behind requireUser / requireAdmin. */
export function userId(req: FastifyRequest): string {
  if (!req.user) throw unauthorized();
  return req.user.sub;
}
export function adminOf(req: FastifyRequest): AdminClaims {
  if (!req.admin) throw unauthorized();
  return req.admin;
}
