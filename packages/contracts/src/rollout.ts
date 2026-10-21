/**
 * Stable percentage rollout: the same user always lands in the same bucket for a flag.
 * FNV-1a (32-bit) over `${flag}:${userId}`, mod 100. Mirrored in the app
 * (apps/mobile/lib/core/config/rollout.dart) — keep the test vectors in sync.
 */
export function rolloutBucket(userId: string, flag: string): number {
  let h = 0x811c9dc5;
  for (const b of utf8(`${flag}:${userId}`)) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h % 100;
}

export function inRollout(userId: string | null, flag: string, percent: number | undefined): boolean {
  if (percent === undefined || percent >= 100) return true;
  if (percent <= 0 || !userId) return false;
  return rolloutBucket(userId, flag) < percent;
}

function utf8(s: string): number[] {
  const out: number[] = [];
  for (const ch of s) {
    const c = ch.codePointAt(0)!;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return out;
}
