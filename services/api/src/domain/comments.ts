/**
 * Comment moderation for «تلاواتي» — zero cost, no third party (pure; unit-tested in test/comments.test.ts).
 *
 * A comment is refused when, after normalisation, it is shorter than `COMMENT_MIN`, longer than
 * `COMMENT_MAX`, carries a link or a phone number, or contains a blocklisted word
 * (data/comment-blocklist.txt). @mentions are returned so the service can refuse those that name no
 * community member. Normalisation folds Arabic tashkeel, alef/ya/ta-marbuta/hamza seats, tatweel,
 * repeated letters (3+ → 1) and leetspeak, and joins letters spread out with spaces or dots.
 * Rate limits and the 3-report auto-hide live in the service (they need the database).
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { COMMENT_MAX, COMMENT_MIN } from '@yaqeen/contracts';
import { normalizeArabic } from './recitation-match.js';

export type CommentProblem = 'too_short' | 'too_long' | 'link' | 'phone' | 'blocked_word' | 'invalid_chars';

export type CommentCheck = { ok: true; text: string; mentions: string[] } | { ok: false; problem: CommentProblem };

/** Bidi controls and zero-width characters are dropped; other control characters refuse the comment. */
// eslint-disable-next-line no-control-regex
const INVISIBLE = /[​-‏‪-‮⁦-⁩﻿]/g;
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;

const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '@': 'a', $: 's', '!': 'i', '|': 'l' };

const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]{2,}\s*(?:\.|dot|\(dot\)|\[dot\]|دوت)\s*(?:com|net|org|io|me|ly|gg|xyz|info|co|app|link|site|online|store|shop|live|tv|ru|tk|eg|sa|ae)\b|\bt\.me\b|wa\.me|\bbit\s*\.\s*ly\b)/i;
const MENTION = /(?:^|[^\w@])@([a-z][a-z0-9_.-]{1,39})/gi;

/** Fold a word for blocklist matching. */
export function foldWord(word: string): string {
  let w = normalizeArabic(word).toLowerCase();
  w = Array.from(w)
    .map((c) => LEET[c] ?? c)
    .join('');
  w = w.replace(/[^\p{L}]/gu, '');
  // Repeated letters: «شرررموط», "shiiit".
  w = w.replace(/(\p{L})\1{2,}/gu, '$1');
  return w;
}

/** Tokens of a text, folded; runs of single letters (s h i t, ش.ر.م.و.ط) are joined into one token. */
export function foldTokens(text: string): string[] {
  const raw = normalizeArabic(text)
    .toLowerCase()
    .split(/[\s.,،؛;:!?؟"'()[\]{}«»\-_/\\*+=~^]+/u)
    .filter(Boolean);
  const out: string[] = [];
  let run = '';
  for (const t of raw) {
    const f = foldWord(t);
    if (Array.from(f).length === 1) {
      run += f;
      continue;
    }
    if (run) {
      out.push(foldWord(run));
      run = '';
    }
    if (f) out.push(f);
  }
  if (run) out.push(foldWord(run));
  return out;
}

/** Arabic attached prefixes tried when matching: و، ال، وال، يا. */
function variants(token: string): string[] {
  const v = new Set([token]);
  for (const p of ['وال', 'ال', 'و', 'يا', 'فال', 'بال']) if (token.startsWith(p) && token.length - p.length >= 2) v.add(token.slice(p.length));
  // English plural.
  if (/^[a-z]+s$/.test(token) && token.length > 3) v.add(token.slice(0, -1));
  return [...v];
}

export interface Blocklist {
  words: Set<string>;
  phrases: string[][];
}

export function parseBlocklist(text: string): Blocklist {
  const words = new Set<string>();
  const phrases: string[][] = [];
  for (const line of text.replace(/\r\n/g, '\n').split('\n')) {
    const l = line.trim();
    if (!l || l.startsWith('#')) continue;
    const toks = foldTokens(l);
    if (toks.length === 1) words.add(toks[0]!);
    else if (toks.length > 1) phrases.push(toks);
  }
  return { words, phrases };
}

let cached: Blocklist | null = null;
export function defaultBlocklist(): Blocklist {
  cached ??= parseBlocklist(readFileSync(fileURLToPath(new URL('../../data/comment-blocklist.txt', import.meta.url)), 'utf8'));
  return cached;
}

function digitsOnly(text: string): string {
  return normalizeArabic(text).replace(/[^0-9]/g, ' ');
}

/** A phone number: 7+ digits, allowing spaces, dots, dashes and brackets between them. */
export function hasPhone(text: string): boolean {
  const t = normalizeArabic(text);
  if (/(?:\+?\d[\s().-]*){7,}/.test(t)) return true;
  return digitsOnly(t).replace(/\s+/g, '').length >= 10;
}

export function hasLink(text: string): boolean {
  return LINK.test(normalizeArabic(text));
}

export function hasBlockedWord(text: string, list: Blocklist = defaultBlocklist()): boolean {
  const toks = foldTokens(text);
  for (const t of toks) for (const v of variants(t)) if (list.words.has(v)) return true;
  for (const p of list.phrases) {
    for (let i = 0; i + p.length <= toks.length; i++) {
      if (p.every((w, k) => variants(toks[i + k]!).includes(w))) return true;
    }
  }
  // Words written without spaces between letters-only runs ("f u c k" handled by foldTokens); also the whole text squashed.
  const squashed = foldWord(text);
  for (const w of list.words) if (Array.from(w).length >= 5 && squashed === w) return true;
  return false;
}

/** Check (and clean) a comment. */
export function checkComment(input: string, list: Blocklist = defaultBlocklist()): CommentCheck {
  if (CONTROL.test(input)) return { ok: false, problem: 'invalid_chars' };
  const text = input.replace(INVISIBLE, '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  const len = Array.from(text).length;
  if (len < COMMENT_MIN) return { ok: false, problem: 'too_short' };
  if (len > COMMENT_MAX) return { ok: false, problem: 'too_long' };
  if (hasLink(text)) return { ok: false, problem: 'link' };
  if (hasPhone(text)) return { ok: false, problem: 'phone' };
  if (hasBlockedWord(text, list)) return { ok: false, problem: 'blocked_word' };
  const mentions = [...new Set([...text.matchAll(MENTION)].map((m) => m[1]!.toLowerCase()))];
  return { ok: true, text, mentions };
}
