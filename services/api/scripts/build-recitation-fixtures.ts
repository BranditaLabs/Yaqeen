/**
 * Builds the shared recitation-match test vectors in packages/contracts/fixtures/recitation-match/.
 * The API test (test/recitation-match.test.ts) and the app test
 * (apps/mobile/test/features/recitation_match_fixtures_test.dart) both run these files.
 *
 * Verse text is copied verbatim from the app's bundled mushaf (apps/mobile/assets/quran/quran.json);
 * the "heard" side is derived from it the way a recogniser writes it (tashkeel stripped), then words
 * are dropped, changed or repeated per case. Nothing is typed by hand. Each case states the verdict it
 * was designed for, and the script refuses to write if the matcher disagrees.
 *
 *   pnpm --filter @yaqeen/api exec tsx scripts/build-recitation-fixtures.ts           # write
 *   pnpm --filter @yaqeen/api exec tsx scripts/build-recitation-fixtures.ts --check   # fail on drift
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { RECITATION_MATCH, type MatchVerdict } from '@yaqeen/contracts';
import { type ExpectedAyah, type HeardWord, matchRecitation, normalizeArabic, normWord, opening, sameWord, splitWords } from '../src/domain/recitation-match.js';

const quran = JSON.parse(readFileSync(fileURLToPath(new URL('../../../apps/mobile/assets/quran/quran.json', import.meta.url)), 'utf8')) as {
  ayat: string[][];
};
const outDir = fileURLToPath(new URL('../../../packages/contracts/fixtures/recitation-match/', import.meta.url));

const text = (s: number, a: number) => quran.ayat[s - 1]![a - 1]!;
const ayat = (s: number, from: number, to: number): ExpectedAyah[] => Array.from({ length: to - from + 1 }, (_, k) => ({ ayah: from + k, text: text(s, from + k) }));
/** What a recogniser writes: everyday spelling (dagger alef as a full alef), no tashkeel or Quranic marks. */
const strip = (w: string) => w.replaceAll(String.fromCharCode(0x0670), 'ا').replace(/[ؐ-ًؚ-ٰٟۖ-ۭ]/g, '');
const heardOf = (s: number, from: number, to: number) => ayat(s, from, to).flatMap((a) => splitWords(a.text).map(strip));
/** 420 ms per word with a 60 ms gap, starting at `startMs`. */
const timed = (words: string[], startMs = 300): HeardWord[] => words.map((w, k) => ({ text: w, startMs: startMs + k * 480, endMs: startMs + k * 480 + 420 }));

interface CaseDef {
  name: string;
  note: string;
  surah: number;
  fromAyah: number;
  toAyah: number;
  heard: HeardWord[];
  durationMs: number;
  speechMs: number;
  designed: MatchVerdict;
}

const ikhlas = heardOf(112, 1, 4);
/**
 * The isti'adha and the Basmala in everyday spelling, as a recogniser writes them — exactly the words
 * `RecitationAligner.opening` (and the TS `opening`) recognise.
 */
const ISTI = ['أعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم'];
const BASMALA = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
const fatiha24 = heardOf(1, 1, 3);
const kursi = heardOf(2, 255, 255);

