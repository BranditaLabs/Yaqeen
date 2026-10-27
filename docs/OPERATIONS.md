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

| Signal | Where | What |
| --- | --- | --- |
| Logs | stdout (pino JSON) | every response carries `x-request-id` (honoured from the load balancer); tokens, ID tokens, passwords and TOTP codes redacted |
| Errors | **Sentry** — projects `yaqeen-api`, `yaqeen-admin`, `yaqeen-app` | API 5xx + unhandled rejections (route template + request id), cron jobs as **cron monitors** (missed/failed runs alert), admin server + browser errors, app crashes (Dart + native). Release = commit SHA (API/admin) or `yaqeen@version+build` (app); deploys are marked by the pipeline. Set `SENTRY_DSN` (API secret), `ADMIN_SENTRY_DSN` / `APP_SENTRY_DSN` (CI variables). Scrubbing: docs/SECURITY_PRIVACY.md. |
| Metrics | **Prometheus** scrape of `:9100/metrics` (`METRICS_PORT`, never through the ingress) | `yaqeen_http_request_duration_seconds{method,route,status}`, `yaqeen_cache_lookups_total{namespace,result}`, `yaqeen_pg_pool_{total,idle,waiting}`, `yaqeen_external_calls_total{service,outcome}`, `yaqeen_product_events_total{event}`, Node defaults (`yaqeen_*`) |
| Dashboards | **Grafana** — `deploy/k8s/monitoring/dashboards/yaqeen-api.json` (sidecar-loaded ConfigMap) | rate, errors, latency, slowest routes, cache, pool, event loop, memory, probes |
| Alerts | `deploy/k8s/monitoring/alerts.yaml` (PrometheusRule) | **page**: 5xx > 1 % 5 min · p99 > 1 s 10 min · Postgres pool waiting · HPA at max 15 min · probe down 3 min. **ticket**: load shedding · cache miss storm · Shopify failing · pod restarts · job failed · TLS < 14 days |
| Uptime | blackbox `Probe` (in cluster, every minute) + `.github/workflows/synthetics.yml` (outside, every 10 min) | `/health`, `/ready`, `/v1/config`, Hijri, card 404 page, `/get-app`, admin login. External failures open one `outage` issue per environment and close it on recovery; run the same checks by hand: `API_URL=… ADMIN_URL=… bash tools/synthetics/check.sh` |
| Product | admin «التحليلات» (aggregates, counts < 20 withheld) + PostHog EU (`POSTHOG_KEY`) | consented `PRODUCT_EVENTS` only — docs/ANALYTICS_EVENTS.md |

- **SLOs**: availability 99.9 % monthly; p99 < 300 ms for cached reads and < 800 ms for personal reads;
  redeem success (excluding user errors) ≥ 99 %.
- Monitoring needs kube-prometheus-stack (Prometheus Operator + Grafana) and
  prometheus-blackbox-exporter in the `monitoring` namespace: `kubectl apply -k deploy/k8s/monitoring`.

## Delivery pipeline

```
PR ──► CI (typecheck, tests + Postgres, migration drift, admin build, Flutter analyze/test,
       APK + emulator smoke, iOS build, kustomize render, image build)
main ─► Deploy: build → Trivy scan → push ghcr.io/branditalabs/yaqeen-{api,admin}:sha-<12> ─► staging (auto)
v1.2.3 tag ─► Deploy: same images ─► production (after the environment's reviewers approve)
mobile-v1.2.3 tag ─► Release mobile: signed AAB → Play (internal) + IPA → TestFlight, symbols → Sentry
```

Each environment rollout (`tools/deploy/deploy.sh <env> <tag>`, also runnable from a laptop):
1. renders `deploy/k8s/overlays/<env>` with both images pinned to the commit;
2. replaces and waits for the `yaqeen-migrate` Job — **a failed migration stops the deploy before any pod changes**;
3. applies everything and waits for both rollouts (`maxUnavailable: 0`);
4. runs the synthetic checks against the environment;
5. a failed rollout or check runs `kubectl rollout undo` on both Deployments and fails the run;
6. marks the Sentry release + deploy.

