/**
 * Pure community rules (docs/design/2026-11-profile-community-quran.md §3.5): Cairo weeks over Egypt
 * DST, competition ranking, zone order, outcomes and badges at tie boundaries, small/solo groups,
 * tournament windows, the display-name filter and competitor handles.
 */
import { describe, expect, it } from 'vitest';
import { RESERVED_HANDLES } from '@yaqeen/contracts';
import {
  cairoMidnight,
  canonicalName,
  competitorHandle,
  daysBetween,
  effectiveZones,
  firstName,
  isCairoMidnight,
  leagueBadge,
  memberHandle,
  nameProblem,
  nextDivision,
  outcomeFor,
  packInto,
  rankStandings,
  tournamentBadge,
  tournamentDays,
  tournamentPhase,
  tournamentWindow,
  validateTournament,
  weekWindow,
} from '../src/domain/community.js';
import { localToday } from '../src/domain/points.js';
import { POLICY_VERSION } from '../src/services/community.service.js';
import { LEGAL_VERSION, renderPrivacy, renderTerms } from '../src/web/site-pages.js';

const seq = (...xs: number[]) => {
  let i = 0;
  return () => xs[i++ % xs.length]!;
};

describe('Cairo midnights and league weeks', () => {
  it('a winter midnight is 22:00 UTC the day before, a summer one 21:00 UTC', () => {
    expect(cairoMidnight('2026-01-10').toISOString()).toBe('2026-01-09T22:00:00.000Z');
    expect(cairoMidnight('2026-07-11').toISOString()).toBe('2026-07-10T21:00:00.000Z');
  });

  it('spring-forward day (last Friday of April 2026) starts at local 01:00 = 22:00 UTC', () => {
    // Egypt: clocks jump from Fri 00:00 to 01:00 on 2026-04-24.
    const m = cairoMidnight('2026-04-24');
    expect(localToday(m)).toBe('2026-04-24');
    expect(localToday(new Date(m.getTime() - 1))).toBe('2026-04-23');
    expect(isCairoMidnight(m)).toBe(true);
    // The next day is a summer midnight.
    expect(cairoMidnight('2026-04-25').toISOString()).toBe('2026-04-24T21:00:00.000Z');
  });

  it('fall-back day (last Thursday of October 2026) — the Friday starts at 22:00 UTC', () => {
    const m = cairoMidnight('2026-10-30');
    expect(m.toISOString()).toBe('2026-10-29T22:00:00.000Z');
    expect(localToday(new Date(m.getTime() - 1))).toBe('2026-10-29');
    expect(cairoMidnight('2026-10-29').toISOString()).toBe('2026-10-28T21:00:00.000Z');
  });

  it('isCairoMidnight rejects other instants', () => {
    expect(isCairoMidnight(new Date('2026-01-09T22:00:00Z'))).toBe(true);
    expect(isCairoMidnight(new Date('2026-01-10T00:00:00Z'))).toBe(false);
    expect(isCairoMidnight(new Date('2026-01-09T22:00:01Z'))).toBe(false);
    expect(isCairoMidnight(new Date('nope'))).toBe(false);
  });

  it('weeks run Saturday 00:00 to Saturday 00:00 Cairo, DST-safe in length', () => {
    // Wednesday 2026-11-11 → week of Saturday 2026-11-07.
    const w = weekWindow(new Date('2026-11-11T10:00:00Z'));
    expect(w.startsOn).toBe('2026-11-07');
    expect(w.startsAt.toISOString()).toBe('2026-11-06T22:00:00.000Z');
    expect(w.endsAt.toISOString()).toBe('2026-11-13T22:00:00.000Z');
    // A Saturday at 00:01 Cairo is already the new week.
    expect(weekWindow(new Date('2026-11-13T22:01:00Z')).startsOn).toBe('2026-11-14');
    // Friday 23:59 Cairo is still the old one.
    expect(weekWindow(new Date('2026-11-13T21:59:00Z')).startsOn).toBe('2026-11-07');
    // The spring-forward week is 167 h, the fall-back week 169 h.
    const spring = weekWindow(new Date('2026-04-22T12:00:00Z'));
    expect(spring.startsOn).toBe('2026-04-18');
    expect((spring.endsAt.getTime() - spring.startsAt.getTime()) / 3_600_000).toBe(167);
    const fall = weekWindow(new Date('2026-10-28T12:00:00Z'));
    expect(fall.startsOn).toBe('2026-10-24');
    expect((fall.endsAt.getTime() - fall.startsAt.getTime()) / 3_600_000).toBe(169);
  });

  it('daysBetween lists the week days', () => {
    expect(daysBetween('2026-11-07', '2026-11-14')).toHaveLength(7);
    expect(daysBetween('2026-11-07', '2026-11-07')).toEqual([]);
  });
});

