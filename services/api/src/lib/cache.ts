/**
 * Read-through cache for hot public endpoints (config, content, calendar, catalogues).
 *
 *  L1  in-process LRU, a few seconds — absorbs bursts on one instance without a network hop.
 *  L2  Redis, minutes — shared by every instance; survives restarts and scale-outs.
 *  Single-flight: concurrent misses for one key share one computation (no stampede on a cold key
 *  when traffic spikes, e.g. right after Maghrib or on Friday mornings).
 *
 * Invalidation: each namespace has a version number in Redis; admin writes call `bumpNamespace`,
 * which changes every key in it at once on all instances (L1 copies age out within L1_TTL_MS).
 * Only non-personal data may be cached here — never anything keyed by user.
 */
import { cacheLookups } from './metrics.js';
import { createHash } from 'node:crypto';
import type { Redis } from 'ioredis';

export type CacheNamespace = 'config' | 'content' | 'calendar' | 'catalogue' | 'profile';

const L1_TTL_MS = 5_000;
const L1_MAX = 500;

interface Entry {
  value: string;
  expires: number;
}

export class ResponseCache {
  private readonly l1 = new Map<string, Entry>();
  private readonly inflight = new Map<string, Promise<string>>();
  private readonly localVersions = new Map<CacheNamespace, number>();
  hits = 0;
  misses = 0;

  constructor(
    private readonly redis: Redis | null,
    private readonly now: () => number = Date.now,
  ) {}

  private async version(ns: CacheNamespace): Promise<string> {
    if (!this.redis) return String(this.localVersions.get(ns) ?? 0);
    try {
      return (await this.redis.get(`cache:ver:${ns}`)) ?? '0';
    } catch {
      return 'x'; // Redis down: still serve, just not shared
    }
  }

  /** JSON string for `key`, computing it with `load` on a miss. */
  async getJson<T>(ns: CacheNamespace, key: string, ttlSec: number, load: () => Promise<T>): Promise<string> {
    const full = `cache:${ns}:${await this.version(ns)}:${key}`;
    const hit = this.l1.get(full);
    if (hit && hit.expires > this.now()) {
      this.hits++;
      cacheLookups.inc({ namespace: ns, result: 'l1' });
      return hit.value;
    }
    const pending = this.inflight.get(full);
    if (pending) return pending;

    const work = (async () => {
      let value: string | null = null;
      try {
        value = (await this.redis?.get(full)) ?? null;
      } catch {
        value = null;
      }
      if (value === null) {
        this.misses++;
        cacheLookups.inc({ namespace: ns, result: 'miss' });
        value = JSON.stringify(await load());
        try {
          await this.redis?.set(full, value, 'EX', ttlSec);
        } catch {
          // best effort
        }
      } else {
        this.hits++;
        cacheLookups.inc({ namespace: ns, result: 'l2' });
      }
      this.remember(full, value, Math.min(L1_TTL_MS, ttlSec * 1000));
      return value;
    })().finally(() => this.inflight.delete(full));
    this.inflight.set(full, work);
    return work;
  }

  private remember(key: string, value: string, ttlMs: number) {
    if (this.l1.size >= L1_MAX) this.l1.delete(this.l1.keys().next().value!);
    this.l1.set(key, { value, expires: this.now() + ttlMs });
  }

  /** Invalidate a whole namespace on every instance. */
  async bumpNamespace(ns: CacheNamespace): Promise<void> {
    this.localVersions.set(ns, (this.localVersions.get(ns) ?? 0) + 1);
    for (const k of [...this.l1.keys()]) if (k.startsWith(`cache:${ns}:`)) this.l1.delete(k);
    try {
      await this.redis?.incr(`cache:ver:${ns}`);
    } catch {
      // next TTL expiry heals it
    }
  }
}

/** Weak ETag of a JSON body. */
/** Send a cached JSON string with ETag + Cache-Control; answers 304 when the client has it. */
export function sendCachedJson(
  req: { headers: Record<string, string | string[] | undefined> },
  reply: { header: (k: string, v: string) => unknown; code: (n: number) => { send: (b?: string) => unknown }; type: (t: string) => unknown },
  json: string,
  maxAgeSec: number,
) {
  const tag = etagOf(json);
  reply.header('ETag', tag);
  reply.header('Cache-Control', `public, max-age=${maxAgeSec}, stale-while-revalidate=${maxAgeSec * 2}`);
  if (req.headers['if-none-match'] === tag) return reply.code(304).send();
  reply.type('application/json; charset=utf-8');
  return reply.code(200).send(json);
}

export const etagOf = (json: string) => `W/"${createHash('sha1').update(json).digest('base64url').slice(0, 22)}"`;
