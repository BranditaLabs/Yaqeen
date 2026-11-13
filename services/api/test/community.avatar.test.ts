/**
 * The photo pipeline without a database (design §5): magic bytes, re-encoding to 256/96-px WebP with
 * every bit of metadata (EXIF incl. GPS) dropped, the 128-px minimum and unreadable input → 422.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { processPhoto, sniffMime } from '../src/services/avatar.service.js';
import { AVATAR_WEBP } from '../src/web/avatar-assets.js';
import { avatarImg } from '../src/web/profile-page.js';

const fixture = (name: string) => readFileSync(fileURLToPath(new URL(`./fixtures/avatar/${name}`, import.meta.url)));

describe('avatar photos', () => {
  it('sniffs JPEG, PNG and WebP by their magic bytes', async () => {
    expect(sniffMime(fixture('gps.jpg'))).toBe('image/jpeg');
    expect(sniffMime(fixture('photo.png'))).toBe('image/png');
    expect(sniffMime(Buffer.from(AVATAR_WEBP.m01!, 'base64'))).toBe('image/webp');
    expect(sniffMime(Buffer.from('GIF89a......'))).toBeNull();
    expect(sniffMime(Buffer.alloc(0))).toBeNull();
  });

  it('re-encodes to square WebP and strips EXIF (the fixture carries GPS)', async () => {
    const input = fixture('gps.jpg');
    const before = await sharp(input).metadata();
    expect(before.exif).toBeDefined();
    expect(before.exif!.toString('latin1')).toContain('YaqeenTestCam');
    const { large, small } = await processPhoto(input);
    for (const [buf, px] of [[large, 256], [small, 96]] as const) {
      const m = await sharp(buf).metadata();
      expect(m.format).toBe('webp');
      expect([m.width, m.height]).toEqual([px, px]);
      expect(m.exif).toBeUndefined();
      expect(m.icc).toBeUndefined();
      expect(m.xmp).toBeUndefined();
      expect(buf.toString('latin1')).not.toContain('YaqeenTestCam');
    }
  });

  it('accepts PNG; refuses tiny pictures and garbage with photo_unreadable (422)', async () => {
    await expect(processPhoto(fixture('photo.png'))).resolves.toBeTruthy();
    await expect(processPhoto(fixture('tiny.jpg'))).rejects.toMatchObject({ status: 422, code: 'photo_unreadable' });
    const truncated = fixture('gps.jpg').subarray(0, 200);
    await expect(processPhoto(truncated)).rejects.toMatchObject({ status: 422, code: 'photo_unreadable' });
    await expect(processPhoto(Buffer.from('not an image at all'))).rejects.toMatchObject({ status: 422, code: 'photo_unreadable' });
  });

  it('embeds all 16 presets as 256-px WebP', async () => {
    expect(Object.keys(AVATAR_WEBP).sort()).toEqual(['f01', 'f02', 'f03', 'f04', 'f05', 'f06', 'f07', 'f08', 'm01', 'm02', 'm03', 'm04', 'm05', 'm06', 'm07', 'm08']);
    const m = await sharp(Buffer.from(AVATAR_WEBP.f05!, 'base64')).metadata();
    expect([m.format, m.width, m.height]).toEqual(['webp', 256, 256]);
  });

  it('the public card page draws only a vetted avatar inside the ring', () => {
    expect(avatarImg({ kind: 'preset', id: 'm03' }, 'x')).toContain('/u/assets/avatars/m03.webp');
    expect(avatarImg({ kind: 'initial' }, 'x')).toBeNull();
    expect(avatarImg(undefined, 'x')).toBeNull();
    const id = '00000000-0000-4000-8000-000000000000';
    expect(avatarImg({ kind: 'photo', id, url: 'https://id.test/v1/public/avatars/x/256.webp', smallUrl: 's' }, 'x')).toContain('https://id.test/v1/public/avatars/x/256.webp');
    expect(avatarImg({ kind: 'photo', id, url: 'javascript:alert(1)', smallUrl: 's' }, 'x')).toBeNull();
  });
});
