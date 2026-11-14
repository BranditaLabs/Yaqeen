/**
 * The AI check's matcher: does what the recogniser heard recite the verses the user chose?
 *
 * A faithful port of the app's `RecitationAligner` (apps/mobile/lib/features/recite/domain/recitation.dart)
 * and `ArabicText.normalize` (apps/mobile/lib/core/text/arabic.dart): the same normalisation, the
 * dagger-alef rule, word Levenshtein with one-edit tolerance for words of 4+ letters, the same
 * backtrace (ties prefer «not heard» over «heard differently») and the same opening rule (the
 * isti'adha, and the Basmala when the passage does not begin with it, are dropped from the start of
 * what is heard — `RecitationAligner.opening`). The port additionally records which heard word each
 * expected word aligned to, for the karaoke word timings.
 *
 * Shared rules and test vectors: packages/contracts/fixtures/recitation-match/*.json — this module's
 * tests and the Dart test run the same files, so both sides provably agree. Thresholds: contracts
 * `RECITATION_MATCH`. Pure (no I/O).
 */
import { RECITATION_MATCH, type MatchVerdict, type RecordingWord, type RejectReason } from '@yaqeen/contracts';

export type WordMark = 'ok' | 'warn' | 'skipped';

/** Harakat, tanween, shadda, sukun, superscript alef, Quranic annotation marks, small letters. */
const MARKS = /[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]/g;
const EASTERN_DIGITS = '٠١٢٣٤٥٦٧٨٩';
const UNIFY: Record<string, string> = { 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ٲ': 'ا', 'ٳ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ؤ': 'و', 'ئ': 'ي', 'ـ': '' };

/** `ArabicText.normalize`: strip marks, unify alef forms, ta marbuta → ha, alef maqsura → ya, drop tatweel, Western digits, lower-case. */
export function normalizeArabic(input: string): string {
  let out = '';
  for (const c of input.replace(MARKS, '')) {
    const d = EASTERN_DIGITS.indexOf(c);
    if (d >= 0) {
      out += String(d);
      continue;
    }
    out += c in UNIFY ? UNIFY[c] : c.toLowerCase();
  }
  return out.replace(/\s+/g, ' ').trim();
}

/** Ayah-end ornaments and pause/sajda signs are not words. */
const MARK_WORD = /^[ۖ-ۭ۝۞٠-٩﴾﴿0-9]+$/;

/** Words of a text as the app splits them (ayah-end marks dropped); a word's position here is its `index`. */
export function splitWords(text: string): string[] {
  return text.split(/\s+/).filter((w) => w.length > 0 && !MARK_WORD.test(w));
}

/** Dagger alef (ٰ) is read as a full alef — recognisers write «العالمين» for «ٱلْعَٰلَمِينَ». Letters only. */
export function normWord(w: string): string {
  return normalizeArabic(w.replaceAll('ٰ', 'ا')).replace(/[^ء-ي]/g, '');
}

export function editDistance(a: string, b: string): number {
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = new Array<number>(b.length + 1).fill(0);
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const c = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j]! + 1, cur[j - 1]! + 1, prev[j - 1]! + c);
    }
    prev = cur;
  }
  return prev[b.length]!;
}

/** Same word for matching: equal after normalisation, or one edit apart when both have 4+ letters. */
export function sameWord(a: string, b: string): boolean {
  const x = normWord(a);
  const y = normWord(b);
  if (x === y) return true;
  if (x.length < RECITATION_MATCH.fuzzyMinLetters || y.length < RECITATION_MATCH.fuzzyMinLetters) return false;
  return editDistance(x, y) <= 1;
}

const ISTI = ['أعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم'];
const BASMALA = ['بسم', 'الله', 'الرحمن', 'الرحيم'];

/**
 * `RecitationAligner.opening`: how many words at the start of `heard` are the isti'adha / Basmala
 * (`drop`; the Basmala only when `expected` does not begin with it), and whether what is heard so far
 * could still be one of them being said (`open`). Heard words compare by their exact key; whether the
 * passage begins with the Basmala uses `sameWord`.
 */
export function opening(heard: string[], expected: string[]): { drop: number; open: boolean } {
  const eq = (a: string, b: string) => normWord(a) === normWord(b);
  const startsWith = (list: string[], at: number, phrase: string[], cmp = eq) => list.length - at >= phrase.length && phrase.every((p, k) => cmp(list[at + k]!, p));
  // The mushaf writes «ٱلرَّحۡمَٰنِ» with a dagger alef (key «الرحمان»): the passage check uses `sameWord`.
  const basmalaFirst = startsWith(expected, 0, BASMALA, sameWord);
  let at = 0;
  for (const phrase of basmalaFirst ? [ISTI] : [ISTI, BASMALA]) {
    if (startsWith(heard, at, phrase)) {
      at += phrase.length;
      continue;
    }
    const rest = heard.length - at;
    if (rest > 0 && rest < phrase.length && Array.from({ length: rest }, (_, k) => eq(heard[at + k]!, phrase[k]!)).every(Boolean)) {
      return { drop: at, open: true };
    }
  }
  return { drop: at, open: false };
}

/** `RecitationAligner.stripOpening`: `heard` without its isti'adha / Basmala prefix. */
export function stripOpening(heard: string[], expected: string[]): string[] {
  return heard.slice(opening(heard, expected).drop);
}

export interface ExpectedAyah {
  ayah: number;
  text: string;
}

export interface AlignedWord {
  ayah: number;
  index: number;
  word: string;
  mark: WordMark;
  /** Index into the heard words for `ok`/`warn`, else null. */
  heard: number | null;
}

