/**
 * Yaqeen's public website, served by the API on the cards host (spec §5.29): the landing page, the
 * privacy policy and terms the app and the stores link to, support/FAQ, and the account-deletion
 * page Google Play asks for. Server-rendered HTML, no scripts or trackers, Arabic RTL first with
 * English, Western digits, brand colours from the design tokens and the logo from artwork only.
 *
 * Legal text: written from what the code actually does (docs/SECURITY_PRIVACY.md). Facts only the
 * owner can give — legal entity, address, DPO, hosting region — stay visibly bracketed until set
 * (CLAUDE.md rule 9 spirit: never invent), and counsel reviews both documents before launch.
 */
import { BRAND_PNG } from './brand-assets.js';
import { escapeHtml, type PageLang } from './profile-page.js';

export type SitePage = 'home' | 'privacy' | 'terms' | 'support' | 'delete-account';

export interface SiteLinks {
  /** Absolute base of the site (PUBLIC_PROFILE_BASE_URL). */
  base: string;
  /** Smart "get the app" link. */
  getApp: string;
  /** The Yaqeen store (medals, rewards). */
  store: string;
  /** Support address; '' until the owner sets SUPPORT_EMAIL. */
  supportEmail: string;
}

/** Bumped whenever the privacy policy or terms change (shown on the pages). */
export const LEGAL_VERSION = '2026-10-31';

const NAV: Record<PageLang, Record<SitePage, string>> = {
  ar: { home: 'الرئيسية', privacy: 'الخصوصية', terms: 'الشروط', support: 'المساعدة', 'delete-account': 'حذف الحساب' },
  en: { home: 'Home', privacy: 'Privacy', terms: 'Terms', support: 'Help', 'delete-account': 'Delete account' },
};

const path = (p: SitePage) => (p === 'home' ? '/' : `/${p}`);

function email(links: SiteLinks, lang: PageLang): string {
  return links.supportEmail
    ? `<a href="mailto:${escapeHtml(links.supportEmail)}">${escapeHtml(links.supportEmail)}</a>`
    : lang === 'ar'
      ? '[بريد الدعم]'
      : '[support email]';
}

function shell(lang: PageLang, page: SitePage, links: SiteLinks, opts: { title: string; description: string; body: string }): string {
  const dir = lang === 'ar' ? 'rtl' : 'ltr';
  const other: PageLang = lang === 'ar' ? 'en' : 'ar';
  const logo = lang === 'ar' ? BRAND_PNG.lockupNavyAr : BRAND_PNG.lockupNavyEn;
  const url = `${links.base}${path(page)}`;
  const nav = (['home', 'privacy', 'terms', 'support'] as SitePage[])
    .map((p) => `<a href="${path(p)}?lang=${lang}"${p === page ? ' aria-current="page"' : ''}>${NAV[lang][p]}</a>`)
    .join('');
  return `<!doctype html>
<html lang="${lang}" dir="${dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#F3F6FB">
<title>${escapeHtml(opts.title)}</title>
<meta name="description" content="${escapeHtml(opts.description)}">
<link rel="canonical" href="${escapeHtml(url)}?lang=${lang}">
<link rel="alternate" hreflang="ar" href="${escapeHtml(url)}?lang=ar">
<link rel="alternate" hreflang="en" href="${escapeHtml(url)}?lang=en">
<meta property="og:type" content="website">
<meta property="og:title" content="${escapeHtml(opts.title)}">
<meta property="og:description" content="${escapeHtml(opts.description)}">
<meta property="og:url" content="${escapeHtml(url)}">
<meta property="og:image" content="${escapeHtml(links.base)}/u/assets/icon.png">
<link rel="icon" href="${escapeHtml(links.base)}/u/assets/icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Amiri:wght@700&family=Jost:wght@300;400;500&family=Tajawal:wght@400;500;700&display=swap">
<style>${CSS}</style>
</head>
<body>
<div class="sky" aria-hidden="true"><i class="glow"></i><i class="glow two"></i></div>
<header class="top">
<a class="logo" href="/?lang=${lang}"><img src="data:image/png;base64,${logo}" alt="${lang === 'ar' ? 'يقين' : 'Yaqeen'}" width="128"></a>
<nav aria-label="${lang === 'ar' ? 'الأقسام' : 'Sections'}">${nav}<a class="lang" href="${path(page)}?lang=${other}" hreflang="${other}" lang="${other}">${other === 'ar' ? 'العربية' : 'English'}</a></nav>
</header>
<main>
${opts.body}
</main>
<footer class="foot">
<p>${lang === 'ar' ? '© يقين' : '© Yaqeen'} · <a href="/privacy?lang=${lang}">${NAV[lang].privacy}</a> · <a href="/terms?lang=${lang}">${NAV[lang].terms}</a> · <a href="/delete-account?lang=${lang}">${NAV[lang]['delete-account']}</a></p>
</footer>
</body>
</html>`;
}

/* ------------------------------------------------------------------ home */

