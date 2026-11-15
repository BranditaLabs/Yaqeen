/**
 * The public card's «تلاواتي» section and its motion: markup, motion tokens, reduced-motion end states,
 * ayah numbers following verified timings, and the player script (behaviour in e2e/tests/cards.spec.ts).
 * Which recordings reach the card (public + approved only) is in recordings.db.test.ts.
 */
import { describe, expect, it } from 'vitest';
import type { PublicProfileView } from '@yaqeen/contracts';
import { ayahStarts } from '../src/domain/ayah-starts.js';
import { renderNotFoundPage, renderProfilePage } from '../src/web/profile-page.js';
import { type CardRecitation, RECITATIONS_CSS, RECITATIONS_JS, renderRecitations } from '../src/web/recitations-player.js';

const links = { getApp: 'https://x.test/get-app?ref=omar', store: 'https://store.test/', self: 'https://x.test/u/omar', image: 'https://x.test/u/assets/icon.png' };

const view: PublicProfileView = {
  handle: 'omar',
  displayName: 'Omar',
  bio: '',
  links: [],
  theme: 'sky',
  level: { level: 2, nameAr: 'على الطريق', nameEn: 'On the path', progress: 0.4 },
  streak: null,
  challengeDay: null,
  badges: null,
  memberSince: null,
  timeline: null,
};

const reactions: CardRecitation['reactions'] = { mashallah: 3, barakallah: 0, ahsant: 1 };
const rec = (over: Partial<CardRecitation> = {}): CardRecitation => ({
  id: '11111111-1111-4111-8111-111111111111',
  surah: 112,
  fromAyah: 1,
  toAyah: 4,
  durationMs: 12_000,
  reactions,
  audioUrl: '/u/omar/r/11111111-1111-4111-8111-111111111111.m4a',
  ayahStarts: [0, 2_400, 5_100, 8_000],
  ...over,
});

/** The CSS rules inside `@media (prefers-reduced-motion:reduce){…}` (one level of nested braces). */
function reducedBlocks(css: string): string[] {
  const out: string[] = [];
  const re = /@media \(prefers-reduced-motion:reduce\)\{((?:[^{}]|\{[^{}]*\})*)\}/g;
  for (let m = re.exec(css); m; m = re.exec(css)) out.push(m[1]!);
  return out;
}

describe('ayah starts from word timings', () => {
  it('takes each ayah’s first word, starts at 0 and never goes back', () => {
    const words = [
      { ayah: 1, index: 0, startMs: 120, endMs: 500 },
      { ayah: 1, index: 1, startMs: 520, endMs: 900 },
      { ayah: 2, index: 0, startMs: 2_400, endMs: 2_900 },
      { ayah: 3, index: 1, startMs: 5_300, endMs: 5_600 },
      { ayah: 3, index: 0, startMs: 5_100, endMs: 5_290 },
      { ayah: 4, index: 0, startMs: 4_000, endMs: 4_200 }, // aligner glitch: earlier than ayah 3
    ];
    expect(ayahStarts(words, 1, 4)).toEqual([0, 2_400, 5_100, 5_100]);
  });

  it('an ayah without words inherits the previous start; nothing to follow → null', () => {
    expect(ayahStarts([{ ayah: 3, startMs: 4_000 }], 2, 4)).toEqual([0, 4_000, 4_000]);
    expect(ayahStarts([{ ayah: 5, startMs: 100 }], 5, 5)).toBeNull(); // one ayah
    expect(ayahStarts([], 1, 4)).toBeNull();
    expect(ayahStarts(null, 1, 4)).toBeNull();
    expect(ayahStarts([{ ayah: 9, startMs: 100 }], 1, 4)).toBeNull(); // out of range only
  });
});

