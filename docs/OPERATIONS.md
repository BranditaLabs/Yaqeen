# Operations — running Yaqeen in production

How the API, dashboard and jobs are deployed, how they behave under changing traffic, and what to
do when something goes wrong. Manifests: `deploy/k8s` (kustomize). Images: `services/api/Dockerfile`,
`apps/admin/Dockerfile` (built by CI from the repo root).

## Traffic shape

Yaqeen's load is spiky and predictable: app opens cluster after Fajr, around Maghrib, on Friday
morning (Kahf) and in Ramadan (iftar / suhoor). Campaign pushes add short bursts. The design
keeps most of that load off the servers:

| Where | What keeps it cheap |
| --- | --- |
| App | Quran, prayer times, Qibla, azkar, duas, hifz and reminders are fully on-device. Remote config is cached 1 h. Challenge ticks go through the Outbox (one request each, replayed later if offline). Failed syncs back off exponentially with full jitter (30 s → 15 min), so phones never retry in lockstep after an outage. |
| API — public reads | `/v1/config`, `/v1/content`, `/v1/daily-task`, `/v1/calendar/hijri`, `/v1/content/reciters`, `/v1/content/packs` are served from a two-level cache (5 s in-process + Redis), single-flighted (one DB query per key even under a stampede), with `ETag` → `304` and `Cache-Control: stale-while-revalidate`. Admin writes invalidate the affected namespace on every instance immediately. |
| API — personal | Challenge, rewards and profile hit Postgres through indexed queries; the redeem path is serialised per user with an advisory lock. |
| Jobs | Dispatcher and purge take a Postgres advisory lock — overlapping runs skip. |

## Capacity (measured)

`pnpm --filter @yaqeen/api load` replays an app open (config · Hijri month · content sync ·
authenticated challenge summary). One API instance (Node 22, 1 process) against local
Postgres + Redis:

| Concurrent connections | Throughput | p50 | p99 | Errors |
| --- | --- | --- | --- | --- |
| 100 | ~1,850 req/s | 27 ms | 210 ms | 0 |
| 600 (spike) | ~2,040 req/s | 78 ms | 1.2 s | 0 |

Rule of thumb: **one pod ≈ 2k req/s** at p99 < 250 ms before it saturates; beyond that latency grows
while throughput plateaus, and `@fastify/under-pressure` sheds load with `503 Retry-After: 10`
once event-loop delay exceeds `MAX_EVENT_LOOP_DELAY_MS`. Re-measure on production hardware
before a launch campaign: `API_URL=https://staging… LOAD_CONNECTIONS=400 pnpm --filter @yaqeen/api load`
(the script exits non-zero if p99 or the error rate exceed `LOAD_P99_MS` / `LOAD_MAX_ERROR_RATE`).

## Scaling

- **API pods** are stateless. HPA: 3 → 30 replicas at 60 % CPU; scale-up doubles every 30 s with no
  stabilisation window, scale-down is gentle (20 %/min after 5 min). A PodDisruptionBudget keeps ≥ 2
  pods through node drains; pods spread across zones.
- **Before a known peak** (Ramadan start, a big campaign) raise `minReplicas` the day before rather
  than relying on reactive scaling.
- **Deploys** are rolling with `maxUnavailable: 0`. On SIGTERM a pod fails `/ready` immediately, waits
  `SHUTDOWN_GRACE_MS` for the load balancer to drop it, finishes in-flight requests and exits —
  `terminationGracePeriodSeconds` must exceed that grace plus the 30 s request timeout.
- **Keep-alive** is 65 s, longer than typical load-balancer idle timeouts (60 s), so the LB never
  reuses a socket the API just closed (avoids sporadic 502s under load).

## Database