const HOME = {
  ar: {
    title: 'يقين · طمأنينة يومية',
    description: 'مصحف كامل دون اتصال، مواقيت دقيقة وتنبيه للأذان، أذكار وأدعية، رمضان، ورحلة يومية تُكافأ عليها — وخصوصيتك محفوظة.',
    eyebrow: 'تطبيق يقين',
    h1: 'طمأنينة يومية،\nتبدأ من هنا',
    lead: 'رفيقك في يومك: صلاتك في وقتها، وِردك من المصحف، أذكارك، ورحلة 365 يوماً تُكافأ عليها بنقاط تستبدلها في متجر يقين.',
    getApp: 'حمّل التطبيق',
    shop: 'متجر يقين',
    features: [
      ['المصحف دون اتصال', 'المصحف كاملاً على جهازك، مع وِرد يومي وخطة حفظ ومراجعة، واستماع لقرّاء مرخّصين.'],
      ['مواقيت الصلاة والقبلة', 'تُحسب على هاتفك لمدينتك، مع تنبيه الأذان والقبلة — تعمل دون إنترنت.'],
      ['الأذكار والأدعية', 'أذكار الصباح والمساء والأدعية بمصادرها، يراجعها مختصّ قبل النشر.'],
      ['رحلة 365 يوماً', 'مهام يومية بسيطة تجمع بها نقاطاً تستبدلها بهدايا وخصومات في متجر يقين.'],
      ['رمضان', 'إمساكية لمدينتك، عدّ تنازلي للإفطار والسحور، وختمة وتراويح تتابعها على جهازك.'],
      ['ودجت الشاشة الرئيسية', 'الصلاة القادمة مع عدّ تنازلي، والتاريخ الهجري، ووِرد اليوم — على شاشتك الرئيسية.'],
    ],
    cardTitle: 'بطاقة يقين وميداليات يقين',
    cardBody: 'بطاقتك العامة تُظهر رحلتك (المستوى والمواظبة والأوسمة) دون أي تفاصيل عبادة. ميداليات وبطاقات يقين من المتجر تفتحها بلمسة أو مسح رمز.',
    privacyTitle: 'عبادتك بينك وبين ربك',
    privacyBody: 'مواقيتك وموقعك وقراءتك وحفظك تبقى على جهازك، إلا ما تختار نسخه احتياطياً بتشفير. لا نرسل أي نشاط عبادة إلى منصّات الإعلان أبداً، ولا يرى فريقنا إلا أرقاماً مجمّعة. كل موافقة منفصلة ويمكنك إلغاؤها في أي وقت.',
    readPolicy: 'اقرأ سياسة الخصوصية',
  },
  en: {
    title: 'Yaqeen · Daily calm',
    description: 'The full mushaf offline, accurate prayer times with adhan, azkar and duas, Ramadan, and a daily journey that earns rewards — with your privacy kept.',
    eyebrow: 'The Yaqeen app',
    h1: 'Daily calm\nstarts here',
    lead: 'A companion for your day: prayer on time, your Quran wird, your azkar, and a 365-day journey that earns points for the Yaqeen store.',
    getApp: 'Get the app',
    shop: 'Yaqeen store',
    features: [
      ['The mushaf, offline', 'The whole mushaf on your phone, with a daily wird, a memorisation plan with reviews, and licensed reciters.'],
      ['Prayer times & Qibla', 'Computed on your phone for your city, with adhan alerts and Qibla — no internet needed.'],
      ['Azkar & duas', 'Morning and evening azkar and duas with their sources, reviewed by a specialist before they go live.'],
      ['A 365-day journey', 'Small daily tasks that earn points you can redeem for gifts and discounts in the Yaqeen store.'],
      ['Ramadan', 'An imsakiyya for your city, countdowns to iftar and suhoor, and a khatma and taraweeh log kept on your phone.'],
      ['Home-screen widget', 'The next prayer with a live countdown, the Hijri date and today’s wird — right on your home screen.'],
    ],
    cardTitle: 'Yaqeen cards & medals',
    cardBody: 'Your public card shows your journey (level, streak, badges) and never any worship detail. Yaqeen medals and cards from the store open it with a tap or a scan.',
    privacyTitle: 'Your worship stays yours',
    privacyBody: 'Your times, location, reading and memorisation stay on your phone, unless you choose an encrypted backup. We never send worship activity to ad platforms, and our team only ever sees totals. Every consent is separate and can be withdrawn at any time.',
    readPolicy: 'Read the privacy policy',
  },
} as const;

export function renderHome(lang: PageLang, links: SiteLinks): string {
  const t = HOME[lang];
  const features = t.features
    .map(([h, p], i) => `<li class="feature rise" style="--d:${i + 2}"><h3>${h}</h3><p>${p}</p></li>`)
    .join('');
  const body = `
<section class="hero rise" style="--d:0">
<p class="eyebrow">${t.eyebrow}</p>
<h1>${t.h1.replace('\n', '<br>')}</h1>
<p class="lead">${t.lead}</p>
<div class="actions"><a class="btn primary" href="${escapeHtml(links.getApp)}">${t.getApp}</a><a class="btn" href="${escapeHtml(links.store)}">${t.shop}</a></div>
</section>
<ul class="features">${features}</ul>
<section class="panel gold rise" style="--d:8"><h2>${t.cardTitle}</h2><p>${t.cardBody}</p><a class="btn" href="${escapeHtml(links.store)}">${t.shop}</a></section>
<section class="panel rise" style="--d:9"><h2>${t.privacyTitle}</h2><p>${t.privacyBody}</p><a class="link" href="/privacy?lang=${lang}">${t.readPolicy}</a></section>`;
  return shell(lang, 'home', links, { title: t.title, description: t.description, body });
}

