/**
 * Verify Google and Apple ID tokens against their published JWKS.
 * (jose caches the key set and refreshes it on unknown `kid`.)
 */
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { unauthorized } from '../lib/errors.js';

const GOOGLE_JWKS = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const APPLE_JWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export interface VerifiedIdentity {
  subject: string;
  email: string | null;
  name: string | null;
}

export async function verifyGoogleIdToken(idToken: string, audiences: string[]): Promise<VerifiedIdentity> {
  if (audiences.length === 0) throw unauthorized('google_not_configured');
  try {
    const { payload } = await jwtVerify(idToken, GOOGLE_JWKS, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: audiences,
    });
    return {
      subject: String(payload.sub),
      email: payload.email_verified ? String(payload.email ?? '') || null : null,
      name: typeof payload.name === 'string' ? payload.name : null,
    };
  } catch {
    throw unauthorized('invalid_google_token');
  }
}

export async function verifyAppleIdToken(idToken: string, audiences: string[]): Promise<VerifiedIdentity> {
  if (audiences.length === 0) throw unauthorized('apple_not_configured');
  try {
    const { payload } = await jwtVerify(idToken, APPLE_JWKS, {
      issuer: 'https://appleid.apple.com',
      audience: audiences,
    });
    // Apple only sends the name on first sign-in, via the client — never in the token.
    return { subject: String(payload.sub), email: typeof payload.email === 'string' ? payload.email : null, name: null };
  } catch {
    throw unauthorized('invalid_apple_token');
  }
}
