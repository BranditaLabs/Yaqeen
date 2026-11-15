import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

type Member = { id: string; handle: string; name: string; photoId?: string };

export type Fixture = {
  email: string;
  password: string;
  totpSecret: string;
  handle: string;
  tagCode: string;
  /** Cairo calendar day the database was prepared on. */
  today: string;
  /** Session tokens for staff in the other roles (the super admin signs in through the form). */
  tokens: { marketing: string; support: string; content_editor: string };
  /** Opted in, attested, preset m03, in the tournament, the league group and the level board. */
  runner: Member;
  /** Support removed this member's photo a day ago. */
  removed: Member & { photoId: string };
  /** Published card with an active, attested photo and an open report. */
  pictured: Member & { photoId: string };
  tournamentId: string;
  groupId: string;
  /** «التلاوات»: a flagged recording, a held one, a hidden comment, and a religious reviewer's session. */
  recitations: { flagged: string; held: string; comment: string; reviewerToken: string };
  /** A published card with two public, approved recordings (word timings, 1.6 s each) — `recordings` on. */
  cardRecitations: { handle: string; first: string; second: string };
};

export const ADMIN_URL = `http://localhost:${process.env.E2E_ADMIN_PORT ?? '3100'}`;
export const API_URL = `http://localhost:${process.env.E2E_API_PORT ?? '4100'}`;

/** A browser context signed in as another staff role (cookie as the login action sets it). */
export async function staffContext(browser: import('@playwright/test').Browser, token: string) {
  const context = await browser.newContext({ baseURL: ADMIN_URL, locale: 'ar-EG' });
  await context.addCookies([{ name: 'yq_admin', value: token, url: ADMIN_URL, httpOnly: true, sameSite: 'Strict' }]);
  return context;
}

export const fixture = (): Fixture => JSON.parse(readFileSync(join(import.meta.dirname, '..', '.auth', 'fixture.json'), 'utf8')) as Fixture;

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** RFC 6238 code (SHA-1, 30 s, 6 digits) — what an authenticator app would show. */
export function totp(secretB32: string, nowMs = Date.now()): string {
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const ch of secretB32.replace(/=+$/, '')) {
    value = (value << 5) | B32.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(nowMs / 30_000)));
  const h = createHmac('sha1', Buffer.from(bytes)).update(counter).digest();
  const o = h[h.length - 1]! & 15;
  const n = ((h[o]! & 127) << 24) | (h[o + 1]! << 16) | (h[o + 2]! << 8) | h[o + 3]!;
  return String(n % 1_000_000).padStart(6, '0');
}
