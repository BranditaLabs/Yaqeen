import { desc, eq } from 'drizzle-orm';
import type { HijriDay } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { hijriAdjustments } from '../db/schema.js';
import { type HijriAdjustment, applyAdjustments, validateSequence } from '../domain/hijri.js';
import { addDays } from '../domain/points.js';

const PAD = 3;

export async function adjustmentsFor(ctx: AppContext, region: string): Promise<HijriAdjustment[]> {
  return ctx.db
    .select({
      offsetDays: hijriAdjustments.offsetDays,
      effectiveHijriYear: hijriAdjustments.effectiveHijriYear,
      effectiveHijriMonth: hijriAdjustments.effectiveHijriMonth,
      createdAt: hijriAdjustments.createdAt,
    })
    .from(hijriAdjustments)
    .where(eq(hijriAdjustments.region, region))
    .orderBy(desc(hijriAdjustments.createdAt));
}

/** Regional (and optional personal) adjusted Hijri days for [from, to]. */
export async function hijriRange(
  ctx: AppContext,
  from: string,
  to: string,
  opts: { region?: string; personalOffset?: number; adjustments?: HijriAdjustment[] } = {},
): Promise<HijriDay[]> {
  const region = opts.region ?? ctx.env.HIJRI_REGION;
  const adjustments = opts.adjustments ?? (await adjustmentsFor(ctx, region));
  const uaq = await ctx.aladhan.range(addDays(from, -PAD), addDays(to, PAD));
  return applyAdjustments(uaq, adjustments, opts.personalOffset ?? 0).filter(
    (d) => d.gregorian >= from && d.gregorian <= to,
  );
}

export async function hijriFor(ctx: AppContext, date: string, personalOffset = 0): Promise<HijriDay | null> {
  const [d] = await hijriRange(ctx, date, date, { personalOffset });
  return d ?? null;
}

/** Admin preview: what the next ~60 days look like with a proposed adjustment added. */
export async function previewAdjustment(ctx: AppContext, proposed: HijriAdjustment, from: string) {
  const current = await adjustmentsFor(ctx, ctx.env.HIJRI_REGION);
  const to = addDays(from, 60);
  const days = await hijriRange(ctx, from, to, { adjustments: [...current, proposed] });
  const firstOfMonths = days.filter((d) => d.hijriDay === 1);
  return { firstOfMonths, warnings: validateSequence(days) };
}
