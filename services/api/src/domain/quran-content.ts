/**
 * Pure mapping from Quran.com / Quran Foundation Content API v4 responses to our contracts
 * (spec §10): curated tafsir list, per-ayah timings, tafsir HTML → plain text.
 */
import type { Tafsir } from '@yaqeen/contracts';
import { QF_ATTRIBUTION } from '@yaqeen/contracts';

/** Curated tafsirs, in display order (Arabic Muyassar first). `qfId` = `/resources/tafsirs` id. */
export const TAFSIRS: readonly (Tafsir & { qfId: number })[] = [
  {
    id: 'muyassar',
    qfId: 16,
    nameAr: 'التفسير الميسر',
    nameEn: 'Al-Tafsir Al-Muyassar',
    language: 'ar',
    authorAr: 'مجمع الملك فهد لطباعة المصحف الشريف',
    authorEn: 'King Fahd Glorious Quran Printing Complex',
    source: 'qf',
    attribution: QF_ATTRIBUTION,
  },
  {
    id: 'ibn-kathir',
    qfId: 14,
    nameAr: 'تفسير ابن كثير',
    nameEn: 'Tafsir Ibn Kathir',
    language: 'ar',
    authorAr: 'الحافظ ابن كثير',
    authorEn: 'Hafiz Ibn Kathir',
    source: 'qf',
    attribution: QF_ATTRIBUTION,
  },
  {
    id: 'saadi',
    qfId: 91,
    nameAr: 'تفسير السعدي',
    nameEn: "Tafsir As-Sa'di",
    language: 'ar',
    authorAr: 'عبد الرحمن بن ناصر السعدي',
    authorEn: "Abdur-Rahman ibn Nasir As-Sa'di",
    source: 'qf',
    attribution: QF_ATTRIBUTION,
  },
  {
    id: 'ibn-kathir-en',
    qfId: 169,
    nameAr: 'تفسير ابن كثير (مختصر، بالإنجليزية)',
    nameEn: 'Ibn Kathir (Abridged, English)',
    language: 'en',
    authorAr: 'الحافظ ابن كثير',
    authorEn: 'Hafiz Ibn Kathir',
    source: 'qf',
    attribution: QF_ATTRIBUTION,
  },
];

export const tafsirById = (id: string) => TAFSIRS.find((t) => t.id === id);

/** Public shape (without the upstream id). */
export const publicTafsir = ({ qfId: _qf, ...t }: Tafsir & { qfId: number }): Tafsir => t;

/** Ayat per surah (Hafs), index 0 = surah 1 — validates `s:a` keys. */
export const AYAH_COUNTS = [
  7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30,
  73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30,
  52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9,
  5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
] as const;

/** `"s:a"` → [surah, ayah] when it names a real ayah, else null. */
export function parseAyahKey(key: string): [number, number] | null {
  const m = /^(\d{1,3}):(\d{1,3})$/.exec(key);
  if (!m) return null;
  const s = Number(m[1]);
  const a = Number(m[2]);
  if (s < 1 || s > 114 || a < 1 || a > AYAH_COUNTS[s - 1]!) return null;
  return [s, a];
}

export interface QfTimestamp {
  verse_key: string;
  timestamp_from: number;
  timestamp_to: number;
}

/**
 * QF verse timestamps → our `[startMs, endMs]` per ayah (index 0 = ayah 1), ordered by ayah and
 * deduplicated; legacy rows with `to < from` are clamped. Null when there are none.
 */
export function timingsFromQf(stamps: readonly QfTimestamp[] | null | undefined): [number, number][] | null {
  if (!stamps?.length) return null;
  const byAyah = new Map<number, [number, number]>();
  for (const t of stamps) {
    const ayah = Number(t.verse_key.split(':')[1]);
    if (!Number.isInteger(ayah) || ayah < 1 || byAyah.has(ayah)) continue;
    const from = Math.max(0, Math.round(t.timestamp_from));
    byAyah.set(ayah, [from, Math.max(from, Math.round(t.timestamp_to))]);
  }
  if (!byAyah.size) return null;
  return [...byAyah.entries()].sort((a, b) => a[0] - b[0]).map(([, span]) => span);
}

const NAMED: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', laquo: '«', raquo: '»', hellip: '…', ndash: '–', mdash: '—' };

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, body: string) => {
    if (body[0] === '#') {
      const code = body[1] === 'x' || body[1] === 'X' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '';
    }
    return NAMED[body.toLowerCase()] ?? whole;
  });
}

/**
 * Tafsir HTML → plain text: footnote markers (`<sup>`), scripts and styles are removed with their
 * content, block ends become paragraph breaks, every other tag is dropped, entities decoded,
 * whitespace collapsed. The words themselves are never changed.
 */
export function tafsirPlainText(html: string): string {
  return decodeEntities(
    html
      .replace(/<(sup|script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|h[1-6]|li|blockquote)\s*>/gi, '\n\n')
      .replace(/<\/?[a-z][^>]*>/gi, ''),
  )
    .replace(/[ \t ]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