/* -------------------------------------------------------- legal documents */

type Section = [heading: string, paragraphs: string[]];

function doc(lang: PageLang, page: SitePage, links: SiteLinks, title: string, intro: string, sections: Section[]): string {
  const toc = sections.map(([h], i) => `<li><a href="#s${i + 1}">${h}</a></li>`).join('');
  const body = `
<article class="doc">
<h1>${title}</h1>
<p class="meta">${lang === 'ar' ? 'آخر تحديث' : 'Last updated'}: <span class="num">${LEGAL_VERSION}</span></p>
<p>${intro}</p>
<nav class="toc" aria-label="${lang === 'ar' ? 'المحتويات' : 'Contents'}"><ol>${toc}</ol></nav>
${sections
  .map(
    ([h, ps], i) => `<section id="s${i + 1}"><h2><span class="num">${i + 1}.</span> ${h}</h2>${ps.map((p) => `<p>${p}</p>`).join('')}</section>`,
  )
  .join('\n')}
</article>`;
  return shell(lang, page, links, { title: `${title} · ${lang === 'ar' ? 'يقين' : 'Yaqeen'}`, description: intro, body });
}

export function renderPrivacy(lang: PageLang, links: SiteLinks): string {
  const mail = email(links, lang);
  if (lang === 'ar') {
    return doc(lang, 'privacy', links, 'سياسة الخصوصية', 'تشرح هذه السياسة ما يجمعه تطبيق يقين وموقعه، ولماذا، وما يبقى على جهازك وحده، وحقوقك وفق قانون حماية البيانات الشخصية المصري رقم 151 لسنة 2020.', [
      ['من نحن', [`يقين يقدّمه [الاسم القانوني للشركة]، [العنوان]، مصر ("نحن"). للتواصل بشأن الخصوصية: ${mail}. مسؤول حماية البيانات: [اسم مسؤول حماية البيانات وبريده].`]],
      ['ما يبقى على جهازك', ['موقعك وإحداثياتك (تُحسب مواقيت الصلاة والقبلة على الهاتف) وبيانات ودجت الشاشة الرئيسية لا تصل إلينا أبداً. وسجل القراءة والعلامات والملاحظات والختمة، وخطة الحفظ ومراجعاتها، وعدّاد الأذكار والمسبحة، وروتينك اليومي، وسجل رمضان (الصيام والتراويح والختمة) تبقى على جهازك ولا تصل إلينا — إلا إذا فعّلت «النسخ الاحتياطي السحابي» بنفسك (انظر أدناه).']],
      ['ما نحتفظ به عندنا', [
        'الحساب: عند الدخول بـ Google أو Apple نحفظ الاسم والبريد اللذين يرسلهما المزوّد ومعرّف الحساب لديه. يمكنك استخدام التطبيق ضيفاً دون حساب.',
        'إعداداتك التي تُزامَن: اللغة، واسم المدينة التي اخترتها، والمنطقة الزمنية، وطريقة الحساب، وتعديل التاريخ الهجري.',
        'رحلة 365 يوماً: المهام التي تسجّل إتمامها ونقاطك والمكافآت التي استبدلتها — لاحتساب النقاط فقط. هذه بيانات تكشف ممارسة دينية؛ لذلك لا تُشارك مع أي منصة إعلان، ولا يرى فريقنا إلا أرقاماً مجمّعة، ولا تظهر في بطاقتك العامة.',
        'بطاقة يقين العامة (اختيارية): الاسم والصورة الرمزية والحقول التي تختار إظهارها، وعدّاد الزيارات فقط. الميداليات والبطاقات المادية تحمل رمزاً عشوائياً لا هويتك.',
        'الجهاز: رمز الإشعارات (FCM) ونظام التشغيل وإصدار التطبيق، لإرسال الإشعارات التي وافقت عليها.',
        'سجل الموافقات: كل تغيير في موافقاتك مع وقته ومصدره، كدليل قانوني على ما وافقت عليه.',
        'النسخ الاحتياطي السحابي (اختياري، للحسابات المسجّلة بـ Google أو Apple فقط، مغلق حتى تفتحه في «حسابي ← الخصوصية»): نسخة من تقدّمك المحفوظ على الجهاز — القراءة والعلامات والملاحظات والختمة والحفظ وعدّاد الأذكار والأدعية المفضّلة والقارئ المختار وروتينك وسجل رمضان والمسبحة — لتعود معك على هاتف جديد. لا تشمل موقعك ولا التحميلات. تُشفَّر قبل حفظها على خوادمنا، ولا يراها غيرك ولا فريقنا، ولا تُستخدم في التحليلات أو الإعلانات، وتُضمَّن في تصدير بياناتك، وتُحذف من خوادمنا فور إيقافها أو حذف حسابك.',
      ]],
      ['الموافقات المنفصلة', ['ست موافقات مستقلة يمكنك تغييرها في «حسابي ← الخصوصية» في أي وقت: تذكيرات العبادة (إشعارات محلية على جهازك)، رسائل التحدي والمكافآت، عروض المتجر، قياس الإعلانات، وتحسين التطبيق، والنسخ الاحتياطي السحابي (للحسابات المسجّلة). كلها مغلقة حتى تفتحها، عدا ما تختاره أثناء الإعداد.']],
      ['الإعلانات', ['مع موافقة «قياس الإعلانات» فقط، نرسل إلى Google وMeta وTikTok أحداثاً تسويقية محدّدة مسبقاً (مثل فتح التطبيق لأول مرة أو الانضمام إلى التحدي أو الشراء من المتجر) — ولا نرسل أبداً أي نشاط عبادة. على iOS لا يظهر طلب التتبع إلا بعد موافقتك داخل التطبيق.']],
      ['تحسين التطبيق', ['مع موافقة «تحسين التطبيق» فقط، نسجّل كيف تتنقّل بين أقسام غير تعبّدية (خطوات الإعداد، البطاقة، المتجر، الإعدادات) بمعرّف عشوائي للجهاز غير مرتبط بحسابك، ونحذفها بعد 180 يوماً. قد نرسلها إلى PostHog (الاتحاد الأوروبي) دون عنوان IP. لا نتتبع أقسام العبادة.']],
      ['تقارير الأعطال', ['نستخدم Sentry لتقارير الأعطال: نوع الخطأ والجهاز وإصدار التطبيق، بعد حذف أي بيانات شخصية أو تعبّدية، ودون لقطات شاشة.']],
      ['من يعالج البيانات لصالحنا', [
        'الاستضافة: [مزوّد الاستضافة ومنطقتها]. الإشعارات: Google Firebase Cloud Messaging. تسجيل الدخول: Google وApple. أكواد المكافآت والمتجر: Shopify. الأعطال: Sentry (الاتحاد الأوروبي). تحسين التطبيق: PostHog (الاتحاد الأوروبي، بموافقتك). الإعلانات: Google وMeta وTikTok (بموافقتك فقط).',
        'بعض هؤلاء خارج مصر؛ ننقل إليهم أقل قدر لازم وفق ضمانات القانون [وتصريح النقل عند الحاجة].',
      ]],
      ['مدة الاحتفاظ', ['نحتفظ ببيانات حسابك ما دام قائماً. عند طلب الحذف تُخفى بطاقتك وتُعطّل ميدالياتك فوراً، وبعد 30 يوماً تُحذف هويتك وجلساتك وأجهزتك وموافقاتك الحالية وسجل المهام والنسخة الاحتياطية السحابية، ويبقى سجل النقاط والاستبدالات مجهول الهوية لأغراض محاسبية، ويبقى سجل الموافقات كدليل قانوني. أحداث «تحسين التطبيق» تُحذف بعد 180 يوماً. والنسخة الاحتياطية السحابية تُحذف فور إيقافها.']],
      ['حقوقك', [`لك أن تطّلع على بياناتك وتصدّرها («حسابي ← تصدير بياناتي»)، وأن تصحّحها، وأن تحذف حسابك (<a href="/delete-account?lang=ar">كيف أحذف حسابي</a>)، وأن تسحب أي موافقة. للاستفسار أو الاعتراض: ${mail}. ويحق لك تقديم شكوى إلى مركز حماية البيانات الشخصية.`]],
      ['الأطفال', ['يقين موجّه لمن هم في سن [السن الأدنى] فأكثر. [يُراجَع مع المستشار القانوني.]']],
      ['التغييرات', ['إن غيّرنا هذه السياسة تغييراً جوهرياً سنُعلمك في التطبيق قبل سريانه، ونحدّث تاريخها أعلاه.']],
    ]);
  }
  return doc(lang, 'privacy', links, 'Privacy policy', 'This policy explains what the Yaqeen app and website collect, why, what stays on your phone alone, and your rights under Egypt’s Personal Data Protection Law No. 151 of 2020.', [
    ['Who we are', [`Yaqeen is provided by [legal entity name], [address], Egypt (“we”). Privacy questions: ${mail}. Data protection officer: [DPO name and email].`]],
    ['What stays on your phone', ['Your location and coordinates (prayer times and Qibla are computed on the phone) and the home-screen widget’s data never reach us. Your reading history, bookmarks, notes and khatma, memorisation plan and reviews, dhikr and tasbeeh counts, daily routine and Ramadan log (fasts, taraweeh, khatma) stay on your phone and don’t reach us — unless you turn on “cloud backup” yourself (below).']],
    ['What we keep', [
      'Account: when you sign in with Google or Apple we keep the name and email they send and their account id. You can use the app as a guest without an account.',
      'Synced settings: language, the city name you picked, time zone, calculation method and Hijri adjustment.',
      'The 365-day journey: the tasks you mark done, your points and the rewards you redeemed — only to award points. This reveals religious practice, so it is never shared with any ad platform, our team only ever sees totals, and it never appears on your public card.',
      'Your public Yaqeen card (optional): the name, avatar and the fields you choose to show, plus a visit counter only. Physical medals and cards carry a random code, not your identity.',
      'Device: push token (FCM), operating system and app version, to deliver the notifications you agreed to.',
      'Consent record: every change to your consents with its time and source, as legal evidence of what you agreed to.',
      'Cloud backup (optional, only for accounts signed in with Google or Apple, off until you turn it on in Profile → Privacy): a copy of the progress kept on your phone — reading, bookmarks, notes, khatma, memorisation, dhikr counts, favourite duas, chosen reciter, your routine, Ramadan log and tasbeeh — so it comes back on a new phone. Never your location or downloads. It is encrypted before it is stored on our servers, seen by no one but you (not our team), never used for analytics or advertising, included in your data export, and deleted from our servers as soon as you turn it off or delete your account.',
    ]],
    ['Separate consents', ['Six independent consents you can change at any time in Profile → Privacy: worship reminders (local notifications on your phone), challenge & rewards messages, store offers, ads measurement, app improvement, and cloud backup (signed-in accounts). Each is off until you turn it on, apart from what you choose during setup.']],
    ['Advertising', ['Only with “ads measurement”, we send Google, Meta and TikTok a fixed list of marketing events (such as first open, joining the challenge, or a store purchase) — never any worship activity. On iOS the tracking prompt only appears after you agreed inside the app.']],
    ['App improvement', ['Only with “app improvement”, we record how you move through non-worship areas (setup steps, the card, the store, settings) under a random install id that is not linked to your account, and delete it after 180 days. It may be forwarded to PostHog (EU) without IP addresses. Worship areas are never tracked.']],
    ['Crash reports', ['We use Sentry for crash reports: the error, device and app version, with personal and worship data removed and no screenshots.']],
    ['Who processes data for us', [
      'Hosting: [hosting provider and region]. Notifications: Google Firebase Cloud Messaging. Sign-in: Google and Apple. Reward codes and the store: Shopify. Crashes: Sentry (EU). App improvement: PostHog (EU, with your consent). Advertising: Google, Meta and TikTok (with your consent only).',
      'Some are outside Egypt; we send them the minimum needed under the law’s safeguards [and a transfer authorisation where required].',
    ]],
    ['How long we keep it', ['We keep your account data while it exists. When you ask to delete it, your card is hidden and your medals switched off at once; after 30 days your identity, sessions, devices, current consents, task history and cloud backup are deleted, while the points ledger and redemptions stay anonymised for accounting and the consent record stays as legal evidence. App-improvement events are deleted after 180 days. The cloud backup is deleted as soon as you turn it off.']],
    ['Your rights', [`You can see and export your data (Profile → Export my data), correct it, delete your account (<a href="/delete-account?lang=en">how to delete your account</a>) and withdraw any consent. Questions or objections: ${mail}. You may also complain to the Personal Data Protection Centre.`]],
    ['Children', ['Yaqeen is meant for people aged [minimum age] and over. [To be confirmed with counsel.]']],
    ['Changes', ['If we change this policy materially we will tell you in the app before it applies, and update the date above.']],
  ]);
}

