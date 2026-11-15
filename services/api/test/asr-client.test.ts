/**
 * The ASR client's answers: 422 → AsrUndecodable, 413 `too_long` → AsrTooLong (both final), anything
 * else that is not a valid response → AsrUnavailable (retried).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { AsrTooLong, AsrUnavailable, AsrUndecodable, HttpAsrClient } from '../src/integrations/asr.js';

const client = new HttpAsrClient('http://asr.internal', 'token', 1000);
const reply = (status: number, body: unknown) => vi.fn(async () => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } }));

describe('HttpAsrClient', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('maps 413 too_long to the final AsrTooLong', async () => {
    vi.stubGlobal('fetch', reply(413, { error: { code: 'too_long' } }));
    await expect(client.verify(Buffer.from('x'))).rejects.toBeInstanceOf(AsrTooLong);
  });
  it('other 413s (too_large: a size mismatch between the services) stay retryable', async () => {
    vi.stubGlobal('fetch', reply(413, { error: { code: 'too_large' } }));
    await expect(client.verify(Buffer.from('x'))).rejects.toBeInstanceOf(AsrUnavailable);
  });
  it('422 → AsrUndecodable; 5xx → AsrUnavailable; a valid body → the result', async () => {
    vi.stubGlobal('fetch', reply(422, { error: { code: 'undecodable' } }));
    await expect(client.verify(Buffer.from('x'))).rejects.toBeInstanceOf(AsrUndecodable);
    vi.stubGlobal('fetch', reply(503, {}));
    await expect(client.verify(Buffer.from('x'))).rejects.toBeInstanceOf(AsrUnavailable);
    vi.stubGlobal('fetch', reply(200, { durationMs: 1000, speechMs: 800, transcript: 'x', words: [] }));
    await expect(client.verify(Buffer.from('x'))).resolves.toMatchObject({ durationMs: 1000 });
  });
});
