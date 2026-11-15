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
 * so a number is lit from the first second. The player lights the LAST ayah whose start has passed, so
 * an ayah the aligner found no word for (e.g. a one-word muqatta'at the ASR missed) takes the start of
 * the next ayah that has one: it gets zero lit time and is passed over, and the ayah actually being
 * recited stays lit. A start later than a following ayah's (an aligner glitch) is pulled back the same
 * way, so the highlight never runs ahead of a known start or goes backwards. `null` when there is
 * nothing to follow: a single ayah, no timings, or no word in the last ayah (its start is unknowable,
 * and inventing one would light it out of turn).
 */
export function ayahStarts(words: readonly TimedWord[] | null | undefined, fromAyah: number, toAyah: number): number[] | null {
  if (!words || words.length === 0 || toAyah <= fromAyah) return null;
  const n = toAyah - fromAyah + 1;
  const first: (number | undefined)[] = new Array(n).fill(undefined);
  for (const w of words) {
    if (!Number.isInteger(w.ayah) || w.ayah < fromAyah || w.ayah > toAyah || !Number.isFinite(w.startMs)) continue;
    const i = w.ayah - fromAyah;
    const at = Math.max(0, Math.round(w.startMs));
    if (first[i] === undefined || at < first[i]!) first[i] = at;
  }
  const last = first[n - 1];
  if (last === undefined) return null;
  const out: number[] = new Array(n);
  out[n - 1] = last;
  for (let i = n - 2; i >= 0; i--) out[i] = Math.min(out[i + 1]!, first[i] ?? out[i + 1]!);
  out[0] = 0;
  return out;
}
