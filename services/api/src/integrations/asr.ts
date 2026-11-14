/**
 * Client of the internal ASR service (services/asr): `POST {ASR_URL}/verify` with the raw .m4a and the
 * shared secret in `X-ASR-Token`. The service is self-hosted in our own Azure region with internal
 * ingress only; it stores and logs nothing. No user id or any other personal data is sent — only the
 * audio bytes. Failures are counted and surfaced as `AsrUnavailable` (the caller retries with backoff);
 * the two definite answers are `AsrUndecodable` (422) and `AsrTooLong` (413 `too_long`: the decoded audio
 * is longer than the service's 31 s) — final, never retried.
 */
import { AsrVerifyResponse } from '@yaqeen/contracts';
import { externalCalls } from '../lib/metrics.js';

export class AsrUnavailable extends Error {
  constructor(readonly detail: string) {
    super(`asr: ${detail}`);
    this.name = 'AsrUnavailable';
  }
}

/** The service could not decode the audio (HTTP 422) — the recording is rejected as `unclear`. */
export class AsrUndecodable extends Error {
  constructor() {
    super('asr: undecodable audio');
    this.name = 'AsrUndecodable';
  }
}

/**
 * The service decoded the audio and it is longer than it accepts (HTTP 413 `too_long`): the file's own
 * length fields understated it — the recording is rejected as `too_long`.
 */
export class AsrTooLong extends Error {
  constructor() {
    super('asr: audio too long');
    this.name = 'AsrTooLong';
  }
}

export interface AsrClient {
  verify(audio: Buffer): Promise<AsrVerifyResponse>;
}

export class HttpAsrClient implements AsrClient {
  constructor(
    private readonly url: string,
    private readonly token: string,
    private readonly timeoutMs: number,
  ) {}

  async verify(audio: Buffer): Promise<AsrVerifyResponse> {
    let res: Response;
    try {
      res = await fetch(`${this.url.replace(/\/$/, '')}/verify`, {
        method: 'POST',
        headers: { 'content-type': 'audio/mp4', 'x-asr-token': this.token },
        body: new Uint8Array(audio),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (err) {
      externalCalls.inc({ service: 'asr', outcome: 'error' });
      throw new AsrUnavailable(err instanceof Error ? err.name : 'network');
    }
    if (res.status === 422) {
      externalCalls.inc({ service: 'asr', outcome: 'ok' });
      throw new AsrUndecodable();
    }
    if (res.status === 413) {
      const body = (await res.json().catch(() => null)) as { error?: { code?: string } } | null;
      if (body?.error?.code === 'too_long') {
        externalCalls.inc({ service: 'asr', outcome: 'ok' });
        throw new AsrTooLong();
      }
    }
    if (!res.ok) {
      externalCalls.inc({ service: 'asr', outcome: 'error' });
      throw new AsrUnavailable(`status ${res.status}`);
    }
    const parsed = AsrVerifyResponse.safeParse(await res.json().catch(() => null));
    if (!parsed.success) {
      externalCalls.inc({ service: 'asr', outcome: 'error' });
      throw new AsrUnavailable('bad response');
    }
    externalCalls.inc({ service: 'asr', outcome: 'ok' });
    return parsed.data;
  }
}

/** Null when `ASR_URL` is unset: shared recordings then go straight to the review queue. */
export function asrFromEnv(env: { ASR_URL: string; ASR_TOKEN: string; ASR_TIMEOUT_MS: number }): AsrClient | null {
  return env.ASR_URL ? new HttpAsrClient(env.ASR_URL, env.ASR_TOKEN, env.ASR_TIMEOUT_MS) : null;
}