const cases: CaseDef[] = [
  { name: 'exact_recitation', note: 'Al-Fatiha 1–4 heard exactly (no tashkeel): every word ok.', surah: 1, fromAyah: 1, toAyah: 4, heard: timed(heardOf(1, 1, 4)), durationMs: 8000, speechMs: 6400, designed: 'approve' },
  {
    name: 'changed_word_and_missing_ayah',
    note: 'The app test: ayah 2 ends with a different word (warn), ayah 3 not heard (skipped) — coverage 0.7.',
    surah: 1,
    fromAyah: 1,
    toAyah: 3,
    heard: timed([...splitWords(text(1, 1)).map(strip), ...splitWords(text(1, 2)).slice(0, -1).map(strip), 'الناس']),
    durationMs: 6000,
    speechMs: 4200,
    designed: 'needs_review',
  },
  {
    name: 'one_letter_slip',
    note: 'A one-letter recogniser slip in a long word still matches (4+ letters, one edit).',
    surah: 1,
    fromAyah: 6,
    toAyah: 7,
    heard: timed(heardOf(1, 6, 7).map((w, k) => (k === 2 ? `${w.slice(0, -1)}ن` : w))),
    durationMs: 9000,
    speechMs: 7000,
    designed: 'approve',
  },
  { name: 'silence', note: 'Almost no speech: rejected as silence whatever was heard.', surah: 112, fromAyah: 1, toAyah: 4, heard: [], durationMs: 20000, speechMs: 1200, designed: 'reject' },
  { name: 'unclear', note: 'Speech detected but nothing recognised: rejected as unclear.', surah: 112, fromAyah: 1, toAyah: 4, heard: [], durationMs: 10000, speechMs: 6000, designed: 'reject' },
  {
    name: 'wrong_verses',
    note: 'Al-Falaq recited for Al-Ikhlas: coverage below 0.35 → not_matching.',
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed(heardOf(113, 1, 5)),
    durationMs: 14000,
    speechMs: 11000,
    designed: 'reject',
  },
  {
    name: 'partial_recitation',
    note: 'Only the first ~55% of Ayat al-Kursi: borderline → needs_review.',
    surah: 2,
    fromAyah: 255,
    toAyah: 255,
    heard: timed(kursi.slice(0, Math.round(kursi.length * 0.55))),
    durationMs: 30000,
    speechMs: 22000,
    designed: 'needs_review',
  },
  {
    name: 'repetition',
    note: 'The first ayah repeated before going on: a few extra words, still approved.',
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...splitWords(text(112, 1)).map(strip), ...ikhlas]),
    durationMs: 12000,
    speechMs: 9000,
    designed: 'approve',
  },
  {
    name: 'too_many_extra_words',
    note: 'The chosen verses plus two more surahs: coverage 1 but most words are extra → needs_review.',
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...ikhlas, ...heardOf(113, 1, 5), ...heardOf(114, 1, 6)], 100),
    durationMs: 30000,
    speechMs: 26000,
    designed: 'needs_review',
  },
  { name: 'little_speech', note: 'Every word heard but speech under 40% of the clip → needs_review.', surah: 1, fromAyah: 1, toAyah: 3, heard: timed(fatiha24), durationMs: 20000, speechMs: 5000, designed: 'needs_review' },
  {
    name: 'segments',
    note: 'A recogniser segment holding several words shares its time span between them.',
    surah: 112,
    fromAyah: 1,
    toAyah: 2,
    heard: [
      { text: heardOf(112, 1, 1).join(' '), startMs: 200, endMs: 2200 },
      { text: heardOf(112, 2, 2).join(' '), startMs: 2400, endMs: 3600 },
    ],
    durationMs: 4500,
    speechMs: 3400,
    designed: 'approve',
  },

  {
    name: 'istiadha_and_basmala_first',
    note: "The isti'adha and the Basmala before Al-Ikhlas (which does not begin with it): dropped, not extra words.",
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...ISTI, ...BASMALA, ...ikhlas]),
    durationMs: 14000,
    speechMs: 11000,
    designed: 'approve',
  },
  {
    name: 'istiadha_before_fatiha',
    note: "The isti'adha before Al-Fatiha 1–4: dropped; the Basmala (written «الرحمن», the mushaf has a dagger alef) is ayah 1 here, so it is matched, not dropped.",
    surah: 1,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...ISTI, ...BASMALA, ...heardOf(1, 2, 4)]),
    durationMs: 10000,
    speechMs: 8000,
    designed: 'approve',
  },
  {
    name: 'istiadha_mid_recitation',
    note: "The isti'adha said in the middle is not an opening: its words count as extra.",
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...ikhlas.slice(0, 4), ...ISTI, ...ikhlas.slice(4)]),
    durationMs: 14000,
    speechMs: 11000,
    designed: 'approve',
  },
  {
    name: 'opening_only',
    note: "Only the isti'adha and the Basmala, then silence: nothing of the passage was heard → unclear.",
    surah: 112,
    fromAyah: 1,
    toAyah: 4,
    heard: timed([...ISTI, ...BASMALA]),
    durationMs: 8000,
    speechMs: 4500,
    designed: 'reject',
  },
];

const built = cases.map((c) => {
  const expected = ayat(c.surah, c.fromAyah, c.toAyah);
  const r = matchRecitation({ expected, heard: c.heard, durationMs: c.durationMs, speechMs: c.speechMs });
  if (r.verdict !== c.designed) throw new Error(`${c.name}: designed ${c.designed}, matcher says ${r.verdict} (${JSON.stringify(r)})`);
  return {
    name: c.name,
    note: c.note,
    surah: c.surah,
    fromAyah: c.fromAyah,
    toAyah: c.toAyah,
    expected,
    heard: c.heard,
    durationMs: c.durationMs,
    speechMs: c.speechMs,
    result: r,
  };
});

const SAME: [string, string][] = [
  [splitWords(text(1, 1))[3]!, 'الرحيم'],
  ['مستقيم', 'مستقين'],
  ['من', 'ما'],
  [splitWords(text(1, 2))[3]!, 'العالمين'],
  [splitWords(text(1, 4))[0]!, 'مالك'],
  ['الله', 'اللة'],
  ['هو', 'هم'],
];
const ikhlasWords = ayat(112, 1, 4).flatMap((a) => splitWords(a.text));
const fatihaWords = ayat(1, 1, 4).flatMap((a) => splitWords(a.text));
/** `RecitationAligner.opening` vectors: what is dropped, and whether the opening may still be going on. */
const OPENING: { note: string; heard: string[]; expected: string[] }[] = [
  { note: "isti'adha in progress: wait", heard: ISTI.slice(0, 2), expected: ikhlasWords },
  { note: "isti'adha done, Basmala in progress: drop 5, wait", heard: [...ISTI, ...BASMALA.slice(0, 2)], expected: ikhlasWords },
  { note: "both, then the passage: drop 9", heard: [...ISTI, ...BASMALA, ...ikhlas.slice(0, 2)], expected: ikhlasWords },
  { note: 'Basmala only, then the passage: drop 4', heard: [...BASMALA, ...ikhlas.slice(0, 3)], expected: ikhlasWords },
  { note: "passage begins with the Basmala: only the isti'adha is dropped", heard: [...ISTI, ...BASMALA], expected: fatihaWords },
  { note: 'the passage straight away: nothing dropped', heard: ikhlas.slice(0, 3), expected: ikhlasWords },
  { note: 'nothing heard yet', heard: [], expected: ikhlasWords },
];

