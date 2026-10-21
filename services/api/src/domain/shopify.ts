/**
 * Shopify discount-code builders — pure functions.
 * The API creates a single-use, customer-agnostic code per redemption via the Admin GraphQL API.
 */
import { randomInt } from 'node:crypto';
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
