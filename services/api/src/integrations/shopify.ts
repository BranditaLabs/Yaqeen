import { type DiscountRequest } from '../domain/shopify.js';
import { externalCalls } from '../lib/metrics.js';
import { AppError } from '../lib/errors.js';

export interface ShopifyConfig {
  shopDomain: string;
  adminToken: string;
  apiVersion: string;
}

export interface ShopifyShopInfo {
  shopName: string;
  domain: string;
  scopes: string[];
}

export class ShopifyClient {
  constructor(private readonly cfg: ShopifyConfig) {}

  /** Last failure talking to Shopify (shown on the dashboard's connection pill). */
  lastError: { message: string; at: Date } | null = null;

  get configured(): boolean {
    return Boolean(this.cfg.shopDomain && this.cfg.adminToken);
  }

  get domain(): string {
    return this.cfg.shopDomain;
  }

  private async graphql<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
    if (!this.configured) throw new AppError(503, 'shopify_not_configured');
    try {
      const res = await fetch(`https://${this.cfg.shopDomain}/admin/api/${this.cfg.apiVersion}/graphql.json`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': this.cfg.adminToken },
        body: JSON.stringify({ query, variables }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) throw new AppError(502, 'shopify_upstream', `Shopify ${res.status}`);
      const body = (await res.json()) as { data?: T; errors?: { message: string }[] };
      if (body.errors?.length || !body.data) {
        throw new AppError(502, 'shopify_rejected', (body.errors ?? []).map((e) => e.message).join('; ') || 'Empty response');
      }
      externalCalls.inc({ service: 'shopify', outcome: 'ok' });
      return body.data;
    } catch (err) {
      externalCalls.inc({ service: 'shopify', outcome: 'error' });
      this.lastError = { message: err instanceof Error ? err.message : String(err), at: new Date() };
      throw err instanceof AppError ? err : new AppError(502, 'shopify_upstream', this.lastError.message);
    }
  }

  /** Create a discount code; returns the Shopify discount node id. */
  async createDiscount(req: DiscountRequest): Promise<string> {
    const data = await this.graphql<Record<string, { codeDiscountNode: { id: string } | null; userErrors: { message: string }[] }>>(
      req.query,
      req.variables,
    );
    const result = data[req.resultKey];
    if (!result || result.userErrors.length || !result.codeDiscountNode) {
      const msg = (result?.userErrors ?? []).map((e) => e.message).join('; ');
      this.lastError = { message: msg || 'Discount was not created', at: new Date() };
      throw new AppError(502, 'shopify_rejected', this.lastError.message);
    }
    return result.codeDiscountNode.id;
  }

  async shopInfo(): Promise<ShopifyShopInfo> {
    const data = await this.graphql<{
      shop: { name: string; primaryDomain: { host: string } | null; myshopifyDomain: string };
      currentAppInstallation: { accessScopes: { handle: string }[] } | null;
    }>(`{ shop { name myshopifyDomain primaryDomain { host } } currentAppInstallation { accessScopes { handle } } }`);
    return {
      shopName: data.shop.name,
      domain: data.shop.primaryDomain?.host ?? data.shop.myshopifyDomain,
      scopes: (data.currentAppInstallation?.accessScopes ?? []).map((s) => s.handle),
    };
  }

  /** Collections for the reward picker (e.g. the prayer-rug collection). */
  async collections(search?: string): Promise<{ id: string; title: string; productsCount: number | null }[]> {
    const data = await this.graphql<{
      collections: { nodes: { id: string; title: string; productsCount: { count: number } | null }[] };
    }>(
      `query Collections($q: String) { collections(first: 50, query: $q, sortKey: TITLE) { nodes { id title productsCount { count } } } }`,
      { q: search ? `title:*${search.replace(/[^\p{L}\p{N} ]/gu, '')}*` : null },
    );
    return data.collections.nodes.map((c) => ({ id: c.id, title: c.title, productsCount: c.productsCount?.count ?? null }));
  }
}