export function renderTerms(lang: PageLang, links: SiteLinks): string {
  const mail = email(links, lang);
  if (lang === 'ar') {
    return doc(lang, 'terms', links, 'شروط الاستخدام', 'باستخدامك تطبيق يقين أو موقعه فإنك توافق على هذه الشروط. اقرأها مع سياسة الخصوصية.', [
      ['الخدمة', ['يقين تطبيق للمصحف ومواقيت الصلاة والأذكار والأدعية ورحلة يومية بنقاط ومكافآت، يقدّمه [الاسم القانوني للشركة]. قد نضيف ميزات أو نعدّلها أو نوقفها.']],
      ['الحساب', ['يمكنك الاستخدام ضيفاً أو بحساب Google أو Apple. أنت مسؤول عن حسابك وعن صحة ما تُدخله.']],
      ['المحتوى الديني', ['نصّ المصحف والتفسير والتلاوات من مصادر مرخّصة، والأذكار والأدعية تُنشر بعد مراجعة مختصّ. مواقيت الصلاة تُحسب فلكياً لمدينتك؛ قد تختلف دقائق عن مسجدك المحلي، فاضبطها من الإعدادات واعتمد مسجدك عند الشك.']],
      ['النقاط والمكافآت', [
        'النقاط تُمنح وفق قواعد البرنامج المعروضة في التطبيق، وليست لها قيمة نقدية ولا تُحوَّل ولا تُباع. قد نعدّل القواعد أو قيم المكافآت أو نوقف البرنامج مع إشعار في التطبيق.',
        'كل مكافأة تُصدر كود خصم لمرة واحدة في متجر يقين، صالحاً للمدة المذكورة عليه؛ الكود غير المستخدم ينتهي ولا تُعاد نقاطه. إن تعذّر إصدار الكود لا تُخصم نقاطك.',
        'نحتفظ بحق إلغاء نقاط تحقّقت بالتحايل أو بإساءة الاستخدام، مع إمكانية الاعتراض عبر الدعم.',
      ]],
      ['بطاقة يقين والميداليات', ['أنت مسؤول عن محتوى بطاقتك العامة. يحق لنا إخفاء بطاقة مسيئة أو اسم مستخدم مضلّل. الميدالية أو البطاقة المادية تُفعّل لحساب واحد؛ إن فقدتها عطّلها من التطبيق، ولا تُنقل لمن يجدها.']],
      ['الاستخدام المقبول', ['لا تسئ استخدام الخدمة: لا محاولات اختراق، ولا أتمتة لجمع النقاط، ولا محتوى مسيء أو مخالف للقانون في بطاقتك.']],
      ['الملكية', ['العلامة «يقين» وشعارها وتصميم التطبيق ملك لنا. نصوص المصحف والتلاوات مرخّصة من أصحابها.']],
      ['حدود المسؤولية', ['نقدّم الخدمة «كما هي». [حدود المسؤولية وفق ما يقرّه المستشار القانوني.]']],
      ['القانون الحاكم', ['تخضع هذه الشروط لقوانين جمهورية مصر العربية. [الاختصاص القضائي وفق المستشار القانوني.]']],
      ['التواصل', [`للأسئلة: ${mail}.`]],
    ]);
  }
  return doc(lang, 'terms', links, 'Terms of use', 'By using the Yaqeen app or website you agree to these terms. Read them together with the privacy policy.', [
    ['The service', ['Yaqeen is an app for the mushaf, prayer times, azkar and duas, and a daily journey with points and rewards, provided by [legal entity name]. We may add, change or stop features.']],
    ['Your account', ['You can use Yaqeen as a guest or with a Google or Apple account. You are responsible for your account and for what you enter.']],
    ['Religious content', ['The mushaf text, tafsir and recitations come from licensed sources; azkar and duas are published after a specialist’s review. Prayer times are computed astronomically for your city and may differ by a few minutes from your local mosque — adjust them in settings and follow your mosque when in doubt.']],
    ['Points and rewards', [
      'Points are awarded under the programme rules shown in the app. They have no cash value and can’t be transferred or sold. We may change the rules or reward values, or end the programme, with notice in the app.',
      'Each reward issues a single-use discount code for the Yaqeen store, valid for the period shown on it; an unused code expires and its points are not returned. If a code can’t be issued, no points are taken.',
      'We may remove points gained through abuse, and you can dispute this through support.',
    ]],
    ['Yaqeen cards and medals', ['You are responsible for what your public card shows. We may hide an abusive card or a misleading handle. A physical medal or card activates for one account; if you lose it, switch it off in the app — it is never passed to whoever finds it.']],
    ['Acceptable use', ['Don’t misuse the service: no attempts to break in, no automation to collect points, no abusive or unlawful content on your card.']],
    ['Ownership', ['The Yaqeen name, logo and app design are ours. The mushaf texts and recitations are licensed from their owners.']],
    ['Liability', ['The service is provided “as is”. [Limits of liability as approved by counsel.]']],
    ['Governing law', ['These terms are governed by the laws of the Arab Republic of Egypt. [Jurisdiction as approved by counsel.]']],
    ['Contact', [`Questions: ${mail}.`]],
  ]);
}

