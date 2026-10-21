// Generates tokens.css from tokens.json (single source of truth). Run: pnpm --filter @yaqeen/design-tokens build
import { readFileSync, writeFileSync } from 'node:fs';
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
const out = lines.join('\n') + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(join(root, 'tokens.css'), 'utf8') !== out) {
    console.error('tokens.css is stale — run: pnpm --filter @yaqeen/design-tokens build');
    process.exit(1);
  }
  console.log(`design-tokens: ${Object.keys(t.color).length} colours in sync`);
} else {
  writeFileSync(join(root, 'tokens.css'), out);
  console.log(`tokens.css written (${Object.keys(t.color).length} colours)`);
}
