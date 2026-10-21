import { type DiscountRequest } from '../domain/shopify.js';
import { AppError } from '../lib/errors.js';

export interface ShopifyConfig {
  shopDomain: string;
  adminToken: string;
  apiVersion: string;
}

export class ShopifyClient {
  constructor(private readonly cfg: ShopifyConfig) {}

  get configured(): boolean {
    return Boolean(this.cfg.shopDomain && this.cfg.adminToken);
  }

  /** Create a discount code; returns the Shopify discount node id. */
  async createDiscount(req: DiscountRequest): Promise<string> {
    if (!this.configured) throw new AppError(503, 'shopify_not_configured');
    const res = await fetch(`https://${this.cfg.shopDomain}/admin/api/${this.cfg.apiVersion}/graphql.json`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': this.cfg.adminToken },
      body: JSON.stringify({ query: req.query, variables: req.variables }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new AppError(502, 'shopify_upstream', `Shopify ${res.status}`);
    const body = (await res.json()) as {
      data?: Record<string, { codeDiscountNode: { id: string } | null; userErrors: { message: string }[] }>;
      errors?: { message: string }[];
    };
    const result = body.data?.[req.resultKey];
    if (body.errors?.length || !result || result.userErrors.length || !result.codeDiscountNode) {
      const msg = [...(body.errors ?? []), ...(result?.userErrors ?? [])].map((e) => e.message).join('; ');
      throw new AppError(502, 'shopify_rejected', msg || 'Discount was not created');
    }
    return result.codeDiscountNode.id;
  }
}
