/**
 * The web card's «تلاواتي» section (/u/<handle>): server-rendered markup + a tiny same-origin player
 * script served at /u/assets/recitations.js (the CSP allows script-src 'self' only; no inline script, no
 * inline handlers). Audio comes from /u/<handle>/r/<id>.m4a (media-src 'self'). Reference only
 * («سورة … · الآيات …»): the server holds no displayable Quran text, so no verse text is shown here; when
 * the recording carries verified word timings, its ayah numbers light up in turn as it plays.
 *
 * Motion follows the app's motion tokens (Flutter `Motion`, mirrored on the card's :root): quick
 * 160 ms, standard 280 ms, emphasised 450 ms on cubic-bezier(.2,0,0,1). One player at a time; the
 * hairline ring turns once per 12 s only while playing; reduced motion → static end states.
 */
import { REACTION_COPY, REACTION_KINDS, verseRef } from '@yaqeen/contracts';

export interface CardRecitation {
  id: string;
  surah: number;
  fromAyah: number;
  toAyah: number;
  durationMs: number;
  reactions: Record<(typeof REACTION_KINDS)[number], number>;
  audioUrl: string;
  /** Start (ms) of each ayah `fromAyah`…`toAyah` (verified word timings); absent/null = nothing to follow. */
  ayahStarts?: number[] | null;
}

const COPY = {
  ar: {
    title: 'تلاواتي',
    note: 'بصوت صاحب البطاقة',
    play: 'تشغيل التلاوة',
    react: 'تفاعل في تطبيق يقين',
  },
  en: {
    title: 'My recitations',
    note: 'In the card owner’s own voice',
    play: 'Play the recitation',
    react: 'React in the Yaqeen app',
  },
} as const;

const R = 26;
const C = 2 * Math.PI * R;

