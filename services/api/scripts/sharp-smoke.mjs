#!/usr/bin/env node
/**
 * sharp container smoke test (design §4.3): proves the prebuilt libvips binary loads inside the
 * production image (node:22-alpine / linuxmusl, built with `pnpm deploy`) and that the avatar
 * pipeline decodes a JPEG with EXIF GPS, re-encodes it to 256/96-px WebP and drops the metadata.
 *
 *   node scripts/sharp-smoke.mjs [fixture.jpg]       (CI runs it inside the built API image)
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = process.argv[2] ?? join(here, '..', 'test', 'fixtures', 'avatar', 'gps.jpg');
const input = readFileSync(fixture);
const fail = (msg) => {
  console.error(`[sharp-smoke] FAIL: ${msg}`);
  process.exit(1);
};

const before = await sharp(input).metadata();
if (!before.exif) fail('the fixture has no EXIF block to strip');
for (const px of [256, 96]) {
  const out = await sharp(input, { limitInputPixels: 40_000_000, failOn: 'error' })
    .rotate()
    .resize(px, px, { fit: 'cover', position: 'attention' })
    .webp({ quality: 80 })
    .toBuffer();
  const meta = await sharp(out).metadata();
  if (meta.format !== 'webp') fail(`expected webp, got ${meta.format}`);
  if (meta.width !== px || meta.height !== px) fail(`expected ${px}x${px}, got ${meta.width}x${meta.height}`);
  if (meta.exif !== undefined) fail('EXIF survived re-encoding');
}
console.log(`[sharp-smoke] ok — sharp ${sharp.versions.sharp}, libvips ${sharp.versions.vips}, ${process.platform}/${process.arch}`);
process.exit(0);