describe('rankStandings', () => {
  it('standard competition ranking, handle order inside ties, 0 points → no rank', () => {
    const r = rankStandings([
      { userId: 'a', handle: 'zed', points: 50 },
      { userId: 'b', handle: 'amy', points: 50 },
      { userId: 'c', handle: 'bob', points: 30 },
      { userId: 'd', handle: 'cat', points: 0 },
      { userId: 'e', handle: 'abe', points: 0 },
      { userId: 'f', handle: 'dan', points: 10 },
    ]);
    expect(r.map((x) => [x.userId, x.rank, x.position, x.order])).toEqual([
      ['b', 1, 1, 1],
      ['a', 1, 1, 2],
      ['c', 3, 3, 3],
      ['f', 4, 4, 4],
      ['e', null, 5, 5],
      ['d', null, 5, 6],
    ]);
  });

  it('empty input', () => {
    expect(rankStandings([])).toEqual([]);
  });
});

describe('effectiveZones (rule order)', () => {
  const s = { promote: 5, demote: 5 };
  it('groups under 5 neither promote nor demote', () => {
    expect(effectiveZones(4, s, 3)).toEqual({ promote: 0, demote: 0 });
    expect(effectiveZones(1, s, 3)).toEqual({ promote: 0, demote: 0 });
  });
  it('caps each zone at a third of the group', () => {
    expect(effectiveZones(30, s, 3)).toEqual({ promote: 5, demote: 5 });
    expect(effectiveZones(9, s, 3)).toEqual({ promote: 3, demote: 3 });
    expect(effectiveZones(5, s, 3)).toEqual({ promote: 1, demote: 1 });
  });
  it('division 6 never promotes, division 1 never demotes (after the caps)', () => {
    expect(effectiveZones(30, s, 6)).toEqual({ promote: 0, demote: 5 });
    expect(effectiveZones(30, s, 1)).toEqual({ promote: 5, demote: 0 });
    expect(effectiveZones(3, s, 1)).toEqual({ promote: 0, demote: 0 });
  });
});

describe('outcomes and badges at tie boundaries', () => {
  const zones = { promote: 2, demote: 2 };
  it('everyone tied at the promote boundary goes up', () => {
    const r = rankStandings([
      { userId: 'a', handle: 'a', points: 90 },
      { userId: 'b', handle: 'b', points: 50 },
      { userId: 'c', handle: 'c', points: 50 },
      { userId: 'd', handle: 'd', points: 40 },
      { userId: 'e', handle: 'e', points: 30 },
      { userId: 'f', handle: 'f', points: 20 },
      { userId: 'g', handle: 'g', points: 10 },
    ]);
    const out = r.map((x) => outcomeFor(x.position, r.length, x.points, zones));
    expect(out).toEqual(['up', 'up', 'up', 'stay', 'stay', 'down', 'down']);
  });

  it('a tie straddling the demote boundary stays (the kinder side)', () => {
    const r = rankStandings([
      { userId: 'a', handle: 'a', points: 90 },
      { userId: 'b', handle: 'b', points: 80 },
      { userId: 'c', handle: 'c', points: 70 },
      { userId: 'd', handle: 'd', points: 60 },
      { userId: 'e', handle: 'e', points: 10 },
      { userId: 'f', handle: 'f', points: 10 },
    ]);
    // Size 6, demote 2 → down only when position > 4; e and f share position 5 → both down.
    expect(r.map((x) => outcomeFor(x.position, 6, x.points, zones))).toEqual(['up', 'up', 'stay', 'stay', 'down', 'down']);
    const r2 = rankStandings([
      { userId: 'a', handle: 'a', points: 90 },
      { userId: 'b', handle: 'b', points: 80 },
      { userId: 'c', handle: 'c', points: 70 },
      { userId: 'd', handle: 'd', points: 10 },
      { userId: 'e', handle: 'e', points: 10 },
      { userId: 'f', handle: 'f', points: 5 },
    ]);
    // d and e share position 4 (≤ 4) → stay, though one of them sits in the bottom two.
    expect(r2.map((x) => outcomeFor(x.position, 6, x.points, zones))).toEqual(['up', 'up', 'stay', 'stay', 'stay', 'down']);
  });

  it('up needs points above 0; members who left get nothing', () => {
    expect(outcomeFor(1, 10, 0, zones)).toBe('stay');
    expect(outcomeFor(1, 10, 50, zones, true)).toBeNull();
  });

  it('a solo group never promotes and earns no first/top-3 badge', () => {
    const z = effectiveZones(1, { promote: 5, demote: 5 }, 3);
    const o = outcomeFor(1, 1, 500, z);
    expect(o).toBe('stay');
    expect(leagueBadge(1, 1, 500, o)).toBeNull();
  });

  it('league badge tiers, shared on ties', () => {
    expect(leagueBadge(1, 30, 10, 'up')).toBe('league_first');
    expect(leagueBadge(1, 30, 10, 'up')).toBe('league_first'); // a tied first also gets it
    expect(leagueBadge(3, 30, 10, 'up')).toBe('league_top3');
    expect(leagueBadge(4, 30, 10, 'up')).toBe('league_promoted');
    expect(leagueBadge(4, 30, 10, 'stay')).toBeNull();
    expect(leagueBadge(1, 30, 0, 'stay')).toBeNull();
    expect(leagueBadge(2, 4, 10, 'stay')).toBeNull();
  });

  it('tournament badge tiers with minPoints and small fields', () => {
    expect(tournamentBadge(1, 10, 100, 50)).toBe('tournament_podium');
    expect(tournamentBadge(3, 100, 100, 50)).toBe('tournament_podium');
    expect(tournamentBadge(10, 100, 100, 50)).toBe('tournament_top10');
    expect(tournamentBadge(11, 100, 100, 50)).toBe('tournament_finisher');
    expect(tournamentBadge(1, 9, 100, 50)).toBe('tournament_finisher'); // fewer than 10 joiners: no podium
    expect(tournamentBadge(1, 100, 49, 50)).toBeNull();
    expect(tournamentBadge(2, 25, 60, 50)).toBe('tournament_podium');
    expect(tournamentBadge(3, 25, 60, 50)).toBe('tournament_podium'); // tied third shares the podium
    expect(tournamentBadge(4, 25, 60, 1)).toBe('tournament_finisher'); // ceil(2.5) = 3
    expect(tournamentBadge(1, 5, 0, 1)).toBeNull();
  });

  it('divisions move by one and stay within 1..6', () => {
    expect(nextDivision(3, 'up')).toBe(4);
    expect(nextDivision(6, 'up')).toBe(6);
    expect(nextDivision(1, 'down')).toBe(1);
    expect(nextDivision(2, null)).toBe(2);
  });

  it('packing fills each group before opening another', () => {
    expect(packInto([28, 30], 5, 30)).toEqual({ existing: [2, 0], fresh: [3] });
    expect(packInto([], 65, 30)).toEqual({ existing: [], fresh: [30, 30, 5] });
    expect(packInto([10], 3, 30)).toEqual({ existing: [3], fresh: [] });
  });
});

