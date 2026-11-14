/**
 * The web card's «تلاواتي» section (/u/<handle>): server-rendered markup + a tiny same-origin player
 * script served at /u/assets/recitations.js (the CSP allows script-src 'self' only; no inline script, no
 * inline handlers). Audio comes from /u/<handle>/r/<id>.m4a (media-src 'self'). Without the script the
 * native <audio> controls still work. Reference only («سورة … · الآيات …»): the server holds no
 * displayable Quran text, so no verse text is shown here.
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

export function renderRecitations(items: CardRecitation[], lang: 'ar' | 'en', getApp: string): string {
  if (items.length === 0) return '';
  const t = COPY[lang];
  const rows = items
    .map((r, i) => {
      const ref = esc(verseRef(r.surah, r.fromAyah, r.toAyah, lang));
      const counts = REACTION_KINDS.filter((k) => r.reactions[k] > 0)
        .map((k) => `<span class="rx"><b dir="ltr">${num(r.reactions[k])}</b>${esc(REACTION_COPY[k][lang])}</span>`)
        .join('');
      return `<article class="rec" style="--i:${i}" data-dur="${r.durationMs}">
<button class="play" type="button" aria-pressed="false" aria-label="${t.play} · ${ref}">
<svg viewBox="0 0 60 60" aria-hidden="true"><circle class="trk" cx="30" cy="30" r="${R}"/><circle class="prog" cx="30" cy="30" r="${R}" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${C.toFixed(2)}" data-c="${C.toFixed(2)}"/><circle class="hair" cx="30" cy="30" r="29.2"/></svg>
<i class="ico"></i>
</button>
<div class="meta"><b>${ref}</b><span class="dur" dir="ltr">${clock(r.durationMs)}</span>${counts ? `<span class="rxs">${counts}</span>` : ''}</div>
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

/** Styles for the section, appended to the card's stylesheet (theme tokens from the page's :root). */
export const RECITATIONS_CSS = `
.recs{margin-top:22px;padding:18px 16px 14px;border-radius:28px;background:var(--glass);border:1px solid var(--rim);box-shadow:0 22px 40px -30px rgba(15,26,54,.4)}
.recs .sec{display:flex;align-items:baseline;justify-content:space-between;gap:8px}
.recs .sec small{font-size:11px;font-weight:500;color:var(--muted);letter-spacing:0}
.rec{display:flex;align-items:center;gap:14px;padding:10px 4px;border-top:1px solid var(--track);animation:rise .7s cubic-bezier(.2,.7,.2,1) both;animation-delay:calc(.5s + var(--i,0) * 90ms)}
.rec:first-of-type{border-top:0}
.play{position:relative;flex:none;width:60px;height:60px;border:0;padding:0;border-radius:50%;background:transparent;cursor:pointer;color:var(--lapis);-webkit-tap-highlight-color:transparent}
.play:focus-visible{outline:2px solid var(--lapis);outline-offset:3px}
.play svg{position:absolute;inset:0;width:60px;height:60px;transform:rotate(-90deg)}
[dir=rtl] .play svg{transform:rotate(-90deg) scaleY(-1)}
.play circle{fill:none}
.play .trk{stroke:var(--track);stroke-width:3}
.play .prog{stroke:var(--lapis);stroke-width:3;stroke-linecap:round;transition:stroke-dashoffset .12s linear}
.play .hair{stroke:var(--lapis);stroke-width:.6;stroke-dasharray:2 7;opacity:0;transform-origin:30px 30px}
.rec.playing .hair{opacity:.55;animation:hairline 14s linear infinite}
@keyframes hairline{to{transform:rotate(360deg)}}
.ico{position:absolute;inset:0;margin:auto;width:0;height:0;border-block:9px solid transparent;border-inline-start:14px solid currentColor;transform:translateX(2px)}
[dir=rtl] .ico{transform:translateX(-2px) scaleX(-1)}
.rec.playing .ico{width:13px;height:16px;border:0;border-inline:4px solid currentColor;transform:none}
.meta{flex:1;min-width:0;display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 10px}
.meta b{flex-basis:100%;font-size:15px;font-weight:700;line-height:1.5}
.dur{font-family:Jost,sans-serif;font-size:12px;color:var(--muted)}
.rxs{display:flex;flex-wrap:wrap;gap:6px}
.rx{display:inline-flex;align-items:center;gap:5px;padding:3px 9px;border-radius:999px;font-size:11px;color:var(--muted);background:rgba(255,255,255,.35);border:1px solid var(--track)}
.theme-night .rx{background:rgba(255,255,255,.06)}
.rx b{font-family:Jost,sans-serif;font-weight:500;color:var(--ink)}
.rx-cta{display:block;margin:8px 4px 2px;font-size:12px;font-weight:700;color:var(--lapis);text-decoration:none}
.theme-night .rx-cta,.theme-night .play{color:var(--goldLight)}
.theme-night .play .prog,.theme-night .play .hair{stroke:var(--goldLight)}
.rec audio{display:none}
@media (prefers-reduced-motion:reduce){.rec.playing .hair{animation:none}.play .prog{transition:none}}
`;

/** The player: one recitation at a time, an SVG progress ring, aria-pressed and keyboard-friendly. */
export const RECITATIONS_JS = `(function(){
var all=[].slice.call(document.querySelectorAll('.rec'));
all.forEach(function(el){
var a=el.querySelector('audio'),b=el.querySelector('.play'),p=el.querySelector('.prog');
if(!a||!b||!p)return;
var c=parseFloat(p.getAttribute('data-c'))||1,raf=0;
function draw(){var d=a.duration&&isFinite(a.duration)?a.duration:(parseFloat(el.getAttribute('data-dur'))/1000||1);
p.style.strokeDashoffset=String(c*(1-Math.min(1,a.currentTime/d)));if(!a.paused)raf=requestAnimationFrame(draw);}
b.addEventListener('click',function(){
if(a.paused){all.forEach(function(o){var oa=o.querySelector('audio');if(o!==el&&oa&&!oa.paused)oa.pause();});var pr=a.play();if(pr&&pr.catch)pr.catch(function(){});}
else a.pause();});
a.addEventListener('play',function(){el.classList.add('playing');b.setAttribute('aria-pressed','true');cancelAnimationFrame(raf);raf=requestAnimationFrame(draw);});
a.addEventListener('pause',function(){el.classList.remove('playing');b.setAttribute('aria-pressed','false');cancelAnimationFrame(raf);draw();});
a.addEventListener('ended',function(){a.currentTime=0;draw();});
});
})();
`;
