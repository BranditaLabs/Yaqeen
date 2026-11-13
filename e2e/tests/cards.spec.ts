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