/* ----------------------------------------------------------- support / help */

const FAQ = {
  ar: [
    ['المواقيت تختلف عن مسجدي', 'من «الصلاة ← الإعدادات» اختر طريقة الحساب المناسبة لبلدك، وتأكّد من المدينة، ويمكنك تعديل كل صلاة بالدقائق.'],
    ['لا يصلني تنبيه الأذان', 'اسمح بالإشعارات للتطبيق، وعلى أندرويد اسمح بـ«المنبّهات والتذكيرات» واستثنِ يقين من توفير البطارية. تأكّد أن موافقة «تذكيرات العبادة» مفعّلة.'],
    ['هل يعمل دون إنترنت؟', 'نعم: المصحف والمواقيت والقبلة والأذكار والأدعية والحفظ وتسجيل المهام تعمل دون اتصال، وتُزامَن المهام عند عودة الاتصال.'],
    ['كيف أستبدل نقاطي؟', 'من «التحدي ← المكافآت» اختر مكافأة؛ يظهر كود خصم لمرة واحدة تستخدمه في متجر يقين قبل انتهاء صلاحيته.'],
    ['فقدت ميداليتي', 'من «حسابي ← بطاقة يقين ← ميدالياتي» عطّلها فوراً. لا يمكن لمن يجدها استخدامها.'],
    ['كيف أحذف حسابي؟', 'من «حسابي ← حذف الحساب»، والتفاصيل في صفحة حذف الحساب.'],
  ],
  en: [
    ['The times differ from my mosque', 'In Prayer → settings choose the calculation method for your country, check the city, and adjust any prayer by minutes.'],
    ['I don’t get the adhan alert', 'Allow notifications for the app; on Android also allow “Alarms & reminders” and exclude Yaqeen from battery optimisation. Make sure the “worship reminders” consent is on.'],
    ['Does it work offline?', 'Yes: the mushaf, times, Qibla, azkar, duas, memorisation and task ticks all work offline; ticks sync when you’re back online.'],
    ['How do I redeem points?', 'In Challenge → Rewards pick a reward; you get a single-use discount code for the Yaqeen store, to use before it expires.'],
    ['I lost my medal', 'In Profile → Yaqeen card → My medals, switch it off at once. Whoever finds it can’t use it.'],
    ['How do I delete my account?', 'Profile → Delete account; details on the account deletion page.'],
  ],
} as const;

