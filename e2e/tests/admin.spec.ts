import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { fixture } from './fixture';

const SECTIONS = [
  { href: '/', label: 'نظرة عامة' },
  { href: '/users', label: 'المستخدمون' },
  { href: '/content', label: 'المحتوى' },
  { href: '/campaigns', label: 'الحملات' },
  { href: '/rewards', label: 'النقاط والمكافآت' },
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
