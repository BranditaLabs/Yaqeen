import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export type Fixture = { email: string; password: string; totpSecret: string; handle: string; tagCode: string };

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
