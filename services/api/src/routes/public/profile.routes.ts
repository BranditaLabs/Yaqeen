/**
 * Public profile cards for NFC tags and QR codes (no auth):
 *   GET /u/:handle                 the card as an HTML page (also the CTA to the app and the store)
 *   GET /v1/public/profiles/:handle the same data as JSON (in-app preview, link unfurlers)
 *   GET /get-app                   smart link: the right app store for the visitor's phone
 *   GET /u/assets/icon.png         share image
 *   GET /go/store                  the page's shop button: counts the click, then the store (UTM-tagged)
 *   GET /t/:code                   a physical tag (medal/card): → /u/<handle>, or how to activate it
 * Only published cards of active accounts resolve; everything else is a friendly 404 page.
 */
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { PROFILE_HANDLE, TagCode } from '@yaqeen/contracts';
import { sendCachedJson } from '../../lib/cache.js';
import { notFound } from '../../lib/errors.js';
import * as profile from '../../services/profile.service.js';
import * as tags from '../../services/tags.service.js';
import * as cardStats from '../../services/card-stats.service.js';
import { cardFeatureOn, readCardsSettings, storeUrl } from '../../services/cards-settings.service.js';
import { BRAND_PNG } from '../../web/brand-assets.js';
import { type PageLang, pickLang, renderActivatePage, renderNotFoundPage, renderProfilePage, type PageLinks } from '../../web/profile-page.js';

const HandleParam = z.object({ handle: z.string().min(1).max(40) });
const BOT = /bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|preview|curl|wget|headless/i;

export const profileRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  const base = () => ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '');

  /** Page links; the shop button goes through `/go/store` so clicks are counted (a number only). */
  async function links(handle: string | null, lang: PageLang, src: 'card' | 'medal' | 'missing'): Promise<PageLinks> {
    const ref = handle ? `ref=${encodeURIComponent(handle)}` : '';
    const s = await readCardsSettings(ctx);
    return {
      getApp: `${base()}/get-app${ref ? `?${ref}` : ''}`,
      store: `${base()}/go/store?src=${src}${ref ? `&${ref}` : ''}`,
      self: handle ? `${base()}/u/${handle}` : base(),
      image: `${base()}/u/assets/icon.png`,
      copy: lang === 'ar' ? { ctaTitle: s.ctaTitleAr, ctaBody: s.ctaBodyAr } : { ctaTitle: s.ctaTitleEn, ctaBody: s.ctaBodyEn },
    };
  }
  const human = (req: FastifyRequest) => !BOT.test(String(req.headers['user-agent'] ?? ''));

  const viewOf = (handle: string) =>
    ctx.cache.getJson('profile', `view:${handle.toLowerCase()}`, 60, () => profile.publicView(ctx, handle));

  app.get('/v1/public/profiles/:handle', async (req, reply) => {
    const { handle } = HandleParam.parse(req.params);
    if (!(await cardFeatureOn(ctx, 'publicCards'))) throw notFound('profile');
    const json = await viewOf(handle);
    if (json === 'null') throw notFound('profile');
    return sendCachedJson(req, reply, json, 60);
  });

  app.get('/u/:handle', async (req: FastifyRequest, reply) => {
    const { handle } = HandleParam.parse(req.params);
    const { lang: q } = z.object({ lang: z.string().optional() }).parse(req.query);
    const lang = pickLang(q, req.headers['accept-language']);
    const json = (await cardFeatureOn(ctx, 'publicCards')) ? await viewOf(handle) : 'null';
    reply.header('Vary', 'Accept-Language');
    reply.type('text/html; charset=utf-8');
    if (json === 'null') {
      reply.header('Cache-Control', 'public, max-age=60');
      return reply.code(404).send(renderNotFoundPage(lang, await links(null, lang, 'missing')));
    }
    const view = JSON.parse(json);
    if (human(req)) {
      profile.countView(ctx, handle).catch((err) => req.log.warn({ err }, 'profile view count failed'));
      cardStats.bumpLater(ctx, 'page_open', req.log);
    }
    // Short cache: an edit or unpublish shows within a minute even behind a CDN.
    reply.header('Cache-Control', 'public, max-age=60, stale-while-revalidate=120');
    return reply.code(200).send(renderProfilePage(view, lang, await links(view.handle, lang, 'card')));
  });

  /**
   * A physical tag (key medal / card). Linked → the owner's card under its current handle; blank →
   * how to activate it; switched off, unknown or hidden card → the friendly 404 with the app CTA.
   */
  app.get('/t/:code', async (req, reply) => {
    const parsed = TagCode.safeParse((req.params as { code?: string }).code ?? '');
    const { lang: q } = z.object({ lang: z.string().optional() }).parse(req.query);
    const lang = pickLang(q, req.headers['accept-language']);
    reply.header('Vary', 'Accept-Language');
    reply.header('Cache-Control', 'no-store'); // the owner can relink, rename or hide at any time
    const target = parsed.success ? await tags.resolve(ctx, parsed.data) : ({ state: 'missing' } as const);
    if (target.state === 'linked' && target.handle && (await cardFeatureOn(ctx, 'publicCards'))) {
      if (human(req)) {
        tags.countScan(ctx, parsed.data!).catch((err) => req.log.warn({ err }, 'tag scan count failed'));
        cardStats.bumpLater(ctx, 'tag_scan', req.log);
      }
      return reply.redirect(`${base()}/u/${target.handle}${q ? `?lang=${encodeURIComponent(q)}` : ''}`, 302);
    }
    reply.type('text/html; charset=utf-8');
    if (target.state === 'unclaimed') {
      if (human(req)) cardStats.bumpLater(ctx, 'activation_open', req.log);
      return reply.code(200).send(renderActivatePage(parsed.data!, target.kind, lang, await links(null, lang, 'medal')));
    }
    return reply.code(404).send(renderNotFoundPage(lang, await links(null, lang, 'missing')));
  });

  app.get('/get-app', async (req, reply) => {
    const ua = String(req.headers['user-agent'] ?? '');
    const ios = /iphone|ipad|ipod/i.test(ua);
    const android = /android/i.test(ua);
    const target = ios ? ctx.env.APP_STORE_URL || ctx.env.STORE_URL : android ? ctx.env.PLAY_STORE_URL : ctx.env.STORE_URL;
    if (human(req)) cardStats.bumpLater(ctx, 'get_app', req.log);
    reply.header('Cache-Control', 'no-store');
    return reply.redirect(target, 302);
  });

  /** The card / medal page's «shop» button: counts the click, then the store with attribution tags. */
  app.get('/go/store', async (req, reply) => {
    const q = z
      .object({ src: z.enum(['card', 'medal', 'missing']).catch('card'), ref: z.string().regex(PROFILE_HANDLE).optional().catch(undefined) })
      .parse(req.query);
    const store = new URL(await storeUrl(ctx));
    store.searchParams.set('utm_source', 'yaqeen_card');
    store.searchParams.set('utm_medium', q.src === 'medal' ? 'medal' : 'nfc');
    if (q.ref) store.searchParams.set('utm_campaign', q.ref);
    if (human(req)) cardStats.bumpLater(ctx, 'store_click', req.log);
    reply.header('Cache-Control', 'no-store');
    return reply.redirect(store.toString(), 302);
  });

  app.get('/u/assets/icon.png', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=604800, immutable');
    reply.type('image/png');
    return reply.send(Buffer.from(BRAND_PNG.icon, 'base64'));
  });
};