describe('«تلاواتي» on the public card', () => {
  it('no recordings → no section and no script', () => {
    const html = renderProfilePage(view, 'ar', links);
    expect(html).not.toContain('class="recs');
    expect(html).not.toContain('<script');
    expect(renderRecitations([], 'ar', links.getApp)).toBe('');
  });

  it('renders the player with a progress ring, a hairline ring and reaction counts, and only a same-origin script', () => {
    const html = renderProfilePage(view, 'ar', links, [rec()]);
    expect(html).toContain('<section class="recs rise"');
    expect(html).toContain('aria-pressed="false"');
    expect(html).toContain('class="prog"');
    expect(html).toContain('class="hair"');
    expect(html).toContain('<b dir="ltr">3</b>');
    expect(html).toContain('سورة الإخلاص');
    // CSP script-src 'self': one external same-origin script, no inline script or handlers.
    expect(html.match(/<script/g)).toHaveLength(1);
    expect(html).toContain('<script src="/u/assets/recitations.js" defer></script>');
    expect(html).not.toMatch(/<script>[^<]/);
    expect(html).not.toMatch(/\son[a-z]+=/i);
  });

  it('ayah numbers follow the verified timings (Western digits), only for a range with one start per ayah', () => {
    const html = renderRecitations([rec()], 'ar', links.getApp);
    expect(html).toContain('<ol class="ayat" aria-hidden="true" dir="ltr" data-at="0,2400,5100,8000"><li>1</li><li>2</li><li>3</li><li>4</li></ol>');
    expect(renderRecitations([rec({ ayahStarts: null })], 'ar', links.getApp)).not.toContain('class="ayat"');
    expect(renderRecitations([rec({ ayahStarts: [0, 10] })], 'ar', links.getApp)).not.toContain('class="ayat"'); // wrong length
    expect(renderRecitations([rec({ fromAyah: 2, toAyah: 2, ayahStarts: [0] })], 'ar', links.getApp)).not.toContain('class="ayat"');
  });

  it('uses the app motion tokens: 160/280/450 ms, a 900 ms ring draw on the emphasised curve', () => {
    const html = renderProfilePage(view, 'en', links, [rec()]);
    expect(html).toContain('--t-quick:160ms;--t-std:280ms;--t-emph:450ms;--t-ring:900ms;--ease-emph:cubic-bezier(.2,0,0,1)');
    // The level ring: the track fades in first (quick), then the arc draws (ring, emphasised).
    expect(html).toContain('.ring .track{stroke:var(--track);animation:fade var(--t-quick) var(--ease-out) .2s both}');
    expect(html).toContain('.ring .arc{stroke:var(--gold);stroke-linecap:round;animation:arc var(--t-ring) var(--ease-emph) .36s both}');
    // Recordings: rows rise (emphasised, 40 ms stagger), the glyph morphs and the ring resets on the standard token.
    expect(RECITATIONS_CSS).toContain('animation:rise var(--t-emph) var(--ease-emph) both;animation-delay:calc(.5s + var(--i,0) * 40ms)');
    expect(RECITATIONS_CSS).toContain('transition:clip-path var(--t-std) var(--ease-emph)');
    expect(RECITATIONS_CSS).toContain('transition:stroke-dashoffset var(--t-std) var(--ease-emph)');
    // The hairline turns once per 12 s, and only while playing.
    expect(RECITATIONS_CSS).toContain('animation:hairline 12s linear infinite paused');
    expect(RECITATIONS_CSS).toContain('.rec.playing .hair{opacity:.55;animation-play-state:running}');
    // No legacy timing left on these pieces.
    expect(RECITATIONS_CSS).not.toContain('14s');
    expect(RECITATIONS_CSS).not.toContain('.12s linear');
  });

  it('reduced motion: every animation and transition stops at its end state (page and section)', () => {
    const html = renderProfilePage(view, 'ar', links, [rec()]);
    const blocks = reducedBlocks(html);
    expect(blocks.length).toBeGreaterThanOrEqual(2);
    expect(blocks.join('\n')).toContain('*,*::before,*::after{animation:none!important;transition:none!important}');
    const section = reducedBlocks(RECITATIONS_CSS).join('\n');
    expect(section).toContain('.rec,.rx,.play .hair{animation:none}');
    expect(section).toContain('.ayat li{transition:none}');
    expect(section).toContain('.ayat li.on{transform:none}');
    // The script reads the same preference and stops drawing per frame.
    expect(RECITATIONS_JS).toContain("matchMedia('(prefers-reduced-motion: reduce)')");
  });

  it('is theme-aware: lapis on sky and gold, light gold at night', () => {
    expect(RECITATIONS_CSS).toContain('.recs{--accent:var(--lapis);--on-accent:#fff;');
    expect(RECITATIONS_CSS).toContain('.theme-night .recs{--accent:var(--goldLight);--on-accent:#0A1530}');
    for (const theme of ['sky', 'gold', 'night'] as const) {
      expect(renderProfilePage({ ...view, theme }, 'ar', links, [rec()])).toContain(`<body class="theme-${theme}">`);
    }
  });

  it('ships a script that parses and keeps one player at a time', () => {
    expect(() => new Function(RECITATIONS_JS)).not.toThrow();
    // Starting any recording (button, media keys) pauses the others.
    expect(RECITATIONS_JS).toMatch(/addEventListener\('play',function\(\)\{\s*all\.forEach\(function\(o\)\{var oa=o\.querySelector\('audio'\);if\(o!==el&&oa&&!oa\.paused\)oa\.pause\(\);\}\);/);
  });

  it('the not-found page keeps the same tokens and reduced-motion rule', () => {
    const html = renderNotFoundPage('ar', links);
    expect(html).toContain('--ease-emph:cubic-bezier(.2,0,0,1)');
    expect(html).toContain('prefers-reduced-motion');
  });
});
