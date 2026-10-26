/**
 * The public profile page («بطاقة يقين») opened by an NFC tag or QR code. Server-rendered HTML:
 * no script, every user string escaped, links limited to https. Mobile-first, Arabic RTL by
 * default (English when the visitor's browser prefers it), brand colours from the design tokens
 * and the logo from artwork only (CLAUDE.md rule 8).
 *
 * The page is also Yaqeen's front door for whoever scans it: below the owner's card sits a CTA to
 * get the app and to shop the store, tagged with the owner's handle for attribution.
 */
import { socialUrl, type PublicProfileView, type SocialKind } from '@yaqeen/contracts';
import { BRAND_PNG } from './brand-assets.js';

export type PageLang = 'ar' | 'en';

export interface PageLinks {
  /** Smart "get the app" link (redirects to the right store). */
  getApp: string;
  /** The store, already tagged for attribution. */
  store: string;
  /** Canonical URL of this page. */
  self: string;
  /** Absolute URL of the share image. */
  image: string;
}

const COPY = {
  ar: {
    level: (n: number) => `المستوى ${n}`,
    streak: 'يوماً متتالياً',
    challenge: 'رحلة 365 يوماً',
    dayOf: (d: number, of: number) => `اليوم ${d} من ${of}`,
    badges: 'أوسمة المواظبة',
    badge: (d: number) => `${d} يوماً`,
    since: (m: string) => `في يقين منذ ${m}`,
    links: 'تواصل',
    ctaEyebrow: 'من يقين',
    ctaTitle: 'طمأنينة يومية تبدأ من هنا',
    ctaBody: 'مصحف كامل دون اتصال، مواقيت دقيقة وتنبيه للأذان، أذكار وأدعية، ورحلة يومية تُكافأ عليها بنقاط تستبدلها في متجر يقين.',
    getApp: 'حمّل تطبيق يقين',
    shop: 'تسوّق من متجر يقين',
    footer: 'بطاقة يقين',
    footerMake: 'اصنع بطاقتك من التطبيق',
    notFoundTitle: 'هذه البطاقة غير متاحة',
    notFoundBody: 'ربما أخفاها صاحبها أو تغيّر اسمها. يمكنك أن تبدأ رحلتك مع يقين الآن.',
    title: (name: string) => `${name} · يقين`,
  },
  en: {
    level: (n: number) => `Level ${n}`,
    streak: 'day streak',
    challenge: '365-day journey',
    dayOf: (d: number, of: number) => `Day ${d} of ${of}`,
    badges: 'Streak badges',
    badge: (d: number) => `${d} days`,
    since: (m: string) => `On Yaqeen since ${m}`,
    links: 'Connect',
    ctaEyebrow: 'From Yaqeen',
    ctaTitle: 'Daily calm starts here',
    ctaBody: 'The full mushaf offline, accurate prayer times with adhan, azkar and duas, and a daily journey that earns points for the Yaqeen store.',
    getApp: 'Get the Yaqeen app',
    shop: 'Shop the Yaqeen store',
    footer: 'Yaqeen card',
    footerMake: 'Make yours in the app',
    notFoundTitle: 'This card isn’t available',
    notFoundBody: 'Its owner may have hidden it or changed its name. You can start your own journey with Yaqeen now.',
    title: (name: string) => `${name} · Yaqeen`,
  },
} as const;

const SOCIAL: Record<SocialKind, { ar: string; en: string; mono: string }> = {
  instagram: { ar: 'إنستغرام', en: 'Instagram', mono: 'IG' },
  x: { ar: 'إكس', en: 'X', mono: 'X' },
  tiktok: { ar: 'تيك توك', en: 'TikTok', mono: 'TT' },
  facebook: { ar: 'فيسبوك', en: 'Facebook', mono: 'f' },
  youtube: { ar: 'يوتيوب', en: 'YouTube', mono: '▶' },
  snapchat: { ar: 'سناب شات', en: 'Snapchat', mono: 'SC' },
  linkedin: { ar: 'لينكدإن', en: 'LinkedIn', mono: 'in' },
  whatsapp: { ar: 'واتساب', en: 'WhatsApp', mono: 'WA' },
  website: { ar: 'الموقع', en: 'Website', mono: '↗' },
};

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"'`]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' })[c]!);
}

