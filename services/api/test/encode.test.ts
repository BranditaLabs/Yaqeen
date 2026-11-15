import { describe, expect, it } from 'vitest';
import { ENCODE_TOKEN, EncodeWrittenRequest } from '@yaqeen/contracts';
import { encodeDeepLink, hashEncodeToken, newEncodeToken, redactEncodeToken } from '../src/services/tag-encoding.service.js';

describe('staff encoding tokens', () => {
  it('are 32 random bytes in base64url, distinct each time, stored only as SHA-256', () => {
    const a = newEncodeToken();
    const b = newEncodeToken();
    expect(a).toMatch(ENCODE_TOKEN);
    expect(Buffer.from(a, 'base64url')).toHaveLength(32);
    expect(a).not.toBe(b);
    expect(hashEncodeToken(a)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashEncodeToken(a)).toBe(hashEncodeToken(a));
    expect(encodeDeepLink(a)).toBe(`yaqeen://encode/${a}`);
  });

  it('never reach request logs', () => {
    expect(redactEncodeToken('/v1/encode/abcDEF_-123/written')).toBe('/v1/encode/[token]/written');
    expect(redactEncodeToken('/v1/encode/abc?x=1')).toBe('/v1/encode/[token]?x=1');
    expect(redactEncodeToken('/v1/me/tags')).toBe('/v1/me/tags');
  });

  it('a written report takes a real code, an optional hex UID and the lock flag', () => {
    expect(EncodeWrittenRequest.parse({ code: 'ab23-cd45', uid: '04a1ff', locked: false })).toEqual({ code: 'AB23CD45', uid: '04A1FF', locked: false });
    expect(EncodeWrittenRequest.safeParse({ code: 'AB23CD45' }).success).toBe(false);
    expect(EncodeWrittenRequest.safeParse({ code: 'AB23CD45', uid: 'xyz', locked: true }).success).toBe(false);
    expect(EncodeWrittenRequest.safeParse({ code: 'O0I1O0I1', locked: true }).success).toBe(false);
  });
});
