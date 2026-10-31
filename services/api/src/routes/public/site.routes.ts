/**
 * The public website (spec §5.29) on the cards host:
 *   GET /  /privacy  /terms  /support  /delete-account   (Arabic by default; ?lang=en)
 *   GET /robots.txt  /sitemap.xml
 * Static per language, cached at the edge for an hour. The app's privacy/terms/help links, the
 * store listings and Google Play's account-deletion URL all point here.
 */
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { storeUrl } from '../../services/cards-settings.service.js';
import { pickLang } from '../../web/profile-page.js';
import {
  renderDeleteAccount,
  renderHome,
  renderPrivacy,
  renderSupport,
  renderTerms,
  robotsTxt,
  sitemapXml,
  type SiteLinks,
} from '../../web/site-pages.js';

const PAGES = {
  '/': renderHome,
  '/privacy': renderPrivacy,
  '/terms': renderTerms,
  '/support': renderSupport,
  '/delete-account': renderDeleteAccount,
} as const;

export const siteRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  const base = () => ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '');

  async function links(): Promise<SiteLinks> {
    // The site stays up without the database: fall back to the configured store.
    const store = new URL(await storeUrl(ctx).catch(() => ctx.env.STORE_URL));
    store.searchParams.set('utm_source', 'yaqeen_site');
    return { base: base(), getApp: `${base()}/get-app`, store: store.toString(), supportEmail: ctx.env.SUPPORT_EMAIL };
  }

  for (const [url, render] of Object.entries(PAGES)) {
    app.get(url, async (req: FastifyRequest, reply: FastifyReply) => {
      const { lang: q } = z.object({ lang: z.string().optional() }).parse(req.query);
      const lang = pickLang(q, req.headers['accept-language']);
      reply.header('Vary', 'Accept-Language');
      reply.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
      reply.type('text/html; charset=utf-8');
      return render(lang, await links());
    });
  }

  app.get('/robots.txt', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=86400');
    return reply.type('text/plain; charset=utf-8').send(robotsTxt(base()));
  });
  app.get('/sitemap.xml', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=86400');
    return reply.type('application/xml; charset=utf-8').send(sitemapXml(base()));
  });
};
