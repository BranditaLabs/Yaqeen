import { describe, expect, it } from 'vitest';
import { ResponseCache, etagOf } from '../src/lib/cache.js';

describe('response cache (no Redis)', () => {
  it('serves repeats from memory and shares one load between concurrent misses', async () => {
    let loads = 0;
    const cache = new ResponseCache(null);
    const load = async () => {
      loads++;
      await new Promise((r) => setTimeout(r, 10));
      return { ok: true };
    };
    const [a, b, c] = await Promise.all([1, 2, 3].map(() => cache.getJson('config', 'k', 60, load)));
    expect(loads).toBe(1);
    expect(a).toBe('{"ok":true}');
    expect(b).toBe(a);
    expect(c).toBe(a);
    await cache.getJson('config', 'k', 60, load);
    expect(loads).toBe(1);
  });

  it('expires L1 entries and invalidates a namespace on demand', async () => {
    let t = 0;
    let n = 0;
    const cache = new ResponseCache(null, () => t);
    const load = async () => ++n;
    expect(await cache.getJson('content', 'list', 60, load)).toBe('1');
    t += 6_000; // beyond L1 TTL (no Redis behind it) → reload
    expect(await cache.getJson('content', 'list', 60, load)).toBe('2');
    await cache.bumpNamespace('content');
    expect(await cache.getJson('content', 'list', 60, load)).toBe('3');
    expect(await cache.getJson('config', 'list', 60, load)).toBe('4'); // other namespace unaffected by keys
  });

  it('etags are stable and differ by body', () => {
    expect(etagOf('{"a":1}')).toBe(etagOf('{"a":1}'));
    expect(etagOf('{"a":1}')).not.toBe(etagOf('{"a":2}'));
  });
});
