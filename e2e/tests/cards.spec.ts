import { expect, test } from '@playwright/test';
import { fixture } from './fixture';

// Runs after the admin project, whose «إخفاء الصورة» test hides the pictured member's photo.
test.describe('public card «بطاقة يقين» — avatar and level ring', () => {
  test('the card draws the member avatar inside the level ring', async ({ page }) => {
    const f = fixture();
    const res = await page.goto(`/u/${f.runner.handle}`);
    expect(res?.status()).toBe(200);
    const medallion = page.locator('.medallion');
    await expect(medallion.locator('svg.ring')).toHaveCount(1); // the level ring (public lifetime snapshot)
    const avatar = medallion.locator('img.avatar');
    await expect(avatar).toHaveAttribute('src', '/u/assets/avatars/m03.webp');
    await expect.poll(() => avatar.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBeGreaterThan(0);
  });

  test('after support hides a photo, its public URL answers 404 and the card falls back', async ({ page, request }) => {
    const f = fixture();
    for (const size of [96, 256]) {
      expect((await request.get(`/v1/public/avatars/${f.pictured.photoId}/${size}.webp`)).status()).toBe(404);
    }
    const res = await page.goto(`/u/${f.pictured.handle}`);
    expect(res?.status()).toBe(200);
    await expect(page.locator(`.medallion img[src*="${f.pictured.photoId}"]`)).toHaveCount(0);
  });
});

/** A short quiet tone as 8-bit PCM WAV: decodes in every Chromium build (the stored audio is a stub). */
function toneWav(seconds: number): Buffer {
  const rate = 8000;
  const n = Math.round(rate * seconds);
  const b = Buffer.alloc(44 + n);
  b.write('RIFF', 0, 'latin1');
  b.writeUInt32LE(36 + n, 4);
  b.write('WAVEfmt ', 8, 'latin1');
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); // PCM
  b.writeUInt16LE(1, 22); // mono
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate, 28);
  b.writeUInt16LE(1, 32);
  b.writeUInt16LE(8, 34);
  b.write('data', 36, 'latin1');
  b.writeUInt32LE(n, 40);
  for (let i = 0; i < n; i++) b[44 + i] = 128 + Math.round(6 * Math.sin((2 * Math.PI * 440 * i) / rate));
  return b;
}

test.describe('public card «بطاقة يقين» — «تلاواتي» player', () => {
  const C = 2 * Math.PI * 26; // the play button's ring circumference

  async function open(page: import('@playwright/test').Page) {
    const f = fixture();
    const problems: string[] = [];
    page.on('pageerror', (e) => problems.push(e.message));
    page.on('console', (m) => {
      if (m.type() === 'error' || /Content Security Policy/i.test(m.text())) problems.push(m.text());
    });
    await page.route('**/u/*/r/*.m4a', (route) => route.fulfill({ status: 200, contentType: 'audio/wav', body: toneWav(1.6) }));
    const res = await page.goto(`/u/${f.cardRecitations.handle}`);
    expect(res?.status()).toBe(200);
    // The player is a same-origin script under the page's CSP (script-src 'self', media-src 'self').
    expect(res?.headers()['content-security-policy']).toContain("script-src 'self'");
    const first = page.locator('.rec').filter({ has: page.locator(`audio[src$="${f.cardRecitations.first}.m4a"]`) });
    const second = page.locator('.rec').filter({ has: page.locator(`audio[src$="${f.cardRecitations.second}.m4a"]`) });
    await expect(page.locator('.recs')).toBeVisible();
    await expect(page.locator('.rec')).toHaveCount(2);
    return { first, second, problems };
  }

  const offset = (row: import('@playwright/test').Locator) => row.locator('.prog').evaluate((el) => parseFloat(getComputedStyle(el).strokeDashoffset));
  const hairState = (row: import('@playwright/test').Locator) => row.locator('.hair').evaluate((el) => getComputedStyle(el).animationPlayState);
  const lit = (row: import('@playwright/test').Locator) => row.locator('.ayat li.on').evaluateAll((els) => els.map((e) => e.textContent));

  test('plays one recitation at a time: ring, hairline and ayah numbers follow, then it resets', async ({ page }) => {
    const { first, second, problems } = await open(page);
    await expect(first.locator('.ayat li')).toHaveText(['1', '2', '3', '4']);
    // Rows rise on the emphasised token with their stagger, even where scroll-driven animations exist.
    expect(await first.evaluate((el) => getComputedStyle(el).animationName)).toBe('rise');
    // On the Arabic card the numbers run right to left, in the reading direction (like the rings).
    expect(await page.locator('html').getAttribute('dir')).toBe('rtl');
    const xs = await first.locator('.ayat li').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().left));
    expect(xs[0]!).toBeGreaterThan(xs[1]!);
    expect(xs[1]!).toBeGreaterThan(xs[2]!);
    await expect(first.locator('.play')).toHaveAttribute('aria-pressed', 'false');
    expect(await hairState(first)).toBe('paused');

    await first.locator('.play').click();
    await expect(first).toHaveClass(/playing/);
    await expect(first.locator('.play')).toHaveAttribute('aria-pressed', 'true');
    expect(await hairState(first)).toBe('running');
    await expect.poll(() => offset(first)).toBeLessThan(C - 1); // the progress ring draws
    await expect.poll(async () => Number((await lit(first))[0] ?? 0)).toBeGreaterThanOrEqual(2); // ayah 2+ lit by its timing
    expect(await first.locator('.ayat li.on').count()).toBe(1);
    expect(await first.locator('.ayat li.done').count()).toBeGreaterThanOrEqual(1);

    // Starting the second pauses the first.
    await second.locator('.play').click();
    await expect(second).toHaveClass(/playing/);
    await expect(first).not.toHaveClass(/playing/);
    await expect(first.locator('.play')).toHaveAttribute('aria-pressed', 'false');
    expect(await page.locator('.rec.playing').count()).toBe(1);

    // At the end: back to play, ring and ayah numbers reset.
    await expect(second).not.toHaveClass(/playing/, { timeout: 8_000 });
    await expect(second.locator('.play')).toHaveAttribute('aria-pressed', 'false');
    await expect.poll(() => offset(second)).toBeGreaterThan(C - 0.5);
    await expect(second.locator('.ayat li.on')).toHaveCount(0);
    expect(problems).toEqual([]);
  });

  test('reduced motion: static end states, the player still works', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const { first, problems } = await open(page);
    const none = (sel: string) => page.locator(sel).first().evaluate((el) => getComputedStyle(el).animationName);
    expect(await none('.ring .arc')).toBe('none');
    expect(await none('.rec')).toBe('none');
    // The level ring shows its final arc at once.
    const dash = await page.locator('.ring .arc').evaluate((el) => getComputedStyle(el).strokeDasharray);
    expect(dash).not.toMatch(/^0(px)?[ ,]/);
    await first.locator('.play').click();
    await expect(first).toHaveClass(/playing/);
    expect(await first.locator('.hair').evaluate((el) => getComputedStyle(el).animationName)).toBe('none');
    expect(await first.locator('.prog').evaluate((el) => getComputedStyle(el).transitionDuration)).toBe('0s');
    await expect.poll(() => offset(first)).toBeLessThan(C - 1); // progress steps on timeupdate
    await expect(first).not.toHaveClass(/playing/, { timeout: 8_000 });
    expect(problems).toEqual([]);
  });
});
