/**
 * The «تلاواتي» fixtures the Dart models are tested against (apps/mobile/test/fixtures/recordings) must
 * parse with the zod contracts, so the app and the API agree on every shape.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import type { z } from 'zod';
import { MemberRecordings, MyRecordings, ReactionState, RecordingCommentsPage, RecordingMeta, verseRef } from '@yaqeen/contracts';

const dir = new URL('../../../apps/mobile/test/fixtures/recordings/', import.meta.url);
const load = (name: string): unknown => JSON.parse(readFileSync(fileURLToPath(new URL(name, dir)), 'utf8'));

const FIXTURES: Record<string, z.ZodType> = {
  'my_recordings.json': MyRecordings,
  'member_recordings.json': MemberRecordings,
  'comments.json': RecordingCommentsPage,
  'reaction_state.json': ReactionState,
};

describe('recordings fixtures parse with the contracts', () => {
  for (const [name, schema] of Object.entries(FIXTURES)) {
    it(name, () => {
      const r = schema.safeParse(load(name));
      expect(r.success, r.success ? '' : JSON.stringify(r.error.issues, null, 2)).toBe(true);
    });
  }
});

describe('recordings contract helpers', () => {
  it('upload meta defaults to private with comments on; ranges must be ordered', () => {
    expect(RecordingMeta.parse({ surah: 1, fromAyah: 1, toAyah: 4, durationMs: 9000 })).toMatchObject({ visibility: 'private', commentsOn: true });
    expect(RecordingMeta.safeParse({ surah: 1, fromAyah: 4, toAyah: 1, durationMs: 9000 }).success).toBe(false);
    expect(RecordingMeta.safeParse({ surah: 1, fromAyah: 1, toAyah: 1, durationMs: 40_000 }).success).toBe(false);
  });
  it('verse references use Western digits', () => {
    expect(verseRef(1, 1, 4, 'ar')).toBe('سورة الفاتحة · الآيات 1–4');
    expect(verseRef(2, 255, 255, 'ar')).toBe('سورة البقرة · الآية 255');
    expect(verseRef(112, 1, 4, 'en')).toBe('Al-Ikhlas · Ayat 1–4');
  });
});
