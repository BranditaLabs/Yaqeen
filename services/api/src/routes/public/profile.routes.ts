/**
 * Public profile cards for NFC tags and QR codes (no auth):
 *   GET /u/:handle                 the card as an HTML page (also the CTA to the app and the store)
 *   GET /v1/public/profiles/:handle the same data as JSON (in-app preview, link unfurlers)
 *   GET /get-app                   smart link: the right app store for the visitor's phone
 *   GET /u/assets/icon.png         share image
 *   GET /t/:code                   a physical tag (medal/card): → /u/<handle>, or how to activate it
 * Only published cards of active accounts resolve; everything else is a friendly 404 page.
 */
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { TagCode } from '@yaqeen/contracts';
import { sendCachedJson } from '../../lib/cache.js';
import { notFound } from '../../lib/errors.js';
import * as profile from '../../services/profile.service.js';
import * as tags from '../../services/tags.service.js';
import { BRAND_PNG } from '../../web/brand-assets.js';
import { pickLang, renderActivatePage, renderNotFoundPage, renderProfilePage, type PageLinks } from '../../web/profile-page.js';

const HandleParam = z.object({ handle: z.string().min(1).max(40) });
const BOT = /bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|preview|curl|wget|headless/i;

export const profileRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  const base = () => ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '');

  function links(handle: string | null): PageLinks {
    const ref = handle ? `?ref=${encodeURIComponent(handle)}` : '';
    const store = new URL(ctx.env.STORE_URL);
    store.searchParams.set('utm_source', 'yaqeen_card');
    store.searchParams.set('utm_medium', 'nfc');
    if (handle) store.searchParams.set('utm_campaign', handle);
    return {
      getApp: `${base()}/get-app${ref}`,
      store: store.toString(),
      self: handle ? `${base()}/u/${handle}` : base(),
      image: `${base()}/u/assets/icon.png`,
    };
  }

  const viewOf = (handle: string) =>
    ctx.cache.getJson('profile', `view:${handle.toLowerCase()}`, 60, () => profile.publicView(ctx, handle));

  app.get('/v1/public/profiles/:handle', async (req, reply) => {
    const { handle } = HandleParam.parse(req.params);
    const json = await viewOf(handle);
    if (json === 'null') throw notFound('profile');
    return sendCachedJson(req, reply, json, 60);
  });

  app.get('/u/:handle', async (req: FastifyRequest, reply) => {
    const { handle } = HandleParam.parse(req.params);
    const { lang: q } = z.object({ lang: z.string().optional() }).parse(req.query);
    const lang = pickLang(q, req.headers['accept-language']);
    const json = await viewOf(handle);
    reply.header('Vary', 'Accept-Language');
    reply.type('text/html; charset=utf-8');
    if (json === 'null') {
      reply.header('Cache-Control', 'public, max-age=60');
      return reply.code(404).send(renderNotFoundPage(lang, links(null)));
    }
    const view = JSON.parse(json);
    if (!BOT.test(String(req.headers['user-agent'] ?? ''))) {
      profile.countView(ctx, handle).catch((err) => req.log.warn({ err }, 'profile view count failed'));
    }
    // Short cache: an edit or unpublish shows within a minute even behind a CDN.
    reply.header('Cache-Control', 'public, max-age=60, stale-while-revalidate=120');
    return reply.code(200).send(renderProfilePage(view, lang, links(view.handle)));
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
    if (target.state === 'linked' && target.handle) {
      if (!BOT.test(String(req.headers['user-agent'] ?? ''))) {
        tags.countScan(ctx, parsed.data!).catch((err) => req.log.warn({ err }, 'tag scan count failed'));
      }
      return reply.redirect(`${base()}/u/${target.handle}${q ? `?lang=${encodeURIComponent(q)}` : ''}`, 302);
    }
    reply.type('text/html; charset=utf-8');
    if (target.state === 'unclaimed') return reply.code(200).send(renderActivatePage(parsed.data!, target.kind, lang, links(null)));
    return reply.code(404).send(renderNotFoundPage(lang, links(null)));
  });

  app.get('/get-app', async (req, reply) => {
    const ua = String(req.headers['user-agent'] ?? '');
    const ios = /iphone|ipad|ipod/i.test(ua);
    const android = /android/i.test(ua);
    const target = ios ? ctx.env.APP_STORE_URL || ctx.env.STORE_URL : android ? ctx.env.PLAY_STORE_URL : ctx.env.STORE_URL;
    reply.header('Cache-Control', 'no-store');
    return reply.redirect(target, 302);
  });

  app.get('/u/assets/icon.png', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=604800, immutable');
    reply.type('image/png');
    return reply.send(Buffer.from(BRAND_PNG.icon, 'base64'));
  });
};
