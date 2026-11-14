/**
 * Expected words for an ayah range, read from data/quran-words.txt (normalised matching keys built by
 * scripts/build-quran-words.ts from the app's bundled mushaf text; never displayed). Loaded once.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { AYAH_COUNTS } from './quran-content.js';
import type { ExpectedAyah } from './recitation-match.js';

/** A recording covers at most this many ayat (30 s rarely holds more than a few). */
export const MAX_RANGE_AYAT = 40;

/** Valid ayah range inside one surah. */
export function validRange(surah: number, fromAyah: number, toAyah: number): boolean {
  if (!Number.isInteger(surah) || surah < 1 || surah > 114) return false;
  const n = AYAH_COUNTS[surah - 1]!;
  return Number.isInteger(fromAyah) && Number.isInteger(toAyah) && fromAyah >= 1 && toAyah <= n && fromAyah <= toAyah && toAyah - fromAyah < MAX_RANGE_AYAT;
}

let lines: string[] | null = null;
let starts: number[] | null = null;

function load(): { lines: string[]; starts: number[] } {
  if (!lines || !starts) {
    const file = fileURLToPath(new URL('../../data/quran-words.txt', import.meta.url));
    lines = readFileSync(file, 'utf8')
      .replace(/\r\n/g, '\n')
      .split('\n')
      .filter((l) => l.length > 0 && !l.startsWith('#'));
    if (lines.length !== 6236) throw new Error(`quran-words.txt: expected 6236 ayat, got ${lines.length}`);
    starts = [];
    let acc = 0;
    for (const n of AYAH_COUNTS) {
      starts.push(acc);
      acc += n;
    }
  }
  return { lines, starts };
}

export function expectedAyat(surah: number, fromAyah: number, toAyah: number): ExpectedAyah[] {
  if (!validRange(surah, fromAyah, toAyah)) throw new Error('invalid range');
  const { lines: l, starts: s } = load();
  const out: ExpectedAyah[] = [];
  for (let a = fromAyah; a <= toAyah; a++) out.push({ ayah: a, text: l[s[surah - 1]! + a - 1]! });
  return out;
}
