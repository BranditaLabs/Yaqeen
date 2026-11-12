/**
 * Quran.com / Quran Foundation Content API v4 client (spec §10 — reciters' audio + timings, tafsir).
 *
 * Server only — the app never sees QF credentials. With `QF_CLIENT_ID` + `QF_CLIENT_SECRET` it uses
 * OAuth2 client_credentials (`scope=content`) against `{auth}/oauth2/token`, caches the token until
 * shortly before `expires_in`, and on a 401 drops it, fetches a new one and retries once; requests
 * carry `x-auth-token` + `x-client-id`. Without credentials it falls back to the legacy
 * unauthenticated `https://api.quran.com/api/v4` (same paths and shapes, verified 2026-10-31) unless
 * `QF_PUBLIC_BASE_URL` is empty, in which case every call fails with `QfUnavailable`.
 *
 * Each attempt has a timeout; network errors, timeouts, 429 and 5xx are retried once. Failures are
 * counted (`yaqeen_external_calls_total{service="quran_foundation"}`) and reported to Sentry with
 * the path and status only (no token, no secret). No user data is ever sent.
 */
import { externalCalls } from '../lib/metrics.js';
import { captureError } from '../lib/observability.js';

export const QF_HOSTS = {
  production: { auth: 'https://oauth2.quran.foundation', api: 'https://apis.quran.foundation/content/api/v4' },
  prelive: { auth: 'https://prelive-oauth2.quran.foundation', api: 'https://apis-prelive.quran.foundation/content/api/v4' },
} as const;

const TIMEOUT_MS = 15_000;
/** Renew this long before the token's stated expiry. */
const TOKEN_SLACK_MS = 60_000;

/** Upstream unreachable / not configured / erroring — routes answer 503 `content_unavailable`. */
export class QfUnavailable extends Error {
  constructor(readonly detail: string) {
    super(`quran_foundation: ${detail}`);
    this.name = 'QfUnavailable';
  }
}

/** Upstream says the resource does not exist (404). */
export class QfNotFound extends Error {
  constructor(path: string) {
    super(`quran_foundation: not found ${path}`);
    this.name = 'QfNotFound';
  }
}

export interface QfOptions {
  clientId: string;
  clientSecret: string;
  env: 'production' | 'prelive';
  /** Legacy unauthenticated base; '' disables the fallback. */
  publicBaseUrl: string;
  fetchImpl?: typeof fetch;
  now?: () => number;
}

export type QfMode = 'oauth' | 'public' | 'off';

export interface QfChapterAudio {
  audio_file: {
    id: number;
    chapter_id: number;
    file_size: number | null;
    format: string;
    audio_url: string;
    timestamps?: { verse_key: string; timestamp_from: number; timestamp_to: number; duration?: number }[];
  };
}

export interface QfTafsirRow {
  verse_key: string;
  text: string;
}

const retryable = (status: number) => status === 429 || status >= 500;

export class QuranFoundationClient {
  private token: { value: string; expires: number } | null = null;
  private tokenInflight: Promise<string> | null = null;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;

  constructor(private readonly opts: QfOptions) {
    this.fetchImpl = opts.fetchImpl ?? fetch;
    this.now = opts.now ?? Date.now;
  }

  get mode(): QfMode {
    if (this.opts.clientId && this.opts.clientSecret) return 'oauth';
    return this.opts.publicBaseUrl ? 'public' : 'off';
  }

