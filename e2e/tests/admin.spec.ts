import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { API_URL, fixture, staffContext } from './fixture';

/** Rule 2: admins never see which prayers, azkar or pages someone did. */
const WORSHIP = /الفجر|الظهر|العصر|المغرب|العشاء|أذكار الصباح|أذكار المساء|الورد|وِرد/;

const SECTIONS = [
  { href: '/', label: 'نظرة عامة' },
  { href: '/users', label: 'المستخدمون' },
  { href: '/content', label: 'المحتوى' },
  { href: '/campaigns', label: 'الحملات' },
  { href: '/rewards', label: 'النقاط والمكافآت' },
  { href: '/competitions', label: 'المسابقات' },
  { href: '/analytics', label: 'التحليلات' },
  { href: '/cards', label: 'البطاقات العامة' },
  { href: '/tags', label: 'الميداليات والبطاقات' },
  { href: '/settings', label: 'الإعدادات' },
];

test.describe('admin dashboard', () => {
  for (const s of SECTIONS) {
    test(`${s.href} renders without errors, RTL`, async ({ page }) => {
      const errors: string[] = [];
      page.on('pageerror', (e) => errors.push(e.message));
      const res = await page.goto(s.href);
      expect(res?.status()).toBeLessThan(400);
      // Stayed on the section (a lost session would bounce to /login and then the overview).
      await expect(page).toHaveURL(s.href === '/' ? /:\d+\/$/ : new RegExp(`${s.href}$`));
      await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
      await expect(page.getByRole('link', { name: s.label }).first()).toBeVisible();
      await expect(page.getByText(/Application error|خطأ غير متوقع/)).toHaveCount(0);
      expect(errors).toEqual([]);
    });
  }

  test('sidebar navigates between sections', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: 'المحتوى' }).first().click();
    await expect(page).toHaveURL(/\/content/);
    await page.getByRole('link', { name: 'الميداليات والبطاقات' }).first().click();
    await expect(page).toHaveURL(/\/tags/);
  });

  test('the card directory lists the published card, without worship detail', async ({ page }) => {
    const f = fixture();
    await page.goto('/cards');
    await expect(page.getByText(f.handle).first()).toBeVisible();
    // Rule 2: admins never see which prayers/azkar/pages someone did.
    await expect(page.getByText(/الفجر|الظهر|العصر|المغرب|العشاء|أذكار الصباح/)).toHaveCount(0);
  });

  test('the medal batch and its tag are listed', async ({ page }) => {
    const f = fixture();
    await page.goto('/tags');
    await expect(page.getByText('e2e').first()).toBeVisible();
    await page.goto(`/tags?code=${f.tagCode}`);
    // Codes are shown in two groups of four for reading aloud: E2ET-AG23.
    const row = page.getByRole('row', { name: new RegExp(`${f.tagCode.slice(0, 4)}-${f.tagCode.slice(4)}`) });
    await expect(row).toBeVisible();
    await expect(row).toContainText(`@${f.handle}`);
  });

  test('staff encoding: a session for the batch shows its QR and app link once', async ({ page }) => {
    await page.goto('/tags');
    const panel = page.getByTestId('encode-e2e');
    await page.getByText('ترميز بالهاتف').first().click();
    await panel.getByRole('button', { name: 'فتح جلسة ترميز جديدة' }).click();
    await expect(panel.getByTestId('encode-link')).toHaveText(/^yaqeen:\/\/encode\/[A-Za-z0-9_-]{43}$/);
    await expect(panel.getByRole('img', { name: 'رمز QR لجلسة الترميز' }).locator('svg')).toBeVisible();
    await expect(panel.getByRole('button', { name: 'إيقاف' }).first()).toBeVisible();
  });

  test('overview has no serious accessibility violations', async ({ page }) => {
    await page.goto('/');
    const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    const serious = violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    expect(serious.map((v) => `${v.id}: ${v.nodes.length}`)).toEqual([]);
  });

  test('signing out closes the dashboard', async ({ browser }) => {
    // Own context: signing out must not end the shared session the other tests use.
    const context = await browser.newContext({ storageState: '.auth/admin.json' });
    const page = await context.newPage();
    await page.goto('/');
    await page.getByRole('button', { name: /خروج/ }).first().click();
    await expect(page).toHaveURL(/\/login/);
    await page.goto('/users');
    await expect(page).toHaveURL(/\/login/);
    await context.close();
  });
});