**Rollback** any time: Actions › Deploy › Run workflow › `rollback` (or `tools/deploy/deploy.sh production --rollback`).
**Re-deploy an older commit**: Run workflow › `deploy` with that `sha` (its images are already in GHCR).

### One-time setup

| Where | Name | Value |
| --- | --- | --- |
| Settings › Environments | `staging`, `production` | create both; on `production` add **required reviewers** (the approval gate) and restrict to `v*` tags |
| Environment secret (each) | `KUBE_CONFIG` | base64 kubeconfig of a deployer ServiceAccount bound to that namespace only (`edit` role) |
| Repository variables | `DEPLOY_ENABLED` | `true` once the clusters exist (until then images are built and scanned, nothing deploys) |
| | `STAGING_API_URL`, `STAGING_ADMIN_URL`, `PROD_API_URL`, `PROD_ADMIN_URL` | public URLs (smoke checks + synthetics) |
| | `SENTRY_ORG`, `ADMIN_SENTRY_DSN`, `APP_SENTRY_DSN` | Sentry organisation and the admin/app project DSNs (DSNs are not secrets) |
| Repository secret | `SENTRY_AUTH_TOKEN` | Sentry internal integration token (releases, source maps, app symbols) |
| Cluster secret `yaqeen-api-secrets` | `SENTRY_DSN`, `POSTHOG_KEY` | API project DSN; PostHog EU project key (optional) |
| | `ADMIN_SECRETS_KEY` | **required in production** — `openssl rand -base64 32`; seals admin 2FA secrets. Back it up: losing it means every admin re-enrols 2FA |
| | `SHOPIFY_WEBHOOK_SECRET` | signing secret of the shop's `orders/paid` webhook → `<api>/webhooks/shopify/orders-paid` (marks reward codes used) |
| ConfigMap / env | `SUPPORT_EMAIL` | shown on the website's help, privacy and deletion pages |
| Packages | GHCR | the cluster pulls `ghcr.io/branditalabs/*`: make the packages public or add an image pull secret |

Namespaces: `yaqeen-staging` (1 replica, HPA 1–4, campaigns suspended, 20 % traces) and `yaqeen`
(production, base manifests). Dependabot opens grouped weekly PRs for npm, pub, Actions and base images.

## Runbooks

| Symptom | Do |
| --- | --- |
| Latency climbing, CPU high | Confirm HPA is scaling (`kubectl -n yaqeen get hpa`); if at max, raise `maxReplicas` and check Postgres. |
| `503` from load shedding | Expected briefly during a spike; sustained → scale up and check for a slow query (`pg_stat_statements`). The app retries with backoff. |
| Postgres connections exhausted | Lower `PG_POOL_MAX` or add PgBouncer; look for long transactions. |
| Redis down | Service degrades gracefully; restore Redis. Expect higher DB read load meanwhile. |
| Shopify failing | Redemptions refund automatically (`shopify_unavailable`, points not deducted). Check the token/scopes on the dashboard pill. |
| Bad deploy | Actions › Deploy › Run workflow › `rollback` (or `tools/deploy/deploy.sh production --rollback`); migrations are backwards compatible. |
| Error spike after a deploy | Sentry › Releases › compare the new release with the previous one; roll back first, investigate after. |
| `outage` issue opened | Synthetics failed from outside: check the probe dashboard (in-cluster view) to tell a cluster outage from an ingress/DNS/TLS one. |
| Need to pause a feature | Dashboard → الإعدادات → turn the flag off (apps pick it up within the config cache window), or maintenance mode for a full stop — Quran, prayer and azkar keep working offline. |

## Release checklist (ops)

- [ ] Secrets present in `yaqeen-api-secrets`; `NODE_ENV=production` refuses dev JWT secrets.
- [ ] `yaqeen-migrate` Job succeeded for the new image.
- [ ] Load test on staging within budget.
- [ ] HPA `minReplicas` raised ahead of a known peak.
- [ ] Dashboard Shopify pill shows «متصل» with `write_discounts`.
- [ ] Firebase service account set (pushes), AlAdhan reachable from the cluster (Hijri).
- [ ] Sentry DSNs set (API secret, admin/app variables); alert routes for `page` / `ticket` configured in Alertmanager.
- [ ] Staging deploy green and smoke checks passing before tagging `v*` for production.