/** `RecitationAligner.align`: marks every expected word against the heard words, in order. */
export function align(expected: ExpectedAyah[], heard: string[]): AlignedWord[] {
  const exp: { ayah: number; index: number; word: string }[] = [];
  for (const e of expected) splitWords(e.text).forEach((word, index) => exp.push({ ayah: e.ayah, index, word }));
  const got = heard.flatMap((h) => splitWords(h));
  const n = exp.length;
  const m = got.length;
  const same: boolean[][] = Array.from({ length: n }, (_, i) => Array.from({ length: m }, (_, j) => sameWord(exp[i]!.word, got[j]!)));
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = 0; i <= n; i++) dp[i]![0] = i;
  for (let j = 0; j <= m; j++) dp[0]![j] = j;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const sub = dp[i - 1]![j - 1]! + (same[i - 1]![j - 1] ? 0 : 1);
      const del = dp[i - 1]![j]! + 1; // expected word not heard
      const ins = dp[i]![j - 1]! + 1; // extra word heard (repetition, isti'adha…)
      dp[i]![j] = sub < del ? (sub < ins ? sub : ins) : del < ins ? del : ins;
    }
  }
  const marks: WordMark[] = new Array<WordMark>(n).fill('skipped');
  const heardIdx: (number | null)[] = new Array<number | null>(n).fill(null);
  let i = n;
  let j = m;
  while (i > 0 && j > 0) {
    const match = same[i - 1]![j - 1]!;
    // Ties prefer «not heard yet» over «heard differently», so stopping early never shows a warning.
    if (match && dp[i]![j] === dp[i - 1]![j - 1]) {
      marks[i - 1] = 'ok';
      heardIdx[i - 1] = j - 1;
      i--;
      j--;
    } else if (dp[i]![j] === dp[i - 1]![j]! + 1) {
      marks[i - 1] = 'skipped';
      i--;
    } else if (dp[i]![j] === dp[i - 1]![j - 1]! + 1) {
      marks[i - 1] = 'warn';
      heardIdx[i - 1] = j - 1;
      i--;
      j--;
    } else {
      j--;
    }
  }
  return exp.map((e, k) => ({ ...e, mark: marks[k]!, heard: heardIdx[k]! }));
}

export interface HeardWord {
  text: string;
  startMs: number;
  endMs: number;
}

export interface MatchInput {
  expected: ExpectedAyah[];
  heard: HeardWord[];
  durationMs: number;
  speechMs: number;
}

export interface MatchResult {
  /** `ok` expected words ÷ expected words. */
  coverage: number;
  /** Heard words aligned to no expected word ÷ heard words, after the opening (0 when nothing was heard). */
  extraRatio: number;
  /** Words dropped from the start of what was heard as the isti'adha / Basmala (not part of the passage). */
  openingWords: number;
  /** Speech ÷ duration. */
  speech: number;
  verdict: MatchVerdict;
  rejectReason: Exclude<RejectReason, 'removed_by_moderator'> | null;
  marks: WordMark[];
  /** Karaoke timings of the matched (`ok`/`warn`) words, in order. */
  words: RecordingWord[];
}

const round = (x: number) => Math.round(x * 10_000) / 10_000;

/** Score a recording and decide: approve, needs_review or reject (contracts `RECITATION_MATCH`). */
export function matchRecitation(input: MatchInput): MatchResult {
  const T = RECITATION_MATCH;
  // A heard entry may hold several words (a recogniser segment): split, sharing its time span.
  const all: HeardWord[] = input.heard.flatMap((h) => {
    const parts = splitWords(h.text);
    if (parts.length <= 1) return parts.map((text) => ({ ...h, text }));
    const span = Math.max(0, h.endMs - h.startMs) / parts.length;
    return parts.map((text, k) => ({ text, startMs: Math.round(h.startMs + k * span), endMs: Math.round(h.startMs + (k + 1) * span) }));
  });
  // The isti'adha / Basmala said before the passage is neither an extra word nor part of it.
  const openingWords = opening(
    all.map((h) => h.text),
    input.expected.flatMap((e) => splitWords(e.text)),
  ).drop;
  const heard = all.slice(openingWords);
  const aligned = align(
    input.expected,
    heard.map((h) => h.text),
  );
  const n = aligned.length;
  const okCount = aligned.filter((a) => a.mark === 'ok').length;
  const paired = aligned.filter((a) => a.heard !== null).length;
  const coverage = n === 0 ? 0 : okCount / n;
  const extraRatio = heard.length === 0 ? 0 : (heard.length - paired) / heard.length;
  const speech = input.durationMs <= 0 ? 0 : Math.min(1, input.speechMs / input.durationMs);

  let verdict: MatchVerdict;
  let rejectReason: MatchResult['rejectReason'] = null;
  if (speech < T.silenceSpeech) {
    verdict = 'reject';
    rejectReason = 'silence';
  } else if (heard.length === 0) {
    verdict = 'reject';
    rejectReason = 'unclear';
  } else if (coverage < T.rejectCoverage) {
    verdict = 'reject';
    rejectReason = 'not_matching';
  } else if (coverage >= T.approveCoverage && speech >= T.approveSpeech && extraRatio <= T.maxExtraRatio) {
    verdict = 'approve';
  } else {
    verdict = 'needs_review';
  }

  const words: RecordingWord[] = aligned
    .filter((a) => a.heard !== null)
    .map((a) => {
      const h = heard[a.heard!]!;
      return { ayah: a.ayah, index: a.index, startMs: Math.max(0, Math.round(h.startMs)), endMs: Math.max(0, Math.round(h.endMs)) };
    });

  return { coverage: round(coverage), extraRatio: round(extraRatio), openingWords, speech: round(speech), verdict, rejectReason, marks: aligned.map((a) => a.mark), words };
}