  private get base(): string {
    return this.mode === 'oauth' ? QF_HOSTS[this.opts.env].api : this.opts.publicBaseUrl.replace(/\/+$/, '');
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expires > this.now()) return this.token.value;
    this.tokenInflight ??= this.requestToken().finally(() => {
      this.tokenInflight = null;
    });
    return this.tokenInflight;
  }

  private async requestToken(): Promise<string> {
    const basic = Buffer.from(`${this.opts.clientId}:${this.opts.clientSecret}`).toString('base64');
    let res: Response;
    try {
      res = await this.fetchImpl(`${QF_HOSTS[this.opts.env].auth}/oauth2/token`, {
        method: 'POST',
        headers: { authorization: `Basic ${basic}`, 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
        body: 'grant_type=client_credentials&scope=content',
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch {
      throw this.fail('token network');
    }
    if (!res.ok) throw this.fail(`token ${res.status}`);
    const body = (await res.json().catch(() => null)) as { access_token?: unknown; expires_in?: unknown } | null;
    if (typeof body?.access_token !== 'string') throw this.fail('token malformed');
    const ttlMs = (typeof body.expires_in === 'number' ? body.expires_in : 3600) * 1000;
    this.token = { value: body.access_token, expires: this.now() + Math.max(0, ttlMs - TOKEN_SLACK_MS) };
    return body.access_token;
  }

  private fail(detail: string): QfUnavailable {
    externalCalls.inc({ service: 'quran_foundation', outcome: 'failed' });
    const err = new QfUnavailable(detail);
    captureError(err, { route: 'integration:quran_foundation' });
    return err;
  }

  /** GET `path` (e.g. `/chapter_recitations/7/1`) → parsed JSON. */
  async get<T>(path: string, query: Record<string, string | number | boolean> = {}): Promise<T> {
    if (this.mode === 'off') throw new QfUnavailable('not configured');
    const qs = new URLSearchParams(Object.entries(query).map(([k, v]): [string, string] => [k, String(v)])).toString();
    const url = `${this.base}${path}${qs ? `?${qs}` : ''}`;
    let reauthed = false;
    let detail = 'error';
    for (let attempt = 0; attempt < 2; attempt++) {
      const headers: Record<string, string> = { accept: 'application/json' };
      if (this.mode === 'oauth') {
        headers['x-auth-token'] = await this.accessToken();
        headers['x-client-id'] = this.opts.clientId;
      }
      let res: Response;
      try {
        res = await this.fetchImpl(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) });
      } catch (e) {
        detail = e instanceof Error && e.name === 'TimeoutError' ? 'timeout' : 'network';
        continue;
      }
      if (res.ok) {
        const json = (await res.json().catch(() => undefined)) as T | undefined;
        if (json === undefined) {
          detail = 'malformed';
          continue;
        }
        externalCalls.inc({ service: 'quran_foundation', outcome: 'ok' });
        return json;
      }
      if (res.status === 401 && this.mode === 'oauth' && !reauthed) {
        // Token expired or revoked: drop it, get a new one, retry once (does not use the retry slot).
        reauthed = true;
        this.token = null;
        attempt--;
        continue;
      }
      if (res.status === 404) {
        externalCalls.inc({ service: 'quran_foundation', outcome: 'not_found' });
        throw new QfNotFound(path);
      }
      detail = `${res.status} ${path}`;
      if (!retryable(res.status)) break;
    }
    throw this.fail(detail);
  }

  /** One surah of one chapter reciter, with verse timestamps. */
  chapterAudio(qfReciterId: number, surah: number): Promise<QfChapterAudio> {
    return this.get<QfChapterAudio>(`/chapter_recitations/${qfReciterId}/${surah}`, { segments: true });
  }

  /** Every ayah's tafsir row in a surah (one page; the largest surah has 286 ayat). */
  async tafsirSurah(qfTafsirId: number, surah: number): Promise<QfTafsirRow[]> {
    const res = await this.get<{ tafsirs: QfTafsirRow[] }>(`/tafsirs/${qfTafsirId}/by_chapter/${surah}`, { per_page: 300, page: 1 });
    return res.tafsirs ?? [];
  }

}

export function quranFoundationFromEnv(env: { QF_CLIENT_ID: string; QF_CLIENT_SECRET: string; QF_ENV: 'production' | 'prelive'; QF_PUBLIC_BASE_URL: string }) {
  return new QuranFoundationClient({
    clientId: env.QF_CLIENT_ID,
    clientSecret: env.QF_CLIENT_SECRET,
    env: env.QF_ENV,
    publicBaseUrl: env.QF_PUBLIC_BASE_URL,
  });
}
