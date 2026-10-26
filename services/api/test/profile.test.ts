/**
 * Public profile card: pure logic (levels, social links, language) and the page renderer.
 * DB-backed behaviour (publish, privacy, counting) is in profile.db.test.ts.
 */
import { describe, expect, it } from 'vitest';
import { levelFor, PublicProfileUpdate, socialUrl, type PublicProfileView } from '@yaqeen/contracts';
import { escapeHtml, pickLang, renderNotFoundPage, renderProfilePage } from '../src/web/profile-page.js';

const links = { getApp: 'https://x.test/get-app?ref=ahmed', store: 'https://store.test/?utm_source=yaqeen_card', self: 'https://x.test/u/ahmed', image: 'https://x.test/u/assets/icon.png' };

const view: PublicProfileView = {
  handle: 'ahmed',
  displayName: 'أحمد <script>',
  bio: 'سطر\nثانٍ',
  links: [
    { kind: 'instagram', value: '@ahmed.y' },
    { kind: 'website', value: 'javascript:alert(1)' },
    { kind: 'whatsapp', value: '+20 100 123 4567' },
  ],
  theme: 'sky',
  level: { level: 3, nameAr: 'مواظب', nameEn: 'Steadfast', progress: 0.4 },
  streak: 12,
  challengeDay: { day: 47, of: 365 },
  badges: [7, 30],
  memberSince: '2026-09-04',
};

describe('levels', () => {
  it('come from lifetime points with progress toward the next', () => {
    expect(levelFor(0)).toMatchObject({ level: 1, nextAt: 500, progress: 0 });
    expect(levelFor(1250)).toMatchObject({ level: 2, nameEn: 'On the path', nextAt: 2000 });
    expect(levelFor(1250).progress).toBeCloseTo(0.5);
    expect(levelFor(99_999)).toMatchObject({ level: 6, nameAr: 'منارة', nextAt: null, progress: 1 });
  });
});

describe('contract', () => {
  it('normalises the handle and rejects bad ones', () => {
    const base = { published: true, displayName: 'Ahmed' };
    expect(PublicProfileUpdate.parse({ ...base, handle: '  Ahmed.Y ' }).handle).toBe('ahmed.y');
    expect(PublicProfileUpdate.safeParse({ ...base, handle: '1abc' }).success).toBe(false);
    expect(PublicProfileUpdate.safeParse({ ...base, handle: 'ab' }).success).toBe(false);
    expect(PublicProfileUpdate.safeParse({ ...base, handle: 'أحمد' }).success).toBe(false);
  });

  it('defaults keep everything but the level private', () => {
    expect(PublicProfileUpdate.parse({ published: false, handle: 'ahmed', displayName: 'A' }).show).toEqual({
      level: true,
      streak: false,
      challengeDay: false,
      badges: false,
      memberSince: false,
    });
  });
});

describe('social links', () => {
  it('build https URLs and refuse anything else', () => {
    expect(socialUrl({ kind: 'instagram', value: '@ahmed.y' })).toBe('https://instagram.com/ahmed.y');
    expect(socialUrl({ kind: 'tiktok', value: 'ahmed' })).toBe('https://www.tiktok.com/@ahmed');
    expect(socialUrl({ kind: 'whatsapp', value: '+20 100 123 4567' })).toBe('https://wa.me/201001234567');
    expect(socialUrl({ kind: 'website', value: 'yaqin-brand.com/about' })).toBe('https://yaqin-brand.com/about');
    expect(socialUrl({ kind: 'website', value: 'javascript:alert(1)' })).toBeNull();
    expect(socialUrl({ kind: 'x', value: 'https://x.com/someone' })).toBe('https://x.com/someone');
    expect(socialUrl({ kind: 'x', value: 'http://evil.test' })).toBeNull(); // never plain http
  });
});

describe('page', () => {
  it('picks the visitor language', () => {
    expect(pickLang(undefined, 'en-US,en;q=0.9')).toBe('en');
    expect(pickLang(undefined, 'ar-EG')).toBe('ar');
    expect(pickLang('en', 'ar')).toBe('en');
    expect(pickLang(undefined, undefined)).toBe('ar');
  });

  it('escapes user text, drops unsafe links and shows only what was shared', () => {
    const html = renderProfilePage(view, 'ar', links);
    expect(html).toContain('dir="rtl"');
    expect(html).toContain('أحمد &lt;script&gt;');
    expect(html).not.toContain('<script>');
    expect(html).not.toContain('javascript:');
    expect(html).toContain('https://instagram.com/ahmed.y');
    expect(html).toContain('https://wa.me/201001234567');
    expect(html).toContain('مواظب · المستوى 3');
    expect(html).toContain('اليوم 47 من 365');
    expect(html).toContain('30 يوماً');
    expect(html).toContain('href="https://x.test/get-app?ref=ahmed"');
    expect(html).toContain('noindex');

    const minimal = renderProfilePage({ ...view, level: null, streak: null, challengeDay: null, badges: null, memberSince: null }, 'en', links);
    expect(minimal).toContain('dir="ltr"');
    expect(minimal).not.toContain('class="stats');
    expect(minimal).not.toContain('Level');
    expect(minimal).toContain('Get the Yaqeen app');
  });

  it('a missing card still invites to the app and the store', () => {
    const html = renderNotFoundPage('ar', links);
    expect(html).toContain('هذه البطاقة غير متاحة');
    expect(html).toContain('تسوّق من متجر يقين');
  });

  it('escapeHtml covers attribute breakers', () => {
    expect(escapeHtml(`"'<>&\``)).toBe('&quot;&#39;&lt;&gt;&amp;&#96;');
  });
});