export function renderSupport(lang: PageLang, links: SiteLinks): string {
  const ar = lang === 'ar';
  const faq = FAQ[lang].map(([q, a]) => `<details class="faq"><summary>${q}</summary><p>${a}</p></details>`).join('');
  const body = `
<article class="doc">
<h1>${ar ? 'المساعدة' : 'Help'}</h1>
<p>${ar ? 'إجابات سريعة لأكثر الأسئلة شيوعاً. لم تجد ما تبحث عنه؟ راسلنا.' : 'Quick answers to the most common questions. Can’t find yours? Write to us.'}</p>
${faq}
<section class="panel"><h2>${ar ? 'تواصل معنا' : 'Contact us'}</h2><p>${email(links, lang)}</p></section>
</article>`;
  return shell(lang, 'support', links, {
    title: ar ? 'المساعدة · يقين' : 'Help · Yaqeen',
    description: ar ? 'أسئلة شائعة عن تطبيق يقين وطرق التواصل.' : 'Frequently asked questions about Yaqeen and how to reach us.',
    body,
  });
}

export function renderDeleteAccount(lang: PageLang, links: SiteLinks): string {
  const ar = lang === 'ar';
  const steps = ar
    ? ['افتح تطبيق يقين وسجّل الدخول', 'اذهب إلى «حسابي» ثم «حذف الحساب»', 'أكّد مرتين']
    : ['Open the Yaqeen app and sign in', 'Go to Profile → Delete account', 'Confirm twice'];
  const body = `
<article class="doc">
<h1>${ar ? 'حذف حسابك في يقين' : 'Delete your Yaqeen account'}</h1>
<ol class="steps">${steps.map((s) => `<li>${s}</li>`).join('')}</ol>
<section class="panel"><h2>${ar ? 'ماذا يحدث بعدها' : 'What happens next'}</h2>
<p>${
    ar
      ? 'تُخفى بطاقتك العامة وتُعطّل ميدالياتك ويُسجَّل خروجك من كل الأجهزة فوراً. بعد 30 يوماً تُحذف هويتك وبياناتك نهائياً، عدا سجل النقاط مجهول الهوية (لأغراض محاسبية) وسجل الموافقات (دليل قانوني). تسجيل الدخول خلال الـ30 يوماً يلغي الطلب.'
      : 'Your public card is hidden, your medals switched off and you are signed out everywhere at once. After 30 days your identity and data are deleted for good, except the anonymised points ledger (for accounting) and the consent record (legal evidence). Signing in within the 30 days cancels the request.'
  }</p></section>
<section class="panel"><h2>${ar ? 'لا تستطيع فتح التطبيق؟' : 'Can’t open the app?'}</h2>
<p>${ar ? `راسلنا من البريد المرتبط بحسابك على ${email(links, lang)} واطلب الحذف.` : `Write to ${email(links, lang)} from the email on your account and ask us to delete it.`}</p></section>
</article>`;
  return shell(lang, 'delete-account', links, {
    title: ar ? 'حذف الحساب · يقين' : 'Delete account · Yaqeen',
    description: ar ? 'كيف تحذف حسابك في يقين وماذا يُحذف.' : 'How to delete your Yaqeen account and what is deleted.',
    body,
  });
}