/** Visitor language: `?lang=` wins, then Accept-Language; Arabic by default. */
export function pickLang(query: string | undefined, acceptLanguage: string | undefined): PageLang {
  if (query === 'en' || query === 'ar') return query;
  const first = (acceptLanguage ?? '').split(',')[0]?.trim().toLowerCase() ?? '';
  return first.startsWith('en') ? 'en' : 'ar';
}

/** Western digits everywhere (CLAUDE.md rule 7). */
const n = (v: number) => new Intl.NumberFormat('en-US').format(v);

function monthYear(iso: string, lang: PageLang): string {
  const d = new Date(`${iso}T00:00:00Z`);
  return new Intl.DateTimeFormat(lang === 'ar' ? 'ar-EG-u-nu-latn' : 'en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(d);
}

function ring(progress: number): string {
  // A 132-px medallion ring: gold arc for the level's progress, starting at the top.
  const r = 62;
  const c = 2 * Math.PI * r;
  const p = Math.max(0, Math.min(1, progress));
  return `<svg class="ring" viewBox="0 0 136 136" aria-hidden="true"><circle cx="68" cy="68" r="${r}" class="track"/><circle cx="68" cy="68" r="${r}" class="arc" stroke-dasharray="${(c * p).toFixed(1)} ${c.toFixed(1)}"/></svg>`;
}

function shell(lang: PageLang, opts: { title: string; description: string; theme: string; body: string; links: PageLinks }): string {
  const dir = lang === 'ar' ? 'rtl' : 'ltr';
  const night = opts.theme === 'night';
  const logo = night ? (lang === 'ar' ? BRAND_PNG.lockupWhiteAr : BRAND_PNG.lockupWhiteEn) : lang === 'ar' ? BRAND_PNG.lockupNavyAr : BRAND_PNG.lockupNavyEn;
  return `<!doctype html>
<html lang="${lang}" dir="${dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="${night ? '#0A1530' : '#F3F6FB'}">
<title>${escapeHtml(opts.title)}</title>
<meta name="description" content="${escapeHtml(opts.description)}">
<meta property="og:type" content="profile">
<meta property="og:title" content="${escapeHtml(opts.title)}">
<meta property="og:description" content="${escapeHtml(opts.description)}">
<meta property="og:url" content="${escapeHtml(opts.links.self)}">
<meta property="og:image" content="${escapeHtml(opts.links.image)}">
<meta name="twitter:card" content="summary">
<link rel="icon" href="${escapeHtml(opts.links.image)}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Amiri:wght@700&family=Jost:wght@300;400;500&family=Tajawal:wght@400;500;700&display=swap">
<style>${CSS}</style>
</head>
<body class="theme-${escapeHtml(opts.theme)}">
<div class="sky" aria-hidden="true"><i class="glow"></i><i class="glow two"></i></div>
<main>
<header class="brand"><img src="data:image/png;base64,${logo}" alt="${lang === 'ar' ? 'يقين' : 'Yaqeen'}" width="150"></header>
${opts.body}
</main>
</body>
</html>`;
}

function cta(lang: PageLang, links: PageLinks): string {
  const t = COPY[lang];
  return `<section class="cta rise" style="--d:6">
<p class="eyebrow">${t.ctaEyebrow}</p>
<h2>${t.ctaTitle}</h2>
<p class="cta-body">${t.ctaBody}</p>
<a class="btn primary" href="${escapeHtml(links.getApp)}">${t.getApp}</a>
<a class="btn ghost" href="${escapeHtml(links.store)}">${t.shop}</a>
</section>`;
}

export function renderProfilePage(view: PublicProfileView, lang: PageLang, links: PageLinks): string {
  const t = COPY[lang];
  const name = escapeHtml(view.displayName);
  const initial = escapeHtml(Array.from(view.displayName.trim())[0] ?? '·');
  const level = view.level;

  const stats: string[] = [];
  if (view.streak !== null) {
    stats.push(`<div class="stat"><span class="num">${n(view.streak)}</span><span class="lbl">${t.streak}</span></div>`);
  }
  if (view.challengeDay) {
    const p = view.challengeDay.of ? view.challengeDay.day / view.challengeDay.of : 0;
    stats.push(
      `<div class="stat"><span class="num">${n(view.challengeDay.day)}</span><span class="lbl">${t.dayOf(view.challengeDay.day, view.challengeDay.of)}</span><span class="bar"><i style="width:${(p * 100).toFixed(1)}%"></i></span></div>`,
    );
  }
  if (view.badges && view.badges.length) {
    stats.push(`<div class="stat"><span class="num">${n(view.badges.length)}</span><span class="lbl">${t.badges}</span></div>`);
  }

  const badges =
    view.badges && view.badges.length
      ? `<section class="badges rise" style="--d:4" aria-label="${t.badges}">${view.badges
          .map((d) => `<span class="badge"><i class="diamond"></i>${t.badge(d).replace(String(d), n(d))}</span>`)
          .join('')}</section>`
      : '';

  const linkItems = view.links
    .map((l) => ({ l, url: socialUrl(l) }))
    .filter((x): x is { l: (typeof view.links)[number]; url: string } => x.url !== null)
    .map(({ l, url }) => {
      const meta = SOCIAL[l.kind];
      const shown = escapeHtml(l.value.replace(/^https?:\/\//, '').replace(/\/$/, ''));
      return `<a class="link" href="${escapeHtml(url)}" rel="me noopener nofollow" target="_blank"><span class="mono k-${l.kind}">${meta.mono}</span><span class="txt"><b>${lang === 'ar' ? meta.ar : meta.en}</b><small dir="ltr">${shown}</small></span><span class="go" aria-hidden="true">›</span></a>`;
    })
    .join('');

  const body = `<section class="card rise" style="--d:1">
<div class="medallion">${level ? ring(level.progress) : ''}<span class="initial">${initial}</span></div>
<h1>${name}</h1>
<p class="handle" dir="ltr">@${escapeHtml(view.handle)}</p>
${level ? `<p class="level"><i class="diamond"></i>${escapeHtml(lang === 'ar' ? level.nameAr : level.nameEn)} · ${t.level(level.level).replace(String(level.level), n(level.level))}</p>` : ''}
${view.bio ? `<p class="bio">${escapeHtml(view.bio)}</p>` : ''}
${view.memberSince ? `<p class="since">${escapeHtml(t.since(monthYear(view.memberSince, lang)))}</p>` : ''}
</section>
${stats.length ? `<section class="stats rise" style="--d:2">${stats.join('')}</section>` : ''}
${badges}
${linkItems ? `<nav class="links rise" style="--d:5" aria-label="${t.links}">${linkItems}</nav>` : ''}
${cta(lang, links)}
<footer class="rise" style="--d:7"><span>${t.footer}</span><a href="${escapeHtml(links.getApp)}">${t.footerMake}</a></footer>`;

  return shell(lang, {
    title: t.title(view.displayName),
    description: view.bio || t.ctaTitle,
    theme: view.theme,
    body,
    links,
  });
}

export function renderNotFoundPage(lang: PageLang, links: PageLinks): string {
  const t = COPY[lang];
  const body = `<section class="card rise" style="--d:1">
<div class="medallion empty"><span class="initial">؟</span></div>
<h1>${t.notFoundTitle}</h1>
<p class="bio">${t.notFoundBody}</p>
</section>
${cta(lang, links)}`;
  return shell(lang, { title: t.notFoundTitle, description: t.ctaTitle, theme: 'sky', body, links });
}

/* The stylesheet: porcelain + living sky (theme sky), warm cream (gold), brand night (night). */
const CSS = `
:root{--ink:#0A1530;--muted:#56637F;--lapis:#1F3F94;--navy:#10214D;--gold:#C6A867;--goldText:#7C6127;--goldLight:#E9D49E;
--porcelain:#F3F6FB;--glass:rgba(255,255,255,.62);--rim:rgba(255,255,255,.92);--top:#E3EBF7;--bottom:#F3F6FB;--glow:#ABC4E8;--track:rgba(31,63,148,.12)}
.theme-gold{--top:#FFFBF1;--bottom:#F4E8C8;--glow:#E9D49E;--track:rgba(124,97,39,.14)}
.theme-night{--ink:#F3F6FB;--muted:#C3C8D3;--glass:rgba(255,255,255,.08);--rim:rgba(255,255,255,.16);--top:#0A1530;--bottom:#1F3F94;--glow:#576FAF;--track:rgba(255,255,255,.14);--porcelain:#0A1530}
*{box-sizing:border-box;margin:0}
html{-webkit-text-size-adjust:100%}
body{min-height:100vh;font-family:Tajawal,system-ui,sans-serif;color:var(--ink);background:linear-gradient(180deg,var(--top),var(--bottom) 60%,var(--porcelain));-webkit-font-smoothing:antialiased;overflow-x:hidden}
.sky{position:fixed;inset:0;pointer-events:none;overflow:hidden}
.glow{position:absolute;width:120vw;height:120vw;max-width:780px;max-height:780px;inset-inline-end:-40vw;top:-50vw;border-radius:50%;background:radial-gradient(closest-side,var(--glow),transparent);opacity:.55;animation:drift 18s ease-in-out infinite alternate}
.glow.two{inset-inline-end:auto;inset-inline-start:-50vw;top:auto;bottom:-60vw;opacity:.3;animation-duration:24s}
@keyframes drift{to{transform:translate3d(-6vw,4vw,0) scale(1.08)}}
main{position:relative;max-width:460px;margin:0 auto;padding:calc(env(safe-area-inset-top) + 20px) 20px calc(env(safe-area-inset-bottom) + 28px)}
.brand{display:flex;justify-content:center;padding:6px 0 22px}
.brand img{height:auto;max-width:150px}
.card{position:relative;text-align:center;padding:30px 22px 26px;border-radius:30px;background:var(--glass);border:1px solid var(--rim);box-shadow:0 30px 60px -36px rgba(15,26,54,.45);backdrop-filter:blur(18px) saturate(1.6);-webkit-backdrop-filter:blur(18px) saturate(1.6)}
.card::before{content:"";position:absolute;inset:1px 18% auto;height:24px;border-radius:999px;background:linear-gradient(rgba(255,255,255,.8),transparent);opacity:.7}
.theme-night .card::before{opacity:.15}
.medallion{position:relative;width:136px;height:136px;margin:0 auto 16px;display:grid;place-items:center}
.ring{position:absolute;inset:0;transform:rotate(-90deg)}
[dir=rtl] .ring{transform:rotate(-90deg) scaleY(-1)}
.ring circle{fill:none;stroke-width:5}
.ring .track{stroke:var(--track)}
.ring .arc{stroke:var(--gold);stroke-linecap:round;animation:arc 1.6s cubic-bezier(.2,.7,.2,1) both .3s}
@keyframes arc{from{stroke-dasharray:0 400}}
.initial{width:104px;height:104px;border-radius:50%;display:grid;place-items:center;font-family:Amiri,serif;font-weight:700;font-size:48px;color:#fff;background:linear-gradient(180deg,#576FAF,#1F3F94);border:3px solid rgba(255,255,255,.95);box-shadow:0 18px 34px -16px rgba(31,63,148,.7)}
.theme-gold .initial{background:linear-gradient(180deg,#D4BE8D,#7C6127)}
.medallion.empty .initial{background:linear-gradient(180deg,#C8D5EC,#8F9FCA)}
h1{font-family:Amiri,Tajawal,serif;font-size:32px;line-height:1.25;font-weight:700;letter-spacing:.2px}
.handle{margin-top:4px;color:var(--muted);font-family:Jost,sans-serif;font-size:14px;letter-spacing:.3px}
.level{display:inline-flex;align-items:center;gap:8px;margin-top:14px;padding:7px 14px;border-radius:999px;font-size:13px;font-weight:700;color:var(--goldText);background:rgba(233,212,158,.35);border:1px solid rgba(198,168,103,.45)}
.theme-night .level{color:var(--goldLight);background:rgba(233,212,158,.1)}
.diamond{width:9px;height:9px;transform:rotate(45deg);border-radius:2px;background:linear-gradient(135deg,var(--goldLight),var(--gold));display:inline-block;flex:none}
.bio{margin-top:14px;font-size:15px;line-height:1.75;color:var(--muted);white-space:pre-line;overflow-wrap:anywhere}
.since{margin-top:10px;font-size:12px;color:var(--muted);opacity:.85}
.stats{display:flex;gap:12px;margin-top:16px}
.stat{flex:1;min-width:0;padding:16px 10px 14px;border-radius:24px;text-align:center;background:var(--glass);border:1px solid var(--rim);box-shadow:0 22px 40px -30px rgba(15,26,54,.4)}
.num{display:block;font-family:Jost,sans-serif;font-weight:300;font-size:34px;line-height:1.05;letter-spacing:.5px}
.lbl{display:block;margin-top:4px;font-size:12px;color:var(--muted)}
.bar{display:block;height:4px;margin:10px 8px 0;border-radius:4px;background:var(--track);overflow:hidden}
.bar i{display:block;height:100%;border-radius:4px;background:linear-gradient(90deg,var(--goldLight),var(--gold))}
.badges{display:flex;flex-wrap:wrap;justify-content:center;gap:8px;margin-top:16px}
.badge{display:inline-flex;align-items:center;gap:8px;padding:8px 14px;border-radius:999px;font-size:13px;font-weight:500;background:linear-gradient(180deg,#FFFBF1,#F4E8C8);border:1px solid rgba(198,168,103,.5);color:#4A3C17}
.links{display:grid;gap:10px;margin-top:22px}
.link{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:20px;text-decoration:none;color:var(--ink);background:var(--glass);border:1px solid var(--rim);transition:transform .2s cubic-bezier(.2,.7,.2,1),box-shadow .2s}
.link:active{transform:scale(.98)}
@media (hover:hover){.link:hover{transform:translateY(-2px);box-shadow:0 18px 30px -22px rgba(15,26,54,.45)}}
.mono{width:40px;height:40px;flex:none;border-radius:14px;display:grid;place-items:center;font-family:Jost,sans-serif;font-weight:500;font-size:14px;color:#fff;background:linear-gradient(160deg,#576FAF,#10214D)}
.k-whatsapp{background:linear-gradient(160deg,#4FA27B,#2E7A55)}.k-website{background:linear-gradient(160deg,#D4BE8D,#7C6127)}
.txt{flex:1;min-width:0;text-align:start}
.txt b{display:block;font-size:15px;font-weight:700}
.txt small{display:block;font-size:12px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-align:start}
[dir=rtl] .txt small{text-align:end}
.go{font-size:22px;color:var(--muted)}
[dir=rtl] .go{transform:scaleX(-1)}
.cta{position:relative;overflow:hidden;margin-top:28px;padding:26px 22px 22px;border-radius:30px;color:#F3F6FB;background:linear-gradient(90deg,#0A1530,#10214D 45%,#1F3F94);box-shadow:0 30px 60px -34px rgba(10,21,48,.75)}
.cta::after{content:"";position:absolute;width:260px;height:260px;inset-inline-end:-90px;top:-120px;border-radius:50%;background:radial-gradient(closest-side,rgba(233,212,158,.35),transparent)}
.eyebrow{font-size:12px;font-weight:700;letter-spacing:.6px;color:var(--goldLight)}
.cta h2{margin-top:6px;font-family:Amiri,Tajawal,serif;font-size:26px;line-height:1.35}
.cta-body{margin-top:8px;font-size:14px;line-height:1.75;color:#C3C8D3}
.btn{position:relative;z-index:1;display:flex;align-items:center;justify-content:center;height:54px;margin-top:12px;border-radius:999px;font-weight:700;font-size:15px;text-decoration:none;transition:transform .2s}
.btn:active{transform:scale(.98)}
.btn.primary{margin-top:18px;color:#0A1530;background:linear-gradient(180deg,#F1E2B6,#C6A867);box-shadow:0 14px 28px -14px rgba(198,168,103,.9)}
.btn.ghost{color:#F3F6FB;border:1px solid rgba(255,255,255,.28);background:rgba(255,255,255,.06)}
footer{display:flex;justify-content:space-between;gap:12px;margin-top:20px;padding:0 6px;font-size:12px;color:var(--muted)}
footer a{color:var(--lapis);font-weight:700;text-decoration:none}
.theme-night footer a{color:var(--goldLight)}
.rise{animation:rise .8s cubic-bezier(.2,.7,.2,1) both;animation-delay:calc(var(--d,0) * 70ms)}
@keyframes rise{from{opacity:0;transform:translateY(14px)}}
@media (prefers-reduced-motion:reduce){.rise,.ring .arc,.glow{animation:none}}
`;
