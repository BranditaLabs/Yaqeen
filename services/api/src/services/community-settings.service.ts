/**
 * Settings of the opt-in community: the competition flags (`leagues`, `tournaments`, `leaderboard`,
 * off until an admin turns them on), the league settings (`app_config 'leagues'`, zod defaults; a
 * week keeps the settings it started with) and the names that may not be used.
 */
import { eq } from 'drizzle-orm';
import { DIVISIONS, FEATURE_DEFAULTS_OFF, LeagueSettings, LeagueSettingsBase, RESERVED_HANDLES } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { appConfig } from '../db/schema.js';
import { forbidden } from '../lib/errors.js';
import { readCardsSettings } from './cards-settings.service.js';

/** What community services need from the app context (the job builds one without HTTP clients). */
export type CommunityCtx = Pick<AppContext, 'db' | 'now' | 'cache' | 'env'>;

export const LEAGUES_CONFIG_KEY = 'leagues';

export type CommunityFlag = 'leagues' | 'tournaments' | 'leaderboard';
type Flag = CommunityFlag | 'publicCards' | 'medalActivation';

/** A feature flag from `app_config 'features'`; flags in `FEATURE_DEFAULTS_OFF` are off unless set. */
export async function featureOn(ctx: CommunityCtx, flag: Flag): Promise<boolean> {
  const json = await ctx.cache.getJson('config', `feature:${flag}`, 30, async () => {
    const [row] = await ctx.db.select({ value: appConfig.value }).from(appConfig).where(eq(appConfig.key, 'features'));
    const value = ((row?.value ?? {}) as Record<string, boolean>)[flag];
    const defaultOff = (FEATURE_DEFAULTS_OFF as readonly string[]).includes(flag);
    return defaultOff ? value === true : value !== false;
  });
  return JSON.parse(json) as boolean;
}

/** 403 `feature_off` while the flag is off. */
export async function requireFeature(ctx: CommunityCtx, flag: CommunityFlag): Promise<void> {
  if (!(await featureOn(ctx, flag))) throw forbidden('feature_off', `${flag} is not available`);
}

/** The league settings for weeks that start from now on (zod defaults when unset or invalid). */
export async function readLeagueSettings(ctx: CommunityCtx): Promise<LeagueSettings> {
  const json = await ctx.cache.getJson('config', LEAGUES_CONFIG_KEY, 60, async () => {
    const [row] = await ctx.db.select({ value: appConfig.value }).from(appConfig).where(eq(appConfig.key, LEAGUES_CONFIG_KEY));
    return parseLeagueSettings(row?.value);
  });
  return JSON.parse(json) as LeagueSettings;
}

/** Stored settings (a week's snapshot or app_config) → valid settings, defaults on any problem. */
export function parseLeagueSettings(value: unknown): LeagueSettings {
  const parsed = LeagueSettings.safeParse(value ?? {});
  return parsed.success ? parsed.data : LeagueSettingsBase.parse({});
}

/** The names of a division (admin renames apply from the week that started with them). */
export function divisionName(settings: Pick<LeagueSettings, 'divisionNames'> | null | undefined, division: number): { ar: string; en: string } {
  const custom = settings?.divisionNames?.[division - 1];
  if (custom) return { ar: custom.ar, en: custom.en };
  const d = DIVISIONS[Math.min(6, Math.max(1, division)) - 1]!;
  return { ar: d.ar, en: d.en };
}

/** Built-in reserved handles plus the ones support added in the cards settings. */
export async function reservedNames(ctx: CommunityCtx): Promise<string[]> {
  const s = await readCardsSettings(ctx as AppContext);
  return [...RESERVED_HANDLES, ...s.reservedHandles];
}
