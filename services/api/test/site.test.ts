/**
 * The public website: both languages, no scripts, Western digits, placeholders kept visible until
 * the owner sets them, robots/sitemap — and it stays up without the database.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb } from '../src/db/client.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';

async function build(extra: Record<string, string> = {}): Promise<FastifyInstance> {
  // No database on purpose: the site must render without it.
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: 'postgres://nobody:nothing@127.0.0.1:1/none', PUBLIC_PROFILE_BASE_URL: 'https://yaqeen.test', ...extra });
  return buildApp({
    env,
    db: createDb(env.DATABASE_URL).db,
    redis: null,
    aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
    shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
    fcm: new FcmSender(''),
    now: () => new Date('2026-10-27T08:00:00Z'),
  });
}

describe('website', () => {
  let app: FastifyInstance;
  beforeAll(async () => (app = await build()));
  afterAll(async () => app.close());

  it.each(['/', '/privacy', '/terms', '/support', '/delete-account'])('%s renders in Arabic (RTL) and English, without scripts', async (url) => {
    const ar = await app.inject({ method: 'GET', url });
    expect(ar.statusCode).toBe(200);
    expect(ar.headers['content-type']).toContain('text/html');
    expect(ar.body).toContain('<html lang="ar" dir="rtl">');
    expect(ar.body).not.toMatch(/<script/i);
    expect(ar.body).not.toMatch(/[٠-٩]/); // Western digits only
    const en = await app.inject({ method: 'GET', url: `${url}?lang=en` });
    expect(en.body).toContain('<html lang="en" dir="ltr">');
    const byHeader = await app.inject({ method: 'GET', url, headers: { 'accept-language': 'en-GB,en;q=0.9' } });
    expect(byHeader.body).toContain('lang="en"');
  });

  it('privacy policy states the worship rules and keeps unknown facts bracketed', async () => {
    const en = (await app.inject({ method: 'GET', url: '/privacy?lang=en' })).body;
    expect(en).toContain('never any worship activity');
    expect(en).toContain('[legal entity name]');
    expect(en).toContain('[support email]');
    expect(en).toContain('30 days');
    const ar = (await app.inject({ method: 'GET', url: '/privacy' })).body;
    expect(ar).toContain('[الاسم القانوني للشركة]');
  });

  it('robots keep cards and the API out of search; the sitemap lists both languages', async () => {
    const robots = await app.inject({ method: 'GET', url: '/robots.txt' });
    expect(robots.body).toContain('Disallow: /u/');
    expect(robots.body).toContain('Sitemap: https://yaqeen.test/sitemap.xml');
    const map = await app.inject({ method: 'GET', url: '/sitemap.xml' });
    expect(map.body).toContain('https://yaqeen.test/privacy?lang=ar');
    expect(map.body).toContain('https://yaqeen.test/delete-account?lang=en');
  });

  it('home links to the app and the store (UTM-tagged)', async () => {
    const res = await app.inject({ method: 'GET', url: '/' });
    expect(res.body).toContain('href="https://yaqeen.test/get-app"');
    expect(res.body).toContain('utm_source=yaqeen_site');
  });

  it('the support email appears once the owner sets it', async () => {
    const withMail = await build({ SUPPORT_EMAIL: 'help@yaqeen.test' });
    const res = await withMail.inject({ method: 'GET', url: '/support?lang=en' });
    expect(res.body).toContain('mailto:help@yaqeen.test');
    expect(res.body).not.toContain('[support email]');
    await withMail.close();
  });
});
