/**
 * «تلاواتي» pure domain: the shared recitation-match vectors (packages/contracts/fixtures/recitation-match,
 * also run by the app), the expected-word list, the .m4a inspection and comment moderation.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { RECITATION_MATCH } from '@yaqeen/contracts';
import { checkComment, foldDigits, foldTokens, hasBlockedWord, hasLink, hasPhone, parseBlocklist } from '../src/domain/comments.js';
import { durations, inspectM4a, matchesRecordingFormat } from '../src/domain/m4a.js';
import { checkAudio } from '../src/services/recordings.service.js';
import { expectedAyat, validRange } from '../src/domain/quran-words.js';
import { align, matchRecitation, normalizeArabic, normWord, opening, sameWord, splitWords } from '../src/domain/recitation-match.js';
import { box, buildM4a, u32 } from './helpers/m4a.js';

const dir = new URL('../../../packages/contracts/fixtures/recitation-match/', import.meta.url);
const load = <T>(name: string): T => JSON.parse(readFileSync(fileURLToPath(new URL(name, dir)), 'utf8')) as T;

interface Case {
  name: string;
  surah: number;
  fromAyah: number;
  toAyah: number;
  expected: { ayah: number; text: string }[];
  heard: { text: string; startMs: number; endMs: number }[];
  durationMs: number;
  speechMs: number;
  result: ReturnType<typeof matchRecitation>;
}

describe('recitation match — shared vectors', () => {
  it('rules.json carries the contract thresholds', () => {
    expect(load<{ thresholds: unknown }>('rules.json').thresholds).toEqual(RECITATION_MATCH);
  });

  for (const v of load<{ input: string; output: string; keys: string[] }[]>('normalize.json')) {
    it(`normalize: ${v.input.slice(0, 24)}`, () => {
      expect(normalizeArabic(v.input)).toBe(v.output);
      expect(splitWords(v.input).map(normWord)).toEqual(v.keys);
    });
  }

  for (const v of load<{ a: string; b: string; same: boolean }[]>('same.json')) {
    it(`same(${v.a}, ${v.b}) = ${v.same}`, () => expect(sameWord(v.a, v.b)).toBe(v.same));
  }

  for (const v of load<{ note: string; heard: string[]; expected: string[]; drop: number; open: boolean }[]>('opening.json')) {
    it(`opening: ${v.note}`, () => expect(opening(v.heard, v.expected)).toEqual({ drop: v.drop, open: v.open }));
  }

  for (const c of load<Case[]>('cases.json')) {
    it(`case ${c.name} → ${c.result.verdict}`, () => {
      expect(matchRecitation({ expected: c.expected, heard: c.heard, durationMs: c.durationMs, speechMs: c.speechMs })).toEqual(c.result);
    });
    it(`case ${c.name}: the server word list gives the same verdict as the mushaf text`, () => {
      const fromList = matchRecitation({ expected: expectedAyat(c.surah, c.fromAyah, c.toAyah), heard: c.heard, durationMs: c.durationMs, speechMs: c.speechMs });
      expect(fromList).toEqual(c.result);
    });
  }
});

describe('recitation match — behaviour', () => {
  it('ties prefer «not heard» over «heard differently» when stopping early', () => {
    const expected = expectedAyat(112, 1, 1);
    const words = splitWords(expected[0]!.text);
    const r = align(expected, words.slice(0, 2));
    expect(r.map((w) => w.mark)).toEqual(['ok', 'ok', ...words.slice(2).map(() => 'skipped')]);
  });

  it('word timings map to {ayah, index}', () => {
    const r = matchRecitation({
      expected: expectedAyat(112, 1, 2),
      heard: [...splitWords(expectedAyat(112, 1, 2).map((a) => a.text).join(' '))].map((t, k) => ({ text: t, startMs: k * 500, endMs: k * 500 + 400 })),
      durationMs: 4000,
      speechMs: 3000,
    });
    expect(r.verdict).toBe('approve');
    expect(r.words[0]).toEqual({ ayah: 1, index: 0, startMs: 0, endMs: 400 });
    expect(r.words.at(-1)!.ayah).toBe(2);
  });

  it('empty expected never approves', () => {
    expect(matchRecitation({ expected: [], heard: [{ text: 'كلمة', startMs: 0, endMs: 1 }], durationMs: 1000, speechMs: 900 }).verdict).toBe('reject');
  });

  it('ranges are checked against the ayah counts', () => {
    expect(validRange(1, 1, 7)).toBe(true);
    expect(validRange(1, 1, 8)).toBe(false);
    expect(validRange(1, 3, 2)).toBe(false);
    expect(validRange(115, 1, 1)).toBe(false);
    expect(validRange(2, 1, 60)).toBe(false); // longer than MAX_RANGE_AYAT
    expect(expectedAyat(114, 6, 6)).toHaveLength(1);
  });
});

describe('m4a inspection', () => {
  it('reads duration, channels, rate and AAC-LC', () => {
    const info = inspectM4a(buildM4a({ durationMs: 12_345 }))!;
    expect(info).toEqual({ durationMs: 12_345, headerDurationMs: 12_345, frames: 193, channels: 1, sampleRate: 16_000, audioObjectType: 2 });
    expect(matchesRecordingFormat(info)).toBe(true);
    expect(durations(info, 250)).toEqual({ durationMs: 12_345, longestMs: 12_352, consistent: true });
  });
  it('the true length: a forged mdhd cannot pass a long clip as short', () => {
    // ~125 s of AAC frames and timing behind a header claiming 30 s.
    const forged = inspectM4a(buildM4a({ durationMs: 125_000, headerMs: 30_000, payload: 190_000 }))!;
    expect(forged.headerDurationMs).toBe(30_000);
    expect(forged.durationMs).toBe(125_000);
    expect(durations(forged, 250)).toMatchObject({ longestMs: 125_056, consistent: false }); // 1954 frames × 64 ms
    // Timing table forged short too: the frame count still tells.
    const frames = inspectM4a(buildM4a({ durationMs: 125_000, headerMs: 30_000, sttsMs: 30_000 }))!;
    expect(durations(frames, 250)).toMatchObject({ durationMs: 30_000, longestMs: 125_056, consistent: false });
    // Inconsistent but short (header says 10 s, the audio is 20 s).
    expect(durations(inspectM4a(buildM4a({ durationMs: 20_000, headerMs: 10_000 }))!, 250).consistent).toBe(false);
  });
  it('checkAudio refuses a forged length as too long, a self-contradicting file as bad format', () => {
    const code = (b: Buffer) => {
      try {
        checkAudio(b);
        return 'ok';
      } catch (e) {
        return (e as { code: string }).code;
      }
    };
    expect(code(buildM4a({ durationMs: 125_000, headerMs: 30_000, payload: 190_000 }))).toBe('recording_too_long');
    expect(code(buildM4a({ durationMs: 125_000, headerMs: 29_000, sttsMs: 29_000 }))).toBe('recording_too_long');
    expect(code(buildM4a({ durationMs: 20_000, headerMs: 10_000 }))).toBe('recording_bad_format');
    expect(code(buildM4a({ durationMs: 12_000, frames: 0, sttsMs: 0, headerMs: 0 }))).toBe('recording_bad_format');
    expect(code(buildM4a({ soundTracks: 2 }))).toBe('recording_bad_format');
    expect(code(buildM4a({ durationMs: 29_990 }))).toBe('ok');
    expect(checkAudio(buildM4a({ durationMs: 9_500 }))).toBe(9_500);
  });
  it('truncated or malformed boxes are null, never a throw', () => {
    // An mdhd cut short at the very end of the file (no mdat after it).
    const hdlr = box('hdlr', Buffer.alloc(4), u32(0), Buffer.from('soun', 'latin1'));
    const ftyp = box('ftyp', Buffer.from('M4A ', 'latin1'), u32(0));
    for (const mdhd of [box('mdhd', Buffer.from([0, 0, 0, 0]), u32(0)), box('mdhd', Buffer.from([1, 0, 0, 0]), Buffer.alloc(18))]) {
      const file = Buffer.concat([ftyp, box('moov', box('trak', box('mdia', hdlr, box('minf', box('stbl', box('stsd', Buffer.alloc(8)), box('stts', Buffer.alloc(8)), box('stsz', Buffer.alloc(12)))), mdhd)))]);
      expect(() => inspectM4a(file)).not.toThrow();
      expect(inspectM4a(file)).toBeNull();
      expect(() => checkAudio(file)).toThrow(expect.objectContaining({ code: 'recording_bad_format' }));
    }
    // A stts claiming more entries than it holds; an hdlr too short to name its type.
    const good = buildM4a();
    const at = good.indexOf(Buffer.from('stts', 'latin1'));
    const lying = Buffer.from(good);
    lying.writeUInt32BE(1_000_000, at + 8);
    expect(inspectM4a(lying)).toBeNull();
    const tiny = Buffer.concat([ftyp, box('moov', box('trak', box('mdia', box('hdlr', Buffer.alloc(2)))))]);
    expect(inspectM4a(tiny)).toBeNull();
  });
  it('64-bit mdhd', () => expect(inspectM4a(buildM4a({ durationMs: 31_500, v1: true }))!.durationMs).toBe(31_500));
  it('stereo, 44.1 kHz or HE-AAC are not the format', () => {
    expect(matchesRecordingFormat(inspectM4a(buildM4a({ channels: 2 }))!)).toBe(false);
    expect(matchesRecordingFormat(inspectM4a(buildM4a({ sampleRate: 44_100 }))!)).toBe(false);
    expect(matchesRecordingFormat(inspectM4a(buildM4a({ aot: 5 }))!)).toBe(false);
  });
  it('not an MPEG-4 file', () => {
    expect(inspectM4a(Buffer.from('ID3\u0004 not an m4a at all, just bytes'))).toBeNull();
    expect(inspectM4a(Buffer.alloc(0))).toBeNull();
    expect(inspectM4a(buildM4a().subarray(0, 40))).toBeNull();
  });
});

describe('comment moderation', () => {
  const list = parseBlocklist('# test\nshit\nكلب\nابن الكلب\n');

  it('accepts kind words and trims', () => {
    expect(checkComment('  ما شاء الله، تلاوة جميلة  ', list)).toEqual({ ok: true, text: 'ما شاء الله، تلاوة جميلة', mentions: [] });
    expect(checkComment('Beautiful, may Allah bless you @sara_1', list)).toMatchObject({ ok: true, mentions: ['sara_1'] });
  });
  it('length bounds', () => {
    expect(checkComment('a', list)).toEqual({ ok: false, problem: 'too_short' });
    expect(checkComment('ب'.repeat(281), list)).toEqual({ ok: false, problem: 'too_long' });
  });
  it('links and phone numbers', () => {
    for (const t of ['visit https://x.io', 'www.spam.example', 'go to spam.com now', 'spam dot com', 't.me/channel', 'wa.me/2010'])
      expect(hasLink(t), t).toBe(true);
    expect(hasLink('ما شاء الله. جميل')).toBe(false);
    for (const t of ['call 0100 123 4567', '+20-100-123-4567', 'رقمي ٠١٠٠١٢٣٤٥٦٧']) expect(hasPhone(t), t).toBe(true);
    expect(hasPhone('الآيات 1 إلى 5')).toBe(false);
    expect(checkComment('call 01001234567', list)).toEqual({ ok: false, problem: 'phone' });
  });
  it('blocklist through tashkeel, tatweel, repeats, leetspeak, spacing and prefixes', () => {
    for (const t of ['you are sh1t', 'SHIIIIT', 's h i t', 's.h.i.t', 'يا كَلْب', 'يا كـــلب', 'الكلب', 'والكلب', 'ابن الكلب'])
      expect(hasBlockedWord(t, list), t).toBe(true);
    for (const t of ['shirt', 'كلبشة', 'ما شاء الله']) expect(hasBlockedWord(t, list), t).toBe(false);
    expect(checkComment('انت كلب', list)).toEqual({ ok: false, problem: 'blocked_word' });
  });
  it('the shipped blocklist loads', () => {
    expect(checkComment('fuck this').ok).toBe(false);
    expect(checkComment('بارك الله فيك').ok).toBe(true);
  });
  it('control characters refuse; invisible ones are dropped', () => {
    expect(checkComment('hi\u0007there', list)).toEqual({ ok: false, problem: 'invalid_chars' });
    expect(checkComment('جم​يل', list)).toEqual({ ok: true, text: 'جميل', mentions: [] });
  });
  it('links: any label.tld, invisible splitters, fullwidth and Arabic dots', () => {
    for (const t of ['زوروا evil.de', 'x.top', 'y.biz', 'z.ai', 'promo.vip', 'evil\u00AD.com', 'evil\u2060.com', 'evil.\u180Ecom', 'ｅｖｉｌ．ｃｏｍ', 'evil۔com', 'spam . de', 'spam نقطة com'])
      expect(checkComment(t, list), JSON.stringify(t)).toEqual({ ok: false, problem: 'link' });
    for (const t of ['البقرة 2.255 جميلة', 'تلاوة 1.5 دقيقة', 'ما شاء الله. جميل', 'Well done. Beautiful', 'Surah 2:255', 'Well done. To you', 'Great . One more'])
      expect(checkComment(t, list), t).toMatchObject({ ok: true });
  });
  it('phones in any digit set (Extended Arabic-Indic, fullwidth, mixed) and through invisibles', () => {
    for (const t of ['رقمي ۰۱۰۰۱۲۳۴۵۶۷', 'call ０１００１２３４５６７', '٠١٠٠ 123 ۴۵۶۷', '0100\u00AD1234567'])
      expect(checkComment(t, list), JSON.stringify(t)).toEqual({ ok: false, problem: 'phone' });
    expect(foldDigits('۰۱۲۳۴۵۶۷۸۹ ٠١٢٣٤٥٦٧٨٩ ०१२ ０９ 𝟎𝟗𝟘')).toBe('0123456789 0123456789 012 09 090');
  });
  it('blocked words split by a soft hyphen or word joiner', () => {
    expect(checkComment('انت كل\u00ADب', list)).toEqual({ ok: false, problem: 'blocked_word' });
    expect(checkComment('sh\u2060it', list)).toEqual({ ok: false, problem: 'blocked_word' });
  });
  it('folds tokens', () => expect(foldTokens('Sh1iiT ـ الـلـه')).toEqual(['shit', 'الله']));
});