describe('tournament windows', () => {
  const now = new Date('2026-11-01T10:00:00Z');
  const ok = { slug: 'ramadan-1448', ...tournamentWindow({ startsOn: '2027-02-08', lastDay: '2027-03-09' }) };

  it('admin days map to Cairo midnights (exclusive end and join)', () => {
    expect(ok.startsAt.toISOString()).toBe('2027-02-07T22:00:00.000Z');
    expect(ok.endsAt.toISOString()).toBe('2027-03-09T22:00:00.000Z');
    expect(ok.joinUntil.getTime()).toBe(ok.endsAt.getTime());
    expect(tournamentDays(ok)).toEqual({ startsOn: '2027-02-08', lastDay: '2027-03-09', joinLastDay: '2027-03-09' });
    expect(validateTournament(ok, now)).toBeNull();
  });

  it('rejects non-midnight instants, bad order, > 90 days, bad slugs and past windows', () => {
    expect(validateTournament({ ...ok, startsAt: new Date('2027-02-08T00:00:00Z') }, now)).toBe('tournament_dates');
    expect(validateTournament({ ...ok, endsAt: ok.startsAt }, now)).toBe('tournament_dates');
    expect(validateTournament({ ...ok, joinUntil: ok.startsAt }, now)).toBe('tournament_dates');
    expect(validateTournament({ ...ok, joinUntil: cairoMidnight('2027-03-12') }, now)).toBe('tournament_dates');
    expect(validateTournament({ ...ok, ...tournamentWindow({ startsOn: '2027-01-01', lastDay: '2027-04-01' }) }, now)).toBe('tournament_dates');
    expect(validateTournament({ ...ok, slug: 'Ramadan!' }, now)).toBe('tournament_dates');
    expect(validateTournament(ok, new Date('2027-04-01T00:00:00Z'))).toBe('tournament_dates');
    // Exactly 90 days is fine.
    expect(validateTournament({ ...ok, ...tournamentWindow({ startsOn: '2027-01-01', lastDay: '2027-03-31' }) }, now)).toBeNull();
  });

  it('phases follow the window', () => {
    expect(tournamentPhase(ok, now)).toBe('upcoming');
    expect(tournamentPhase(ok, new Date('2027-02-08T00:00:00Z'))).toBe('live');
    expect(tournamentPhase(ok, ok.endsAt)).toBe('ended');
  });
});

