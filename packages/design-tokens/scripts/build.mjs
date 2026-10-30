// Generates tokens.css from tokens.json (single source of truth). Run: pnpm --filter @yaqeen/design-tokens build
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const t = JSON.parse(readFileSync(join(root, 'tokens.json'), 'utf8'));
const lines = ['/* GENERATED from tokens.json by scripts/build.mjs — do not edit by hand. */', ':root {'];
for (const [k, v] of Object.entries(t.color)) lines.push(`  --yq-${k}: ${v};`);
for (const [k, v] of Object.entries(t.radius)) lines.push(`  --yq-radius-${k}: ${v}px;`);
const g = t.gradient.brand;
lines.push(`  --yq-gradient-brand: linear-gradient(${g.angleDeg}deg, ${g.stops.map(([c, p]) => `${c} ${p * 100}%`).join(', ')});`);
lines.push(`  --yq-font-brand-ar: '${t.font.brandArabic.family}', ${t.font.brandArabic.fallback.map((f) => `'${f}'`).join(', ')};`);
lines.push(`  --yq-font-brand-en: '${t.font.brandLatin.family}', ${t.font.brandLatin.fallback.map((f) => (f === 'serif' ? f : `'${f}'`)).join(', ')};`);
lines.push(`  --yq-ease: cubic-bezier(${t.motion.ease.join(', ')});`);
lines.push('}');
const css = lines.join('\n') + '\n';

// Native home-screen widgets (spec §5.28) take their colours from the same tokens.
const hex = (v) => v.replace('#', '').toUpperCase();
const snake = (k) => k.replace(/([A-Z])/g, '_$1').replace(/(\d+)/g, '_$1').toLowerCase();
const android = [
  '<?xml version="1.0" encoding="utf-8"?>',
  '<!-- GENERATED from packages/design-tokens/tokens.json by scripts/build.mjs — do not edit by hand. -->',
  '<resources>',
  ...Object.entries(t.color).map(([k, v]) => `    <color name="yq_${snake(k)}">#FF${hex(v)}</color>`),
  '</resources>',
  '',
].join('\n');
const swift = [
  '// GENERATED from packages/design-tokens/tokens.json by scripts/build.mjs — do not edit by hand.',
  'import SwiftUI',
  '',
  'enum YqTokens {',
  ...Object.entries(t.color).map(([k, v]) => {
    const n = parseInt(hex(v), 16);
    const c = (shift) => ((n >> shift) & 255) / 255;
    return `    static let ${k} = Color(red: ${c(16).toFixed(4)}, green: ${c(8).toFixed(4)}, blue: ${c(0).toFixed(4)})`;
  }),
  '}',
  '',
].join('\n');

const repo = join(root, '..', '..');

// DESIGN.md (Google Stitch / awesome-design-md format) for design agents: the YAML front matter is
// generated from the tokens; the prose below the second `---` is hand-written and kept as is.
const kebab = (k) => k.replace(/([A-Z])/g, '-$1').replace(/(\d+)/g, '-$1').toLowerCase();
const fam = (f) => [f.family, ...f.fallback].join(', ');
const frontMatter = [
  '---',
  '# GENERATED from packages/design-tokens/tokens.json by scripts/build.mjs — edit the tokens, not this block.',
  'version: alpha',
  'name: Yaqeen',
  'description: A premium Islamic companion on a living canvas — light porcelain glass under a sky that follows the day by the real prayer times, one large moment per screen, live instruments that work in place, the day as a journey. Arabic RTL first, Western digits, lapis as the only accent, gold for worship and reward, no ornament.',
  '',
  'colors:',
  ...Object.entries(t.color).map(([k, v]) => `  ${kebab(k)}: "${v}"`),
  '',
  'typography:',
  `  display-ar: { fontFamily: "${fam(t.font.brandArabic)}", fontWeight: 700 }`,
  `  display-en: { fontFamily: "${fam(t.font.brandLatin)}", fontWeight: 700 }`,
  `  ui: { fontFamily: "${t.font.ui}" }`,
  `  numbers: { fontFamily: "${t.font.numbers}", fontFeature: tnum }`,
  `  quran: { fontFamily: "${t.font.quran}" }`,
  `  naskh: { fontFamily: "${t.font.naskh}" }`,
  '',
  'rounded:',
  ...Object.entries(t.radius).map(([k, v]) => `  ${k}: ${v}px`),
  '',
  'spacing:',
  ...Object.entries(t.space).map(([k, v]) => `  ${k}: ${v}px`),
  '',
  'motion:',
  `  ease: "cubic-bezier(${t.motion.ease.join(', ')})"`,
  `  fast: ${t.motion.fastMs}ms`,
  `  base: ${t.motion.baseMs}ms`,
  `  slow: ${t.motion.slowMs}ms`,
  '',
  'glass:',
  `  fillOpacity: ${t.glass.fillOpacity}`,
  `  blur: ${t.glass.blurPx}px`,
  `  saturate: ${t.glass.saturate}`,
  `  rim: "${t.glass.rim}"`,
  '',
  `gradient-brand: "linear-gradient(${g.angleDeg}deg, ${g.stops.map(([c, p]) => `${c} ${p * 100}%`).join(', ')})"`,
  '---',
].join('\n');
const designPath = join(repo, 'DESIGN.md');
const designMd = (() => {
  const current = readFileSync(designPath, 'utf8');
  const end = current.indexOf('\n---', 4); // the front matter's closing fence
  return frontMatter + current.slice(end + 4);
})();

const outputs = [
  [join(root, 'tokens.css'), css],
  [join(repo, 'apps/mobile/android/app/src/main/res/values/yq_tokens.xml'), android],
  [join(repo, 'apps/mobile/ios/YaqeenWidget/YqTokens.swift'), swift],
  [designPath, designMd],
];
if (process.argv.includes('--check')) {
  const stale = outputs.filter(([f, body]) => {
    try {
      return readFileSync(f, 'utf8') !== body;
    } catch {
      return true;
    }
  });
  if (stale.length) {
    console.error(`stale: ${stale.map(([f]) => f.slice(repo.length + 1)).join(', ')} — run: pnpm --filter @yaqeen/design-tokens build`);
    process.exit(1);
  }
  console.log(`design-tokens: ${Object.keys(t.color).length} colours in sync (css, android, ios, DESIGN.md)`);
} else {
  for (const [f, body] of outputs) {
    mkdirSync(dirname(f), { recursive: true });
    writeFileSync(f, body);
  }
  console.log(`tokens written (${Object.keys(t.color).length} colours → css, android, ios, DESIGN.md)`);
}
