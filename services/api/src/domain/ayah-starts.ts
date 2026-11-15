/**
 * When each ayah of a recording begins, from its verified word timings: the web card lights the ayah
 * being recited (by number — the server holds no displayable Quran text, CLAUDE.md rule 9).
 */

export interface TimedWord {
  ayah: number;
  startMs: number;
}

/**
 * Start (ms) of every ayah from `fromAyah` to `toAyah`, in order and never decreasing; the first is 0
 * so a number is lit from the first second. An ayah the aligner found no word for starts where the
 * previous one did (it is skipped over, never lit out of order). `null` for a single ayah or without
 * timings: there is nothing to follow.
 */
export function ayahStarts(words: readonly TimedWord[] | null | undefined, fromAyah: number, toAyah: number): number[] | null {
  if (!words || words.length === 0 || toAyah <= fromAyah) return null;
  const first: (number | undefined)[] = [];
  for (const w of words) {
    if (!Number.isInteger(w.ayah) || w.ayah < fromAyah || w.ayah > toAyah || !Number.isFinite(w.startMs)) continue;
    const i = w.ayah - fromAyah;
    const at = Math.max(0, Math.round(w.startMs));
    if (first[i] === undefined || at < first[i]!) first[i] = at;
  }
  if (first.every((v) => v === undefined)) return null;
  const out: number[] = [];
  let prev = 0;
  for (let i = 0; i <= toAyah - fromAyah; i++) {
    const v = i === 0 ? 0 : Math.max(prev, first[i] ?? prev);
    out.push(v);
    prev = v;
  }
  return out;
}