- Each pod opens at most `PG_POOL_MAX` connections (default 20) with a server-side
  `statement_timeout` (`PG_STATEMENT_TIMEOUT_MS`, 10 s) and a 5 s connect timeout.
  **Pods × pool must stay below Postgres `max_connections`.** At the HPA maximum (30 × 20 = 600) put
  **PgBouncer in transaction mode** in front of Postgres (the API uses no session features; advisory
  locks in jobs are taken by the jobs, which can connect directly).
- Hot paths are indexed (see migrations `0003_scale_indexes`): refresh tokens by user, consents by
  `(kind, granted)` for campaign audiences, redemptions by `(reward, created_at)` for monthly caps,
  campaigns by `(status, scheduled_at)` for the dispatcher. Points balances are `SUM` over
  `points_ledger(user_id, ref_key)` — append-only, never updated.
- Managed Postgres 16 with PITR backups; a read replica can take the admin overview queries later.
- Migrations: `node dist/db/migrate.js` (the `yaqeen-migrate` Job) runs before each rollout, guarded by
  an advisory lock. Migrations must be backwards compatible with the previous release (add, backfill,
  then remove in a later release).

## Redis

Used for the shared response cache, cache versions, the AlAdhan month cache and shared rate limits.
It is **not** a source of truth: if Redis is down the API keeps serving (in-process cache only, rate
limits fail open per instance) — degraded, not down. Use a managed Redis 7 with persistence off.

## Rate limits

Global 300 req/min per caller (`RATE_LIMIT_PER_MIN`), keyed by bearer token for signed-in traffic
(many Egyptian users share a carrier-grade NAT IP) and by IP otherwise. Tighter limits: sign-in and
guest-link 10/min/IP, redeem 5/min, admin login 5 per 5 min.

## Observability

- Every response carries `x-request-id` (honoured from the load balancer when present); logs are JSON
  (pino) with tokens, ID tokens, passwords and TOTP codes redacted.
- **SLOs**: availability 99.9 % monthly; p99 < 300 ms for cached reads and < 800 ms for personal reads;
  redeem success (excluding user errors) ≥ 99 %.
- **Alerts**: 5xx rate > 1 % for 5 min · p99 > 1 s for 10 min · any `503` from load shedding · pod
  restarts · Postgres connections > 80 % · Redis unavailable · dispatcher job failed twice ·
  `shopify_unavailable` > 5 in 10 min (the dashboard also shows this).
- Crash and performance monitoring in the app: Firebase Crashlytics (spec §6.21) — no worship data in
  keys or logs.

## Runbooks

| Symptom | Do |
| --- | --- |
| Latency climbing, CPU high | Confirm HPA is scaling (`kubectl -n yaqeen get hpa`); if at max, raise `maxReplicas` and check Postgres. |
| `503` from load shedding | Expected briefly during a spike; sustained → scale up and check for a slow query (`pg_stat_statements`). The app retries with backoff. |
| Postgres connections exhausted | Lower `PG_POOL_MAX` or add PgBouncer; look for long transactions. |
| Redis down | Service degrades gracefully; restore Redis. Expect higher DB read load meanwhile. |
| Shopify failing | Redemptions refund automatically (`shopify_unavailable`, points not deducted). Check the token/scopes on the dashboard pill. |
| Bad deploy | `kubectl -n yaqeen rollout undo deploy/yaqeen-api` (migrations are backwards compatible). |
| Need to pause a feature | Dashboard → الإعدادات → turn the flag off (apps pick it up within the config cache window), or maintenance mode for a full stop — Quran, prayer and azkar keep working offline. |

## Release checklist (ops)

- [ ] Secrets present in `yaqeen-api-secrets`; `NODE_ENV=production` refuses dev JWT secrets.
- [ ] `yaqeen-migrate` Job succeeded for the new image.
- [ ] Load test on staging within budget.
- [ ] HPA `minReplicas` raised ahead of a known peak.
- [ ] Dashboard Shopify pill shows «متصل» with `write_discounts`.
- [ ] Firebase service account set (pushes), AlAdhan reachable from the cluster (Hijri).