test.describe('competitions «المسابقات»', () => {
  test('tournament standings list the member with snapshot points, without worship detail', async ({ page }) => {
    const f = fixture();
    await page.goto('/competitions');
    await page.getByRole('link', { name: 'التفاصيل' }).first().click();
    await expect(page).toHaveURL(new RegExp(`/competitions/tournaments/${f.tournamentId}$`));
    const row = page.getByRole('row', { name: new RegExp(f.runner.name) });
    await expect(row).toContainText(`@${f.runner.handle}`);
    await expect(row).toContainText('240');
    await expect(row).toContainText('على الطريق'); // level 2 from the public lifetime snapshot
    await expect(page.getByText('يُحدَّث الترتيب كل ليلة').first()).toBeVisible();
    await expect(page.getByText(WORSHIP)).toHaveCount(0);
  });

  test('stats for fewer than 20 participants show «—»', async ({ page }) => {
    const f = fixture();
    await page.goto(`/competitions/tournaments/${f.tournamentId}`);
    const kpis = page.getByTestId('tournament-kpis');
    await expect(kpis).toBeVisible();
    // Two participants: every aggregate is suppressed (K = 20), never the real count.
    await expect(kpis.getByText('—', { exact: true })).toHaveCount(3);
    await expect(kpis.getByText('أقل من 20 — مخفي')).toHaveCount(2);
  });

  test('support hides a photo with a reason; the audit log records competitor.hide_photo', async ({ page, request }) => {
    const f = fixture();
    // Before: the card's photo is public (attested owner, published card).
    expect((await request.get(`${API_URL}/v1/public/avatars/${f.pictured.photoId}/256.webp`)).status()).toBe(200);

    await page.goto(`/competitions?tab=moderation&q=${f.pictured.handle}`);
    const row = page.getByTestId(`competitor-${f.pictured.handle}`);
    await expect(row).toContainText('أكّد العمر: نعم');
    await row.getByText('إجراء', { exact: true }).click();
    await row.getByLabel('إخفاء الصورة').fill('صورة غير لائقة — بلاغ');
    await row.getByRole('button', { name: 'إخفاء الصورة' }).click();
    // The row re-renders with the new state: hidden, and restorable by support for 7 days.
    await expect(row.getByText('الصورة مخفية')).toBeVisible();
    await expect(row.getByRole('button', { name: 'استعادة الصورة' })).toBeVisible();
    await expect(row.locator('img[data-photo-status="removed"]')).toHaveCount(1);

    await page.goto('/settings');
    await expect(page.getByText('competitor.hide_photo').first()).toBeVisible();
  });

  test('a removed photo loads through the admin proxy for support, never cached', async ({ page }) => {
    const f = fixture();
    await page.goto(`/competitions?tab=moderation&filter=hidden&q=${f.removed.handle}`);
    const thumb = page.getByTestId(`competitor-${f.removed.handle}`).locator('img[data-photo-status="removed"]');
    await expect(thumb).toBeVisible();
    await expect.poll(() => thumb.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBeGreaterThan(0);

    const res = await page.request.get(`/api/competitors/${f.removed.id}/photos/${f.removed.photoId}/96`);
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type']).toContain('image/webp');
    expect(res.headers()['cache-control']).toBe('private, no-store');
  });

  test('the user page shows the competitions card with points only', async ({ page }) => {
    const f = fixture();
    await page.goto(`/users/${f.runner.id}`);
    await expect(page.getByRole('heading', { name: 'المسابقات' })).toBeVisible();
    await expect(page.getByText('لا تظهر هنا أي بيانات عبادة — النقاط فقط')).toBeVisible();
    await expect(page.getByText(WORSHIP)).toHaveCount(0);
  });

  test('a marketing admin sees the competitions but no moderation forms or photos', async ({ browser }) => {
    const f = fixture();
    const context = await staffContext(browser, f.tokens.marketing);
    const page = await context.newPage();
    await page.goto(`/competitions/tournaments/${f.tournamentId}`);
    await expect(page.getByRole('row', { name: new RegExp(f.runner.name) })).toBeVisible();
    await expect(page.getByText('إجراء', { exact: true })).toHaveCount(0);

    await page.goto('/competitions?tab=moderation');
    await expect(page.getByTestId(`competitor-${f.runner.handle}`)).toBeVisible();
    await expect(page.getByText('إجراء', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /إخفاء|إيقاف|تجاهل/ })).toHaveCount(0);
    await expect(page.locator('img[data-photo-status]')).toHaveCount(0);
    // The photo route itself is support-only.
    expect((await page.request.get(`/api/competitors/${f.removed.id}/photos/${f.removed.photoId}/96`)).status()).toBe(403);
    await context.close();
  });

  test('a content editor gets 403 on /competitions', async ({ browser }) => {
    const f = fixture();
    const context = await staffContext(browser, f.tokens.content_editor);
    const page = await context.newPage();
    const res = await page.goto('/competitions');
    expect(res?.status()).toBe(403);
    await expect(page.getByText('لا تملك صلاحية هذا القسم')).toBeVisible();
    await page.goto('/content'); // their own section still opens
    await expect(page.getByRole('link', { name: 'المسابقات' })).toHaveCount(0);
    await context.close();
  });

  test('tournament: create → publish → close early with a reason', async ({ page }) => {
    const f = fixture();
    const lastDay = new Date(Date.parse(`${f.today}T00:00:00Z`) + 3 * 86_400_000).toISOString().slice(0, 10);
    const slug = `e2e-flow-${Date.now() % 1_000_000}`;
    await page.goto('/competitions');
    await page.getByRole('link', { name: 'بطولة جديدة' }).click();
    await expect(page).toHaveURL(/\/competitions\/tournaments\/new$/);
    await expect(page.getByText('نص تسويقي فقط — لا آيات ولا أحاديث ولا أدعية').first()).toBeVisible();
    await page.getByLabel(/المعرّف/).fill(slug);
    await page.getByLabel(/العنوان بالعربية/).fill('أيام الخير');
    await page.getByLabel(/Title \(English\)/).fill('Days of good');
    await page.getByLabel('اليوم الأول').fill(f.today);
    await page.getByLabel('اليوم الأخير').fill(lastDay);
    await page.getByLabel(/اسم الشارة بالعربية/).fill('وسام الخير');
    await page.getByLabel(/Badge name \(English\)/).fill('Good days');
    await page.getByRole('button', { name: 'حفظ ونشر' }).click();

    await expect(page).toHaveURL(/\/competitions\/tournaments\/[0-9a-f-]{36}$/);
    await expect(page.getByText('جارية').first()).toBeVisible(); // published and started today

    await page.getByLabel('سبب الإغلاق المبكر').fill('تجربة الإغلاق المبكر');
    await page.getByRole('button', { name: 'إغلاق مبكر' }).click();
    await expect(page.getByText('ستُغلق البطولة عند منتصف الليل')).toBeVisible();

    await page.goto('/settings');
    await expect(page.getByText('tournament.close').first()).toBeVisible();
  });

  test('league settings save from next week; a group page is read-only', async ({ page }) => {
    const f = fixture();
    await page.goto('/competitions?tab=leagues');
    await expect(page.getByText('تُطبَّق التغييرات من الأسبوع القادم').first()).toBeVisible();
    await page.getByLabel('حجم المجموعة (10–50)').fill('24');
    await page.getByRole('button', { name: 'حفظ الإعدادات' }).click();
    await expect(page.getByText('حُفظت — تُطبَّق من الأسبوع القادم')).toBeVisible();
    await page.reload();
    await expect(page.getByLabel('حجم المجموعة (10–50)')).toHaveValue('24');

    await page.goto(`/competitions/leagues/groups/${f.groupId}`);
    const row = page.getByRole('row', { name: new RegExp(f.runner.name) });
    await expect(row).toContainText('180');
    await expect(page.locator('input[name="groupSize"]')).toHaveCount(0);
  });

  test('the level board lists the member with a level ring', async ({ page }) => {
    const f = fixture();
    await page.goto('/competitions?tab=leaderboard');
    const row = page.getByRole('row', { name: new RegExp(f.runner.name) });
    await expect(row.getByRole('img', { name: /المستوى 2/ })).toBeVisible();
  });

  test('/competitions has no serious accessibility violations', async ({ page }) => {
    for (const tab of ['tournaments', 'leagues', 'moderation', 'badges']) {
      await page.goto(`/competitions?tab=${tab}`);
      await expect(page.getByRole('heading', { name: 'المسابقات', level: 1 })).toBeVisible();
      const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
      const serious = violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
      expect(serious.map((v) => `${tab} ${v.id}: ${v.nodes.length}`)).toEqual([]);
    }
  });
});
