/**
 * Writes the published duas/azkar to the app's bundled seed (spec §6.11) so a first launch works
 * offline. Only approved versions (`live`) — i.e. approved by a religious reviewer who is not the author —
 * are exported; nothing is ever typed into the seed by hand.
 *
 *   DATABASE_URL=… pnpm --filter @yaqeen/api content:export [out=../../apps/mobile/assets/content/seed.json]
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { and, inArray, isNotNull } from 'drizzle-orm';
import { createDb } from '../db/client.js';
import { contentItems } from '../db/schema.js';

const url = process.env.DATABASE_URL;
if (!url) throw new Error('DATABASE_URL is required');
const out = resolve(process.argv[2] ?? '../../apps/mobile/assets/content/seed.json');

const { db, pool } = createDb(url);
const rows = await db
  .select({ id: contentItems.id, type: contentItems.type, live: contentItems.live, liveAt: contentItems.liveAt })
  .from(contentItems)
  .where(and(isNotNull(contentItems.live), inArray(contentItems.type, ['dua', 'zikr'])));
// The approved snapshot — the same text /v1/content serves, even while an edit is in review.
const items = rows
  .map((r) => ({ id: r.id, type: r.type, ...r.live!, updatedAt: r.liveAt }))
  .sort((a, b) => a.category.localeCompare(b.category) || a.sortOrder - b.sortOrder || a.title.localeCompare(b.title));

writeFileSync(out, `${JSON.stringify({ exportedAt: new Date().toISOString(), items }, null, 1)}\n`);
console.log(`${items.length} published items → ${out}`);
await pool.end();
