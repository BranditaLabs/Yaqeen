/**
 * Admin-editable settings of the public-card programme (`app_config` key `cards`): the medal product
 * link, the page's store link and CTA copy, and handles nobody may take. Empty fields fall back to
 * the env links and the built-in copy.
 */
import { eq } from 'drizzle-orm';
import { CardsSettings, RESERVED_HANDLES } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { appConfig } from '../db/schema.js';

export const CARDS_CONFIG_KEY = 'cards';

export async function readCardsSettings(ctx: AppContext): Promise<CardsSettings> {
  const json = await ctx.cache.getJson('config', CARDS_CONFIG_KEY, 60, async () => {
    const [row] = await ctx.db.select({ value: appConfig.value }).from(appConfig).where(eq(appConfig.key, CARDS_CONFIG_KEY));
    const parsed = CardsSettings.safeParse(row?.value ?? {});
    return parsed.success ? parsed.data : CardsSettings.parse({});
  });
  return JSON.parse(json) as CardsSettings;
}

/** Built-in reserved names plus the ones support added. */
export async function isReservedHandle(ctx: AppContext, handle: string): Promise<boolean> {
  const h = handle.trim().toLowerCase();
  if (RESERVED_HANDLES.has(h)) return true;
  return (await readCardsSettings(ctx)).reservedHandles.includes(h);
}

/** The store link the card page sends shoppers to. */
export async function storeUrl(ctx: AppContext): Promise<string> {
  return (await readCardsSettings(ctx)).storeUrl || ctx.env.STORE_URL;
}

/** The two switches of the programme (`features.publicCards`, `features.medalActivation`), on unless turned off. */
export async function cardFeatureOn(ctx: AppContext, flag: 'publicCards' | 'medalActivation'): Promise<boolean> {
  const json = await ctx.cache.getJson('config', `feature:${flag}`, 30, async () => {
    const [row] = await ctx.db.select({ value: appConfig.value }).from(appConfig).where(eq(appConfig.key, 'features'));
    return ((row?.value ?? {}) as Record<string, boolean>)[flag] !== false;
  });
  return JSON.parse(json) as boolean;
}
