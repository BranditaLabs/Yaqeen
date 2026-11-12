/**
 * Ad-platform conversion senders (Meta Conversions API, GA4 Measurement Protocol, TikTok Events API).
 * Each is on only when its credentials are set. Payloads come from `domain/conversions.ts` and hold
 * no personal or worship data. Credentials travel in headers / body where the platform allows it;
 * GA4 requires them in the query, so URLs are never logged or put in errors.
 */
import type { Env } from '../config/env.js';
import { type ConversionPlatform, ga4Payload, metaPayload, type Purchase, tiktokPayload } from '../domain/conversions.js';
import { externalCalls } from '../lib/metrics.js';

export const META_GRAPH_VERSION = 'v21.0';
const TIMEOUT_MS = 5_000;

/** A failed send; the message names the platform and status only (no URL, token or payload). */
export class ConversionSendError extends Error {
  constructor(
    readonly platform: ConversionPlatform,
    readonly detail: string,
  ) {
    super(`conversions: ${platform} ${detail}`);
    this.name = 'ConversionSendError';
  }
}

interface Request {
  url: string;
  headers: Record<string, string>;
  body: unknown;
  /** TikTok answers 200 with a non-zero `code` on errors. */
  check?: (json: unknown) => string | null;
}

function requestFor(env: Env, platform: ConversionPlatform, p: Purchase): Request {
  const json = { 'content-type': 'application/json' };
  switch (platform) {
    case 'meta':
      return {
        url: `https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(env.META_PIXEL_ID)}/events`,
        headers: { ...json, Authorization: `Bearer ${env.META_CAPI_TOKEN}` },
        body: metaPayload(p, { eventSourceUrl: env.STORE_URL, testEventCode: env.META_TEST_EVENT_CODE || undefined }),
      };
    case 'ga4':
      return {
        url: `https://www.google-analytics.com/mp/collect?measurement_id=${encodeURIComponent(env.GA4_MEASUREMENT_ID)}&api_secret=${encodeURIComponent(env.GA4_API_SECRET)}`,
        headers: json,
        body: ga4Payload(p),
      };
    case 'tiktok':
      return {
        url: 'https://business-api.tiktok.com/open_api/v1.3/event/track/',
        headers: { ...json, 'Access-Token': env.TIKTOK_ACCESS_TOKEN },
        body: tiktokPayload(p, { pixelId: env.TIKTOK_PIXEL_ID, pageUrl: env.STORE_URL, testEventCode: env.TIKTOK_TEST_EVENT_CODE || undefined }),
        check: (j) => {
          const code = (j as { code?: unknown } | null)?.code;
          return code === 0 || code === undefined ? null : `code ${String(code)}`;
        },
      };
  }
}

const retryable = (status: number) => status === 429 || status >= 500;

/**
 * Sends one purchase to one platform: a timeout per attempt and at most one retry (network error,
 * timeout, 429 or 5xx). Throws `ConversionSendError` when it didn't go through.
 */
export async function sendConversion(env: Env, platform: ConversionPlatform, p: Purchase, fetchImpl: typeof fetch = fetch): Promise<void> {
  const req = requestFor(env, platform, p);
  let detail = 'error';
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetchImpl(req.url, {
        method: 'POST',
        headers: req.headers,
        body: JSON.stringify(req.body),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (res.ok) {
        const problem = req.check ? req.check(await res.json().catch(() => null)) : null;
        if (!problem) {
          externalCalls.inc({ service: platform, outcome: 'ok' });
          return;
        }
        detail = problem;
        break; // a rejected payload won't pass on retry
      }
      detail = `HTTP ${res.status}`;
      if (!retryable(res.status)) break;
    } catch (err) {
      detail = err instanceof Error && err.name === 'TimeoutError' ? 'timeout' : 'network';
    }
  }
  externalCalls.inc({ service: platform, outcome: 'error' });
  throw new ConversionSendError(platform, detail);
}