const esc = (s: string) => s.replace(/[&<>"'`]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' })[c]!);
const num = (v: number) => new Intl.NumberFormat('en-US').format(v);
const clock = (ms: number) => {
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

/**
 * Ayah numbers (Western digits) that light up in turn — only with one start per ayah of the range. The
 * row follows the page direction (right to left on the Arabic card, like the rings); each chip is a
 * single Western-digit run, so it needs no bidi isolation.
 */
function ayat(r: CardRecitation): string {
  const at = r.ayahStarts;
  const count = r.toAyah - r.fromAyah + 1;
  if (!at || at.length !== count || count < 2 || at.some((v) => !Number.isFinite(v) || v < 0)) return '';
  const items = at.map((_, i) => `<li>${num(r.fromAyah + i)}</li>`).join('');
  return `<ol class="ayat" aria-hidden="true" data-at="${at.map((v) => Math.round(v)).join(',')}">${items}</ol>`;
}

export function renderRecitations(items: CardRecitation[], lang: 'ar' | 'en', getApp: string): string {
  if (items.length === 0) return '';
  const t = COPY[lang];
  const rows = items
    .map((r, i) => {
      const ref = esc(verseRef(r.surah, r.fromAyah, r.toAyah, lang));
      const counts = REACTION_KINDS.filter((k) => r.reactions[k] > 0)
        .map((k, j) => `<span class="rx" style="--j:${j}"><b dir="ltr">${num(r.reactions[k])}</b>${esc(REACTION_COPY[k][lang])}</span>`)
        .join('');
      return `<article class="rec" style="--i:${i}" data-dur="${r.durationMs}">
<button class="play" type="button" aria-pressed="false" aria-label="${t.play} · ${ref}">
<svg viewBox="0 0 60 60" aria-hidden="true"><circle class="trk" cx="30" cy="30" r="${R}"/><circle class="prog" cx="30" cy="30" r="${R}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${C.toFixed(2)}" data-c="${C.toFixed(2)}"/><circle class="hair" cx="30" cy="30" r="29.2"/></svg>
<i class="ico" aria-hidden="true"></i>
</button>
<div class="meta"><b>${ref}</b><span class="dur" dir="ltr">${clock(r.durationMs)}</span>${ayat(r)}${counts ? `<span class="rxs">${counts}</span>` : ''}</div>
<audio preload="none" src="${esc(r.audioUrl)}"></audio>
</article>`;
    })
    .join('');
  return `<section class="recs rise" style="--d:4" aria-label="${t.title}">
<h2 class="sec">${t.title}<small>${t.note}</small></h2>
${rows}
<a class="rx-cta" href="${esc(getApp)}">${t.react}</a>
</section>
<script src="/u/assets/recitations.js" defer></script>`;
}

/**
 * Styles for the section, appended to the card's stylesheet. Theme colours and the motion tokens
 * (--t-quick, --t-std, --t-emph, --ease-emph, --ease-out) come from the card's :root; the accent is
 * lapis on porcelain and cream, light gold at night. The play glyph is not mirrored in RTL (media
 * convention, as in the app); the progress ring fills in the reading direction like the level ring.
 */
export const RECITATIONS_CSS = `
.recs{--accent:var(--lapis);--on-accent:#fff;margin-top:22px;padding:18px 16px 14px;border-radius:28px;background:var(--glass);border:1px solid var(--rim);box-shadow:0 22px 40px -30px rgba(15,26,54,.4)}
.theme-night .recs{--accent:var(--goldLight);--on-accent:#0A1530}
.recs .sec{display:flex;align-items:baseline;justify-content:space-between;gap:8px}
.recs .sec small{font-size:11px;font-weight:500;color:var(--muted);letter-spacing:0}
.rec{display:flex;align-items:center;gap:14px;padding:10px 4px;border-top:1px solid var(--track);animation:rise var(--t-emph) var(--ease-emph) both;animation-delay:calc(.5s + var(--i,0) * 40ms)}
.rec:first-of-type{border-top:0}
.play{position:relative;flex:none;width:60px;height:60px;border:0;padding:0;border-radius:50%;background:transparent;cursor:pointer;color:var(--accent);-webkit-tap-highlight-color:transparent;transition:transform var(--t-quick) var(--ease-out)}
.play:active{transform:scale(.92)}
.play:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
.play svg{position:absolute;inset:0;width:60px;height:60px;transform:rotate(-90deg)}
[dir=rtl] .play svg{transform:rotate(-90deg) scaleY(-1)}
.play circle{fill:none}
.play .trk{stroke:var(--track);stroke-width:3}
.play .prog{stroke:var(--accent);stroke-width:3;stroke-linecap:round;transition:stroke-dashoffset var(--t-std) var(--ease-emph)}
.rec.playing .prog{transition:none}
.play .hair{stroke:var(--accent);stroke-width:.6;stroke-dasharray:2 7;opacity:0;transform-origin:30px 30px;transition:opacity var(--t-std) var(--ease-emph);animation:hairline 12s linear infinite paused}
.rec.playing .hair{opacity:.55;animation-play-state:running}
@keyframes hairline{to{transform:rotate(360deg)}}
.ico{position:absolute;inset:0;margin:auto;width:15px;height:17px;transform:translateX(1.5px);transition:transform var(--t-std) var(--ease-emph)}
.ico::before,.ico::after{content:"";position:absolute;inset:0;background:currentColor;transition:clip-path var(--t-std) var(--ease-emph)}
.ico::before{clip-path:polygon(0 0,50% 25%,50% 75%,0 100%)}
.ico::after{clip-path:polygon(50% 25%,100% 50%,100% 50%,50% 75%)}
.rec.playing .ico{transform:none}
.rec.playing .ico::before{clip-path:polygon(0 0,34% 0,34% 100%,0 100%)}
.rec.playing .ico::after{clip-path:polygon(66% 0,100% 0,100% 100%,66% 100%)}
.meta{flex:1;min-width:0;display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 10px}
.meta b{flex-basis:100%;font-size:15px;font-weight:700;line-height:1.5;transition:color var(--t-std) var(--ease-emph)}
.rec.playing .meta b{color:var(--accent)}
.dur{font-family:Jost,sans-serif;font-size:12px;color:var(--muted);font-variant-numeric:tabular-nums}
.ayat{display:flex;flex-wrap:wrap;gap:4px;list-style:none;padding:0;margin:0}
.ayat li{min-width:22px;height:22px;padding:0 6px;border-radius:999px;display:grid;place-items:center;font-family:Jost,sans-serif;font-size:11px;font-variant-numeric:tabular-nums;color:var(--muted);border:1px solid var(--track);transition:background-color var(--t-quick) var(--ease-out),color var(--t-quick) var(--ease-out),border-color var(--t-quick) var(--ease-out),transform var(--t-std) var(--ease-emph)}
.ayat li.done{color:var(--ink);border-color:var(--accent)}
.ayat li.on{color:var(--on-accent);background:var(--accent);border-color:var(--accent);transform:scale(1.08)}
.rxs{display:flex;flex-wrap:wrap;gap:6px}
.rx{display:inline-flex;align-items:center;gap:5px;padding:3px 9px;border-radius:999px;font-size:11px;color:var(--muted);background:rgba(255,255,255,.35);border:1px solid var(--track);animation:rise var(--t-std) var(--ease-emph) both;animation-delay:calc(.62s + var(--i,0) * 40ms + var(--j,0) * 40ms)}
.theme-night .rx{background:rgba(255,255,255,.06)}
.rx b{font-family:Jost,sans-serif;font-weight:500;color:var(--ink);font-variant-numeric:tabular-nums}
.rx-cta{display:block;margin:8px 4px 2px;font-size:12px;font-weight:700;color:var(--accent);text-decoration:none}
.rec audio{display:none}
@media (prefers-reduced-motion:reduce){.rec,.rx,.play .hair{animation:none}.play,.ico,.ico::before,.ico::after,.play .prog,.play .hair,.meta b,.ayat li{transition:none}.ayat li.on{transform:none}}
`;

/**
 * The player: one recitation at a time (starting one pauses the rest, however it was started), an SVG
 * progress ring, ayah numbers following the timings, aria-pressed and keyboard-friendly. It draws per
 * frame only while playing; with reduced motion the ring steps on timeupdate instead. The empty passive
 * touchstart listener lets iOS Safari apply `.play:active` (the 160 ms press shrink) on touch.
 */
export const RECITATIONS_JS = `(function(){
document.addEventListener('touchstart',function(){},{passive:true});
var mq=window.matchMedia?window.matchMedia('(prefers-reduced-motion: reduce)'):null;
var all=[].slice.call(document.querySelectorAll('.rec'));
function still(){return !!(mq&&mq.matches);}
all.forEach(function(el){
var a=el.querySelector('audio'),b=el.querySelector('.play'),p=el.querySelector('.prog');
if(!a||!b||!p)return;
var c=parseFloat(p.getAttribute('data-c'))||1,raf=0,cur=-2;
var ol=el.querySelector('.ayat'),li=ol?[].slice.call(ol.children):[];
var at=ol?String(ol.getAttribute('data-at')).split(',').map(Number):[];
function mark(ms){if(!li.length)return;var k=-1,i;
if(ms>=0){for(i=0;i<at.length;i++){if(at[i]<=ms)k=i;else break;}}
if(k===cur)return;cur=k;
li.forEach(function(x,j){x.classList.toggle('on',j===k);x.classList.toggle('done',j<k);});}
function draw(){var d=a.duration&&isFinite(a.duration)?a.duration:(parseFloat(el.getAttribute('data-dur'))/1000||1);
p.style.strokeDashoffset=String(c*(1-Math.min(1,a.currentTime/d)));
mark(a.paused&&a.currentTime===0?-1:a.currentTime*1000);
if(!a.paused&&!still())raf=requestAnimationFrame(draw);}
function off(){el.classList.remove('playing');b.setAttribute('aria-pressed','false');cancelAnimationFrame(raf);}
b.addEventListener('click',function(){
if(a.paused){var pr=a.play();if(pr&&pr.catch)pr.catch(function(){off();});}
else a.pause();});
a.addEventListener('play',function(){
all.forEach(function(o){var oa=o.querySelector('audio');if(o!==el&&oa&&!oa.paused)oa.pause();});
el.classList.add('playing');b.setAttribute('aria-pressed','true');cancelAnimationFrame(raf);raf=requestAnimationFrame(draw);});
a.addEventListener('timeupdate',function(){if(still())draw();});
a.addEventListener('pause',function(){off();draw();});
a.addEventListener('error',function(){off();});
a.addEventListener('ended',function(){off();a.currentTime=0;draw();});
});
})();
`;
