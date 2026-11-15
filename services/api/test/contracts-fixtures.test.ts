/**
 * The community fixtures the Dart models are tested against (apps/mobile/test/fixtures/community)
 * must parse with the zod contracts, so the app and the API agree on every shape.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  AVATAR_PRESETS,
  Badge,
  BADGE_KINDS,
  BlockedUser,
  COMMUNITY_ERROR_CODES,
  DIVISIONS,
  LeaderboardView,
  LeagueCurrent,
  LEVELS,
  LevelInfoSchema,
  levelFor,
  MeProfile,
  Tournament,
  TournamentStandings,
} from '@yaqeen/contracts';

const dir = new URL('../../../apps/mobile/test/fixtures/community/', import.meta.url);
const load = (name: string): unknown => JSON.parse(readFileSync(fileURLToPath(new URL(name, dir)), 'utf8'));

const FIXTURES: Record<string, z.ZodType> = {
  'me_profile.json': MeProfile,
  'me_profile_photo.json': MeProfile,
  'league_current_joined.json': LeagueCurrent,
  'league_current_off.json': LeagueCurrent,
  'league_current_closing.json': LeagueCurrent,
  'tournaments.json': z.array(Tournament),
  'standings.json': TournamentStandings,
  'leaderboard.json': LeaderboardView,
  'badges.json': z.array(Badge),
  'blocks.json': z.array(BlockedUser),
  'levels.json': z.array(LevelInfoSchema),
};

describe('community fixtures parse with the contracts', () => {
  for (const [name, schema] of Object.entries(FIXTURES)) {
    it(name, () => {
      const r = schema.safeParse(load(name));
      expect(r.success, r.success ? '' : JSON.stringify(r.error.issues, null, 2)).toBe(true);
    });
  }

  it('every badge kind appears in badges.json', () => {
    const kinds = new Set((load('badges.json') as { kind: string }[]).map((b) => b.kind));
    expect([...kinds].sort()).toEqual([...BADGE_KINDS].sort());
  });

  it('levels.json agrees with levelFor', () => {
    for (const l of z.array(LevelInfoSchema).parse(load('levels.json'))) {
      const min = LEVELS[l.level - 1]!.min;
      const sample = l.nextAt === null ? min : Math.round(min + l.progress * (l.nextAt - min));
      expect(levelFor(sample)).toEqual(l);
    }
  });

  it('constants.json is generated from the contracts', () => {
    const c = load('constants.json') as Record<string, unknown>;
    expect(c.AVATAR_PRESETS).toEqual([...AVATAR_PRESETS]);
    expect(c.DIVISIONS).toEqual(DIVISIONS.map((d) => ({ ...d })));
    expect(c.BADGE_KINDS).toEqual([...BADGE_KINDS]);
    expect(c.COMMUNITY_ERROR_CODES).toEqual([...COMMUNITY_ERROR_CODES]);
    for (const v of c.levelFor as ({ points: number } & ReturnType<typeof levelFor>)[]) {
      const { points, ...info } = v;
      expect(levelFor(points)).toEqual(info);
    }
  });
});
