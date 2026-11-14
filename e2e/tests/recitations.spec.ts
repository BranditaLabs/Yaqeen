import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { fixture, staffContext } from './fixture';

/** A server action round trip: the API write, then the revalidated page re-rendered. */
const ACTION = 20_000;

test.describe('«التلاوات» moderation queue', () => {
  test('lists only queued items, plays audio through the proxy, passes axe', async ({ page }) => {
    const f = fixture();
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const res = await page.goto('/recitations');
    expect(res?.status()).toBeLessThan(400);
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await expect(page.getByRole('heading', { name: 'التلاوات' }).first()).toBeVisible();
    const flagged = page.getByTestId(`recording-${f.recitations.flagged}`);
    await expect(flagged.getByText('سورة الإخلاص · الآيات 1–4')).toBeVisible();
    await expect(flagged.getByText('علّمها الفحص الآلي')).toBeVisible();
    await expect(flagged.getByText('نص تجريبي من الفحص الآلي')).toBeVisible();
    await expect(page.getByTestId(`recording-${f.recitations.held}`).getByText('محجوبة بالبلاغات')).toBeVisible();
    await expect(page.getByTestId(`comment-${f.recitations.comment}`).getByText('مخفي تلقائياً')).toBeVisible();
    // The player streams from the admin proxy, which the API allows only while the item is queued.
    await expect(flagged.locator('audio')).toHaveAttribute('src', `/api/recitations/${f.recitations.flagged}/audio`);
    const audio = await page.request.get(`/api/recitations/${f.recitations.flagged}/audio`);
    expect(audio.status()).toBe(200);
    expect(audio.headers()['content-type']).toContain('audio/mp4');
    expect(audio.headers()['cache-control']).toContain('no-store');
    expect((await page.request.get('/api/recitations/00000000-0000-4000-8000-000000000000/audio')).status()).toBe(404);
    const axe = await new AxeBuilder({ page }).include('main').analyze();
    expect(axe.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical')).toEqual([]);
    expect(errors).toEqual([]);
  });

  test('marketing has no access; support cannot approve, the reviewer can', async ({ browser }) => {
    const f = fixture();
    const marketing = await staffContext(browser, f.tokens.marketing);
    const mp = await marketing.newPage();
    const r = await mp.goto('/recitations');
    expect(r?.status()).toBe(403);
    await marketing.close();

    const support = await staffContext(browser, f.tokens.support);
    const sp = await support.newPage();
    await sp.goto('/recitations');
    await expect(sp.getByTestId(`recording-${f.recitations.flagged}`).getByRole('button', { name: 'اعتماد' })).toHaveCount(0);
    await support.close();

    const reviewer = await staffContext(browser, f.recitations.reviewerToken);
    const rp = await reviewer.newPage();
    await rp.goto('/recitations');
    const item = rp.getByTestId(`recording-${f.recitations.flagged}`);
    // Comments and reports are support's: the reviewer sees them without actions.
    await expect(rp.getByTestId(`comment-${f.recitations.comment}`).getByRole('button')).toHaveCount(0);
    await item.getByLabel('سبب القرار').first().fill('استمعت: تطابق الآيات');
    await item.getByRole('button', { name: 'اعتماد' }).click();
    await expect(rp.getByTestId(`recording-${f.recitations.flagged}`)).toHaveCount(0, { timeout: ACTION });
    await reviewer.close();
  });

  test('support removes the reported comment and dismisses the reports on the held recording', async ({ browser }) => {
    const f = fixture();
    const support = await staffContext(browser, f.tokens.support);
    const page = await support.newPage();
    await page.goto('/recitations');
    const comment = page.getByTestId(`comment-${f.recitations.comment}`);
    await comment.getByLabel('سبب القرار').fill('تعليق مسيء');
    await comment.getByRole('button', { name: 'إزالة التعليق' }).click();
    await expect(page.getByTestId(`comment-${f.recitations.comment}`).getByText('أُزيل')).toBeVisible({ timeout: ACTION });

    const held = page.getByTestId(`recording-${f.recitations.held}`);
    await held.getByLabel('سبب القرار').fill('البلاغات غير صحيحة');
    await held.getByRole('button', { name: 'إسقاط البلاغات' }).click();
    await expect(page.getByTestId(`recording-${f.recitations.held}`)).toHaveCount(0, { timeout: ACTION });
    // Once out of the queue, its audio is closed to admins.
    expect((await page.request.get(`/api/recitations/${f.recitations.held}/audio`)).status()).toBe(404);
    await support.close();
  });
});
