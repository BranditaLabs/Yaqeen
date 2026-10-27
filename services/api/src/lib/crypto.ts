import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb) as (pw: string, salt: Buffer, keylen: number, opts: object) => Promise<Buffer>;

/* -------------------------------------------------------------- passwords */

const N = 16384;
const R = 8;
const P = 1;
const KEYLEN = 64;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await scrypt(password, salt, KEYLEN, { N, r: R, p: P });
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64')}$${hash.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algo, n, r, p, saltB64, hashB64] = stored.split('$');
  if (algo !== 'scrypt' || !saltB64 || !hashB64) return false;
  const expected = Buffer.from(hashB64, 'base64');
  const actual = await scrypt(password, Buffer.from(saltB64, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
  });
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/* ------------------------------------------------------------------- TOTP */

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(buf: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(input: string): Buffer {
  const clean = input.replace(/=+$/, '').replace(/\s/g, '').toUpperCase();
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = B32.indexOf(ch);
    if (idx < 0) throw new Error('Invalid base32');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export function generateTotpSecret(): string {
  return base32Encode(randomBytes(20));
}

/** RFC 6238 TOTP (HMAC-SHA1, 30 s step, 6 digits). */
export function totp(secret: Buffer, timeMs: number, step = 30, digits = 6): string {
  const counter = Math.floor(timeMs / 1000 / step);
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const h = createHmac('sha1', secret).update(msg).digest();
  const offset = h[h.length - 1]! & 0xf;
  const bin =
    ((h[offset]! & 0x7f) << 24) | ((h[offset + 1]! & 0xff) << 16) | ((h[offset + 2]! & 0xff) << 8) | (h[offset + 3]! & 0xff);
  return String(bin % 10 ** digits).padStart(digits, '0');
}

/** Accepts the current step and ±1 step for clock drift. */
export function verifyTotp(secretB32: string, code: string, nowMs = Date.now()): boolean {
  const secret = base32Decode(secretB32);
  for (const drift of [-1, 0, 1]) {
    const expected = totp(secret, nowMs + drift * 30_000);
    if (expected.length === code.length && timingSafeEqual(Buffer.from(expected), Buffer.from(code))) return true;
  }
  return false;
}

/* --------------------------------------------------------- sealed secrets */

const SEAL_PREFIX = 'enc:v1:';

/** The 32-byte key from ADMIN_SECRETS_KEY (base64), or null when unset (dev/test only). */
export function secretsKey(b64: string): Buffer | null {
  if (!b64) return null;
  const key = Buffer.from(b64, 'base64');
  if (key.length !== 32) throw new Error('ADMIN_SECRETS_KEY must be 32 bytes, base64-encoded');
  return key;
}

/** AES-256-GCM: "enc:v1:<iv>.<tag>.<ciphertext>" (base64url). Without a key the value stays as is. */
export function sealSecret(plain: string, key: Buffer | null): string {
  if (!key) return plain;
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return `${SEAL_PREFIX}${iv.toString('base64url')}.${c.getAuthTag().toString('base64url')}.${ct.toString('base64url')}`;
}

export const isSealed = (stored: string) => stored.startsWith(SEAL_PREFIX);

/** Opens a sealed value; a legacy plain value (written before the key existed) is returned as is. */
export function openSecret(stored: string, key: Buffer | null): string {
  if (!isSealed(stored)) return stored;
  if (!key) throw new Error('ADMIN_SECRETS_KEY is required to read sealed secrets');
  const [iv, tag, ct] = stored.slice(SEAL_PREFIX.length).split('.');
  const d = createDecipheriv('aes-256-gcm', key, Buffer.from(iv ?? '', 'base64url'));
  d.setAuthTag(Buffer.from(tag ?? '', 'base64url'));
  return Buffer.concat([d.update(Buffer.from(ct ?? '', 'base64url')), d.final()]).toString('utf8');
}

/* ---------------------------------------------------------------- tokens */

export function opaqueToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

export function sha256(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/** user@example.com → u***@example.com (admin tables never show full emails). */
export function maskEmail(email: string | null): string | null {
  if (!email) return null;
  const [local, domain] = email.split('@');
  if (!local || !domain) return '***';
  return `${local[0]}***@${domain}`;
}