describe('policy pages', () => {
  const links = { base: 'https://x.test', store: 'https://store.test', getApp: 'https://x.test/get-app', supportEmail: '' };
  it('/terms has the «المنافسات والسلوك» section at #community in both languages', () => {
    const ar = renderTerms('ar', links);
    expect(ar).toContain('<section id="community">');
    expect(ar).toContain('href="#community"');
    expect(ar).toContain('المنافسات والسلوك');
    expect(renderTerms('en', links)).toContain('Competitions and conduct');
  });
  it('/privacy covers photos, nightly snapshots, the country board, attestation and retention; counsel brackets kept', () => {
    for (const lang of ['ar', 'en'] as const) {
      const html = renderPrivacy(lang, links);
      expect(html).toMatch(/WebP/);
      expect(html).toMatch(lang === 'ar' ? /كل ليلة/ : /once a night/);
      expect(html).toMatch(/20/);
      expect(html).toMatch(lang === 'ar' ? /18 عاماً/ : /18 or older/);
      expect(html).toMatch(lang === 'ar' ? /7 أيام/ : /7 days/);
      expect(html).toMatch(/\[[^\]]+\]/);
    }
    expect(POLICY_VERSION).toBe(LEGAL_VERSION);
  });
});

describe('names and handles', () => {
  it('canonicalName trims, collapses spaces and normalises to NFC', () => {
    expect(canonicalName('  Omar   Ali ')).toBe('Omar Ali');
    expect(canonicalName('José')).toBe('José');
    expect(firstName('  عمر  علي')).toBe('عمر');
  });

  it('accepts ordinary Arabic and English names', () => {
    for (const n of ['عمر', 'سارة أحمد', 'Omar Ali', 'Fatma', 'عبد الرحمن', "D'Angelo"]) expect(nameProblem(n, [])).toBeNull();
  });

  it('rejects bidi controls and zero-width characters', () => {
    for (const ch of ['‎', '‏', '‪', '‮', '⁦', '⁩', '​', '‌', '‍', '﻿']) {
      expect(nameProblem(`Omar${ch}Ali`, [])).toBe('invalid_name');
    }
  });

  it('rejects empty names, URLs and control characters', () => {
    expect(nameProblem('   ', [])).toBe('name_required');
    expect(nameProblem('visit www.example.com', [])).toBe('invalid_name');
    expect(nameProblem('https://x', [])).toBe('invalid_name');
    expect(nameProblem('a\u0007b', [])).toBe('invalid_name');
  });

  it('rejects brand impersonation after folding', () => {
    for (const n of ['يقين', 'فريق يقين', 'فريق  يَقين', 'الدعم', 'الإدارة', 'Yaqeen', 'YAQEEN Team', 'yaqeen_official', 'Support', 'admin', 'Official Page']) {
      expect(nameProblem(n, [])).toBe('invalid_name');
    }
  });

  it('rejects reserved handles (built-in and cards settings)', () => {
    expect(nameProblem('Settings', RESERVED_HANDLES)).toBe('invalid_name');
    expect(nameProblem('brandita', ['brandita'])).toBe('invalid_name');
    expect(nameProblem('Brandita Fan', ['brandita'])).toBe('invalid_name');
    expect(nameProblem('Omar', ['brandita'])).toBeNull();
  });

  it('rejects the profanity list in Arabic and English', () => {
    for (const n of ['fuck you', 'Bitch', 'shithead', 'شرموطة', 'يا عرص', 'منيوك']) expect(nameProblem(n, [])).toBe('invalid_name');
  });

  it('competitorHandle: first word slug + 4 digits, never the full name', () => {
    expect(competitorHandle('Omar Ali Hassan', seq(0.5, 0.5, 0.2, 0.1))).toBe('omar-5521');
    expect(competitorHandle('José María', seq(0))).toBe('jose-0000');
    expect(competitorHandle('42Sara', seq(0.9))).toBe('sara-9999');
    expect(competitorHandle('Omar Ali', Math.random)).toMatch(/^omar-\d{4}$/);
  });

  it('competitorHandle: member-xxxxxx when the first word has no ASCII letters', () => {
    expect(competitorHandle('عمر علي', seq(0))).toBe('member-aaaaaa');
    expect(competitorHandle(null, Math.random)).toMatch(/^member-[a-z0-9]{6}$/);
    expect(competitorHandle('123', Math.random)).toMatch(/^member-[a-z0-9]{6}$/);
    expect(memberHandle(Math.random)).toMatch(/^member-[a-z0-9]{6}$/);
  });
});
