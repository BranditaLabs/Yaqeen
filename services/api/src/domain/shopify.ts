/**
 * Shopify discount-code builders — pure functions.
 * The API creates a single-use, customer-agnostic code per redemption via the Admin GraphQL API.
 */
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { RewardKind } from '@yaqeen/contracts';

/** No 0/O/1/I to avoid misreading codes typed at checkout. */
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function generateCode(prefix = 'YQ'): string {
  const block = () => Array.from({ length: 4 }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
  return `${prefix}-${block()}-${block()}`;
}

export const DISCOUNT_BASIC_CREATE = /* GraphQL */ `
  mutation CreateBasic($basicCodeDiscount: DiscountCodeBasicInput!) {
    discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
      codeDiscountNode { id }
      userErrors { field message code }
    }
  }
`;

export const DISCOUNT_FREE_SHIPPING_CREATE = /* GraphQL */ `
  mutation CreateFreeShipping($freeShippingCodeDiscount: DiscountCodeFreeShippingInput!) {
    discountCodeFreeShippingCreate(freeShippingCodeDiscount: $freeShippingCodeDiscount) {
      codeDiscountNode { id }
      userErrors { field message code }
    }
  }
`;

export interface DiscountRequest {
  query: string;
  variables: Record<string, unknown>;
  resultKey: 'discountCodeBasicCreate' | 'discountCodeFreeShippingCreate';
}

export function buildDiscountRequest(args: {
  code: string;
  title: string;
  kind: RewardKind;
  value: number;
  collectionIds: string[];
  startsAt: Date;
  endsAt: Date;
}): DiscountRequest {
  const { code, title, kind, value, collectionIds, startsAt, endsAt } = args;
  const common = {
    title,
    code,
    startsAt: startsAt.toISOString(),
    endsAt: endsAt.toISOString(),
    usageLimit: 1,
    appliesOncePerCustomer: true,
    customerSelection: { all: true },
  };

  if (kind === 'free_shipping') {
    return {
      query: DISCOUNT_FREE_SHIPPING_CREATE,
      resultKey: 'discountCodeFreeShippingCreate',
      variables: { freeShippingCodeDiscount: { ...common, destination: { all: true } } },
    };
  }

  const items = collectionIds.length > 0 ? { collections: { add: collectionIds } } : { all: true };
  const discountValue =
    kind === 'percentage'
      ? { percentage: Math.min(100, value) / 100 }
      : { discountAmount: { amount: value.toFixed(2), appliesOnEachItem: false } };

  return {
    query: DISCOUNT_BASIC_CREATE,
    resultKey: 'discountCodeBasicCreate',
    variables: { basicCodeDiscount: { ...common, customerGets: { value: discountValue, items } } },
  };
}

/* ------------------------------------------------------------ webhooks */

/** Shopify signs webhooks with base64(HMAC-SHA256(raw body, secret)) in X-Shopify-Hmac-Sha256. */
export function verifyWebhookHmac(rawBody: Buffer, header: string | undefined, secret: string): boolean {
  if (!secret || !header) return false;
  const expected = createHmac('sha256', secret).update(rawBody).digest();
  const given = Buffer.from(header, 'base64');
  return given.length === expected.length && timingSafeEqual(given, expected);
}

/** Our codes used on a paid order (other discount codes on the order are ignored). */
export function yaqeenCodesIn(order: unknown): string[] {
  const codes = (order as { discount_codes?: { code?: unknown }[] } | null)?.discount_codes ?? [];
  if (!Array.isArray(codes)) return [];
  return [
    ...new Set(
      codes
        .map((d) => (typeof d?.code === 'string' ? d.code.trim().toUpperCase() : ''))
        .filter((c) => /^YQ-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(c)),
    ),
  ];
}
