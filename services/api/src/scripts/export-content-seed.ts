/**
 * Writes the published duas/azkar to the app's bundled seed (spec §6.11) so a first launch works
 * offline. Only `published` items — i.e. approved by a religious reviewer who is not the author —
 * are exported; nothing is ever typed into the seed by hand.
 *
 *   DATABASE_URL=… pnpm --filter @yaqeen/api content:export [out=../../apps/mobile/assets/content/seed.json]
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { and, asc, eq, inArray } from 'drizzle-orm';
import { createDb } from '../db/client.js';
import { contentItems } from '../db/schema.js';

const url = process.env.DATABASE_URL;
if (!url) throw new Error('DATABASE_URL is required');
const out = resolve(process.argv[2] ?? '../../apps/mobile/assets/content/seed.json');

const { db, pool } = createDb(url);
const items = await db
  .select({
    id: contentItems.id,
    type: contentItems.type,
    category: contentItems.category,
    title: contentItems.title,
    textAr: contentItems.textAr,
    translationEn: contentItems.translationEn,
    source: contentItems.source,
    virtue: contentItems.virtue,
    repeatCount: contentItems.repeatCount,
    sortOrder: contentItems.sortOrder,
    featured: contentItems.featured,
    version: contentItems.version,
    updatedAt: contentItems.updatedAt,
  })
  .from(contentItems)
  .where(and(eq(contentItems.status, 'published'), inArray(contentItems.type, ['dua', 'zikr'])))
  .orderBy(asc(contentItems.category), asc(contentItems.sortOrder), asc(contentItems.title));

writeFileSync(out, `${JSON.stringify({ exportedAt: new Date().toISOString(), items }, null, 1)}\n`);
console.log(`${items.length} published items → ${out}`);
await pool.end();
