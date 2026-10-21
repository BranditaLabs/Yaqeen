import { SignJWT, jwtVerify } from 'jose';
import type { AdminRole } from '@yaqeen/contracts';

const ISSUER = 'yaqeen-api';
export const ACCESS_TTL_SEC = 15 * 60;
export const ADMIN_TTL_SEC = 8 * 60 * 60;
export const REFRESH_TTL_DAYS = 60;

export interface UserClaims {
  sub: string;
  guest: boolean;
}
export interface AdminClaims {
  sub: string;
  role: AdminRole;
}

const key = (secret: string) => new TextEncoder().encode(secret);

export async function signUserToken(claims: UserClaims, secret: string): Promise<string> {
  return new SignJWT({ guest: claims.guest })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(claims.sub)
    .setIssuer(ISSUER)
    .setAudience('app')
    .setIssuedAt()
    .setExpirationTime(`${ACCESS_TTL_SEC}s`)
    .sign(key(secret));
}

export async function verifyUserToken(token: string, secret: string): Promise<UserClaims> {
  const { payload } = await jwtVerify(token, key(secret), { issuer: ISSUER, audience: 'app' });
  return { sub: String(payload.sub), guest: Boolean(payload.guest) };
}

/** Admin tokens use a different secret AND audience so an app token can never reach /admin. */
export async function signAdminToken(claims: AdminClaims, secret: string): Promise<string> {
  return new SignJWT({ role: claims.role })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(claims.sub)
    .setIssuer(ISSUER)
    .setAudience('admin')
    .setIssuedAt()
    .setExpirationTime(`${ADMIN_TTL_SEC}s`)
    .sign(key(secret));
}

export async function verifyAdminToken(token: string, secret: string): Promise<AdminClaims> {
  const { payload } = await jwtVerify(token, key(secret), { issuer: ISSUER, audience: 'admin' });
  return { sub: String(payload.sub), role: payload.role as AdminRole };
}
