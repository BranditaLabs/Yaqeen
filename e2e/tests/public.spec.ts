import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { fixture } from './fixture';

const SITE = ['/', '/privacy', '/terms', '/support', '/delete-account'];

async function noSeriousA11y(page: import('@playwright/test').Page) {
  const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
  return violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => `${v.id}: ${v.nodes.length}`);
}

test.describe('website', () => {
  for (const path of SITE) {
    test(`${path} — Arabic RTL, English twin, Western digits, accessible`, async ({ page }) => {
      const res = await page.goto(path);
      expect(res?.status()).toBe(200);
      await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
      await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
      await expect(page.locator('h1')).toBeVisible();
      expect(await page.locator('body').innerText()).not.toMatch(/[٠-٩]/); // rule 7: Western digits
      expect(await noSeriousA11y(page)).toEqual([]);

      await page.goto(`${path}${path.includes('?') ? '&' : '?'}lang=en`);
      await expect(page.locator('html')).toHaveAttribute('lang', 'en');
      await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
    });
  }

  test('robots.txt and sitemap.xml', async ({ request }) => {
    expect((await request.get('/robots.txt')).status()).toBe(200);
    const sitemap = await request.get('/sitemap.xml');
    expect(sitemap.status()).toBe(200);
    expect(await sitemap.text()).toContain('/privacy');
  });
});

test.describe('public card «بطاقة يقين»', () => {
  test('a published card renders, and markup in the bio stays text', async ({ page }) => {
    const f = fixture();
    const res = await page.goto(`/u/${f.handle}`);
    expect(res?.status()).toBe(200);
    await expect(page.getByText('عبد الله').first()).toBeVisible();
    await expect(page.getByText('<img src=x onerror="window.__xss=1">نسأل الله الثبات')).toBeVisible();
    expect(await page.evaluate(() => (window as unknown as { __xss?: number }).__xss)).toBeUndefined();
    expect(await page.locator('script').count()).toBe(0); // the page ships no scripts or trackers
    expect(await page.locator('meta[name="robots"]').getAttribute('content')).toContain('noindex');
    expect(await noSeriousA11y(page)).toEqual([]);
  });

  test('unknown handles and codes answer 404 the same way', async ({ request }) => {
    expect((await request.get('/u/no-such-handle-e2e')).status()).toBe(404);
    expect((await request.get('/t/ZZZZZZZZ', { maxRedirects: 0 })).status()).toBe(404);
  });

  test('a medal code follows its owner to the card', async ({ page }) => {
    const f = fixture();
    await page.goto(`/t/${f.tagCode}`);
    await expect(page).toHaveURL(new RegExp(`/u/${f.handle}`));
  });
});