export function robotsTxt(base: string): string {
  return `User-agent: *\nAllow: /\nDisallow: /u/\nDisallow: /t/\nDisallow: /v1/\nDisallow: /admin/\nDisallow: /go/\nSitemap: ${base}/sitemap.xml\n`;
}

export function sitemapXml(base: string): string {
  const pages: SitePage[] = ['home', 'privacy', 'terms', 'support', 'delete-account'];
  const urls = pages
    .flatMap((p) => (['ar', 'en'] as const).map((l) => `<url><loc>${escapeHtml(`${base}${path(p)}?lang=${l}`)}</loc><lastmod>${LEGAL_VERSION}</lastmod></url>`))
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>\n`;
}

/* Token values (packages/design-tokens): porcelain, ice, sky400, lapis, navy, ink, muted, gold, goldText, goldLight, cream, sand. */
const CSS = `
:root{--ink:#0A1530;--muted:#56637F;--lapis:#1F3F94;--navy:#10214D;--gold:#C6A867;--goldText:#7C6127;--goldLight:#E9D49E;--porcelain:#F3F6FB;--ice:#E9EFF9;--line:#DCE4F2;--glow:#ABC4E8;--cream:#FFFBF1;--sand:#F4E8C8}
*{box-sizing:border-box;margin:0}
html{-webkit-text-size-adjust:100%;scroll-behavior:smooth}
body{min-height:100vh;font-family:Tajawal,system-ui,sans-serif;color:var(--ink);background:linear-gradient(180deg,var(--ice),var(--porcelain) 50%);-webkit-font-smoothing:antialiased;overflow-x:hidden;line-height:1.7}
a{color:var(--lapis)}
.sky{position:fixed;inset:0;pointer-events:none;overflow:hidden;z-index:-1}
.glow{position:absolute;width:120vw;height:120vw;max-width:820px;max-height:820px;inset-inline-end:-40vw;top:-50vw;border-radius:50%;background:radial-gradient(closest-side,var(--glow),transparent);opacity:.5;animation:drift 18s ease-in-out infinite alternate}
.glow.two{inset-inline-end:auto;inset-inline-start:-50vw;top:auto;bottom:-60vw;opacity:.28;animation-duration:24s}
@keyframes drift{to{transform:translate3d(-6vw,4vw,0) scale(1.08)}}
.top{max-width:980px;margin:0 auto;padding:calc(env(safe-area-inset-top) + 16px) 16px 8px;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.logo img{display:block;height:auto;max-width:128px}
.top nav{display:flex;gap:4px;flex-wrap:wrap}
.top nav a{padding:8px 12px;border-radius:999px;text-decoration:none;color:var(--muted);font-size:14px}
.top nav a[aria-current]{color:var(--ink);background:rgba(255,255,255,.7);border:1px solid rgba(255,255,255,.95)}
.top nav .lang{color:var(--lapis)}
main{max-width:980px;margin:0 auto;padding:8px 16px 40px}
.hero{text-align:center;padding:48px 0 32px}
.eyebrow{color:var(--goldText);font-size:14px;letter-spacing:.3px}
h1{font-family:Amiri,Tajawal,serif;font-size:clamp(34px,7vw,56px);line-height:1.2;margin-top:8px}
.lead{max-width:620px;margin:16px auto 0;color:var(--muted);font-size:18px}
.actions{display:flex;gap:12px;justify-content:center;flex-wrap:wrap;margin-top:28px}
.btn{display:inline-block;min-height:48px;padding:12px 22px;border-radius:999px;text-decoration:none;font-weight:700;color:var(--lapis);background:rgba(255,255,255,.7);border:1px solid rgba(255,255,255,.95);box-shadow:0 14px 30px -20px rgba(15,26,54,.45)}
.btn.primary{color:#fff;background:linear-gradient(180deg,#2A52B8,var(--lapis));border-color:transparent}
.features{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px;margin:16px 0 24px}
.feature,.panel{padding:22px;border-radius:26px;background:rgba(255,255,255,.62);border:1px solid rgba(255,255,255,.92);box-shadow:0 24px 50px -36px rgba(15,26,54,.45);backdrop-filter:blur(16px) saturate(1.5);-webkit-backdrop-filter:blur(16px) saturate(1.5)}
.feature h3{font-size:18px}
.feature p,.panel p{color:var(--muted);margin-top:6px}
.panel{margin-top:16px}
.panel h2{font-family:Amiri,Tajawal,serif;font-size:24px}
.panel .btn{margin-top:14px}
.panel.gold{background:linear-gradient(180deg,var(--cream),var(--sand))}
.link{display:inline-block;margin-top:10px;font-weight:700}
.doc{max-width:760px;margin:16px auto 0}
.doc h1{font-size:clamp(30px,6vw,42px)}
.doc h2{font-size:20px;margin-top:28px}
.doc p{margin-top:10px}
.meta{color:var(--muted);font-size:14px}
.num{font-family:Jost,sans-serif}
.toc{margin-top:18px;padding:16px 20px;border-radius:20px;background:rgba(255,255,255,.55);border:1px solid rgba(255,255,255,.9)}
.toc ol{padding-inline-start:20px}
.faq{margin-top:12px;padding:14px 18px;border-radius:18px;background:rgba(255,255,255,.62);border:1px solid rgba(255,255,255,.92)}
.faq summary{cursor:pointer;font-weight:700;min-height:28px}
.steps{margin-top:16px;padding-inline-start:22px;font-size:18px}
.steps li{margin-top:6px}
.foot{max-width:980px;margin:0 auto;padding:16px 16px calc(env(safe-area-inset-bottom) + 24px);color:var(--muted);font-size:13px;text-align:center}
.rise{animation:rise .7s cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--d,0) * 70ms)}
@keyframes rise{from{opacity:0;transform:translateY(14px)}}
@media (prefers-reduced-motion:reduce){.glow,.rise{animation:none}}
`;
