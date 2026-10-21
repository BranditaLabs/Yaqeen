/**
 * Load test — a realistic app mix against a running API:
 *   pnpm --filter @yaqeen/api load            (API_URL defaults to http://localhost:4000)
 *   LOAD_CONNECTIONS=400 LOAD_SECONDS=60 pnpm --filter @yaqeen/api load
 *
 * Mix per virtual user (what an app open costs): config (cached) · Hijri month (cached) ·
 * content sync (cached) · challenge summary (authenticated, DB). Guest sessions are created first
 * so authenticated calls hit real rows. Fails (exit 1) if p99 or the error rate exceed the budget.
 */
import autocannon from 'autocannon';

const API = process.env.API_URL ?? 'http://localhost:4000';
const CONNECTIONS = Number(process.env.LOAD_CONNECTIONS ?? 100);
const SECONDS = Number(process.env.LOAD_SECONDS ?? 20);
const USERS = Number(process.env.LOAD_USERS ?? 50);
const P99_BUDGET_MS = Number(process.env.LOAD_P99_MS ?? 500);
const MAX_ERROR_RATE = Number(process.env.LOAD_MAX_ERROR_RATE ?? 0.01);

async function guestTokens(n: number): Promise<string[]> {
  const tokens: string[] = [];
  for (let i = 0; i < n; i++) {
    const res = await fetch(`${API}/v1/auth/sign-in`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-forwarded-for': `10.9.${i >> 8}.${i & 255}` },
      body: JSON.stringify({ provider: 'guest' }),
    });
    if (res.ok) tokens.push(((await res.json()) as { accessToken: string }).accessToken);
  }
  if (tokens.length === 0) throw new Error('could not create guest sessions (rate limit? API down?)');
  return tokens;
}

const tokens = await guestTokens(USERS);
const now = new Date();
let i = 0;
const result = await autocannon({
  url: API,
  connections: CONNECTIONS,
  duration: SECONDS,
  requests: [
    { method: 'GET', path: '/v1/config' },
    { method: 'GET', path: `/v1/calendar/hijri?year=${now.getFullYear()}&month=${now.getMonth() + 1}` },
    { method: 'GET', path: '/v1/content?type=zikr' },
    {
      method: 'GET',
      path: '/v1/challenge/summary',
      setupRequest: (req) => ({ ...req, headers: { ...req.headers, authorization: `Bearer ${tokens[i++ % tokens.length]}` } }),
    },
  ],
});

const total = result.requests.total || 1;
const errors = result.errors + result.timeouts + result.non2xx;
const errorRate = errors / total;
console.log(autocannon.printResult(result));
console.log(JSON.stringify({ rps: result.requests.average, p50: result.latency.p50, p99: result.latency.p99, errors, errorRate: Number(errorRate.toFixed(4)) }));
if (result.latency.p99 > P99_BUDGET_MS || errorRate > MAX_ERROR_RATE) {
  console.error(`over budget: p99 ${result.latency.p99} ms (≤ ${P99_BUDGET_MS}), errors ${(errorRate * 100).toFixed(2)}% (≤ ${MAX_ERROR_RATE * 100}%)`);
  process.exit(1);
}