const NORMALIZE = [text(1, 1), text(1, 2), text(112, 1), 'أإآٱ ة ى ؤ ئ ـ ١٢٣ ABC'];

const files: Record<string, unknown> = {
  'rules.json': {
    $comment: 'Shared recitation-match rules (contracts RECITATION_MATCH). Generated by services/api/scripts/build-recitation-fixtures.ts.',
    normalize: [
      'Remove U+0610–U+061A, U+064B–U+065F, U+0670, U+06D6–U+06ED, U+08D3–U+08FF (tashkeel, Quranic marks, small letters).',
      'Eastern digits ٠–٩ → 0–9; أ إ آ ٱ ٲ ٳ → ا; ة → ه; ى → ي; ؤ → و; ئ → ي; drop tatweel ـ; lower-case; collapse whitespace.',
    ],
    words: 'Split on whitespace; drop tokens made only of U+06D6–U+06ED, U+06DD, U+06DE, ٠–٩, U+FD3E, U+FD3F, 0–9 (ayah-end and pause marks). A word index counts the rest.',
    wordKey: 'Replace U+0670 (dagger alef) with ا, normalise, keep only U+0621–U+064A.',
    same: `Keys equal, or both at least ${RECITATION_MATCH.fuzzyMinLetters} letters and Levenshtein distance ≤ 1.`,
    opening:
      "Before aligning, drop from the start of what is heard the isti'adha (أعوذ بالله من الشيطان الرجيم) and then the Basmala (بسم الله الرحمن الرحيم) unless the passage itself begins with the Basmala (checked with `same`: the mushaf writes الرحمن with a dagger alef); heard words compare by exact key. A partial phrase at the end of what is heard is 'open' (live following waits) and is not dropped. Dropped words are neither heard nor extra (`openingWords`).",
    align:
      'Word-level Levenshtein (substitution cost 0 when same, else 1; deletion = expected word not heard; insertion = extra heard word). Backtrace from the end: same and diagonal equal → ok; else up (+1) → skipped; else diagonal (+1) → warn; else left (extra heard word).',
    scores: {
      coverage: 'ok marks ÷ expected words',
      extraRatio: 'heard words (after the opening) paired with no expected word (not ok/warn) ÷ heard words; 0 when nothing heard',
      speech: 'min(1, speechMs ÷ durationMs)',
      segments: 'A heard entry with several words is split; its span is shared equally between them.',
    },
    verdict: [
      `speech < ${RECITATION_MATCH.silenceSpeech} → reject silence`,
      'no heard words (after the opening) → reject unclear',
      `coverage < ${RECITATION_MATCH.rejectCoverage} → reject not_matching`,
      `coverage ≥ ${RECITATION_MATCH.approveCoverage} and speech ≥ ${RECITATION_MATCH.approveSpeech} and extraRatio ≤ ${RECITATION_MATCH.maxExtraRatio} → approve`,
      'otherwise → needs_review',
    ],
    words_map: 'Each ok/warn expected word → {ayah, index, startMs, endMs} of the heard word it aligned to, in order. Rounded to 4 decimals: coverage, extraRatio, speech.',
    thresholds: RECITATION_MATCH,
  },
  'normalize.json': NORMALIZE.map((input) => ({ input, output: normalizeArabic(input), keys: splitWords(input).map(normWord) })),
  'same.json': SAME.map(([a, b]) => ({ a, b, same: sameWord(a, b) })),
  'opening.json': OPENING.map((o) => ({ ...o, ...opening(o.heard, o.expected) })),
  'cases.json': built,
};

let drift = false;
mkdirSync(outDir, { recursive: true });
for (const [name, data] of Object.entries(files)) {
  const path = `${outDir}${name}`;
  const body = `${JSON.stringify(data, null, 2)}\n`;
  if (process.argv.includes('--check')) {
    let cur = '';
    try {
      cur = readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
    } catch {
      // missing → drift
    }
    if (cur !== body) {
      console.error(`${name} is out of date: run scripts/build-recitation-fixtures.ts`);
      drift = true;
    }
  } else {
    writeFileSync(path, body);
    console.log(`wrote ${path}`);
  }
}
if (drift) process.exit(1);
