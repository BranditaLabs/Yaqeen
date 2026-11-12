import { describe, expect, it } from 'vitest';
import { randomBytes } from 'node:crypto';
import {
  base32Decode,
  base32Encode,
  hashPassword,
  isSealed,
  maskEmail,
  openSecret,
  sealSecret,
  secretsKey,
  totp,
  verifyPassword,
  verifyTotp,
} from '../src/lib/crypto.js';
import { buildDiscountRequest, generateCode } from '../src/domain/shopify.js';

describe('sealed admin secrets', () => {
  const key = secretsKey(randomBytes(32).toString('base64'));
  it('round-trips, never stores the plain value, and detects tampering', () => {
    const sealed = sealSecret('JBSWY3DPEHPK3PXP', key);
    expect(isSealed(sealed)).toBe(true);
    expect(sealed).not.toContain('JBSWY3DPEHPK3PXP');
    expect(sealSecret('JBSWY3DPEHPK3PXP', key)).not.toBe(sealed); // fresh IV each time
    expect(openSecret(sealed, key)).toBe('JBSWY3DPEHPK3PXP');
    const tampered = sealed.slice(0, -2) + (sealed.endsWith('A') ? 'BB' : 'AA');
    expect(() => openSecret(tampered, key)).toThrow();
    expect(() => openSecret(sealed, secretsKey(randomBytes(32).toString('base64')))).toThrow();
  });
  it('reads legacy plain values; refuses sealed ones without the key; checks key length', () => {
    expect(openSecret('JBSWY3DPEHPK3PXP', key)).toBe('JBSWY3DPEHPK3PXP');
    expect(sealSecret('x', null)).toBe('x');
    expect(() => openSecret(sealSecret('x', key), null)).toThrow(/ADMIN_SECRETS_KEY/);
    expect(() => secretsKey(Buffer.from('short').toString('base64'))).toThrow(/32 bytes/);
  });
});

describe('TOTP (RFC 6238 test vectors, SHA1)', () => {
  const secret = Buffer.from('12345678901234567890');
  it.each([
    [59, '287082'],
    [1111111109, '081804'],
    [1234567890, '005924'],
    [2000000000, '279037'],
  ])('t=%i → %s', (t, code) => {
    expect(totp(secret, t * 1000)).toBe(code);
  });
  it('verifies with ±1 step drift', () => {
    const b32 = base32Encode(secret);
    expect(base32Decode(b32).equals(secret)).toBe(true);
    expect(verifyTotp(b32, '287082', 59_000 + 30_000)).toBe(true);
    expect(verifyTotp(b32, '287082', 59_000 + 120_000)).toBe(false);
  });
});

describe('passwords', () => {
  it('hashes and verifies', async () => {
    const h = await hashPassword('correct horse battery');
    expect(await verifyPassword('correct horse battery', h)).toBe(true);
    expect(await verifyPassword('wrong password!!', h)).toBe(false);
  });
});

describe('maskEmail', () => {
  it('masks the local part', () => {
    expect(maskEmail('ahmed@example.com')).toBe('a***@example.com');
    expect(maskEmail(null)).toBeNull();
  });
});

describe('shopify discount builder', () => {
  const dates = { startsAt: new Date('2026-10-20T00:00:00Z'), endsAt: new Date('2026-11-19T00:00:00Z') };
  it('codes are readable and well-formed', () => {
    expect(generateCode()).toMatch(/^YQ-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
  });
  it('fixed amount → basic discount, all items', () => {
    const r = buildDiscountRequest({ code: 'YQ-AAAA-BBBB', title: 't', kind: 'fixed_amount', value: 50, collectionIds: [], ...dates });
    expect(r.resultKey).toBe('discountCodeBasicCreate');
    expect(r.variables).toMatchObject({
      basicCodeDiscount: {
        usageLimit: 1,
        customerGets: { value: { discountAmount: { amount: '50.00' } }, items: { all: true } },
      },
    });
  });
  it('percentage on prayer-rug collection', () => {
    const r = buildDiscountRequest({
      code: 'YQ-AAAA-BBBB',
      title: 't',
      kind: 'percentage',
      value: 15,
      collectionIds: ['gid://shopify/Collection/1'],
      ...dates,
    });
    expect(r.variables).toMatchObject({
      basicCodeDiscount: {
        customerGets: { value: { percentage: 0.15 }, items: { collections: { add: ['gid://shopify/Collection/1'] } } },
      },
    });
  });
  it('free shipping', () => {
    const r = buildDiscountRequest({ code: 'YQ-AAAA-BBBB', title: 't', kind: 'free_shipping', value: 0, collectionIds: [], ...dates });
    expect(r.resultKey).toBe('discountCodeFreeShippingCreate');
  });
});
