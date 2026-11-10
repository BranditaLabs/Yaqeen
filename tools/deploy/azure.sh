#!/usr/bin/env bash
# Yaqeen on Azure Container Apps (deploy/azure/main.bicep). Needs `az` signed in and Docker; runs from
# a laptop (Git Bash on Windows works) or CI.
#
#   tools/deploy/azure.sh <staging|production> all        infra → images → apps → migrate → smoke → dns
#   tools/deploy/azure.sh <staging|production> infra      resource group + infrastructure only
#   tools/deploy/azure.sh <staging|production> images     build + push the API/admin images (tag: commit)
#   tools/deploy/azure.sh <staging|production> apps       roll out the images at TAG (default: HEAD)
#   tools/deploy/azure.sh <staging|production> migrate    run the migration job and wait
#   tools/deploy/azure.sh <staging|production> smoke      /health and /ready on the API
#   tools/deploy/azure.sh <staging|production> seed       once: reference data + first super admin
#   tools/deploy/azure.sh <staging|production> dns        print the DNS records to create
#   tools/deploy/azure.sh <staging|production> domains    after DNS resolves: hostnames + managed certs
#
# Secrets are generated on the first run and kept in the environment's Key Vault — never in git, never
# on a command line. Back up the vault's `backup-secrets-key` and `admin-secrets-key`
# (docs/OPERATIONS.md › Azure). Optional integrations: add a vault secret named env-<var-name>, e.g.
# env-shopify-admin-token → SHOPIFY_ADMIN_TOKEN, then run `apps`; non-secret API settings go in
# deploy/azure/<env>.env.json. ADMIN_ALLOWED_CIDRS=1.2.3.4/32,… restricts the admin console.
set -euo pipefail
umask 077
export MSYS_NO_PATHCONV=1 # Git Bash: keep /subscriptions/... ids intact…
# …so paths handed to native Windows tools (git, node, az, docker) are converted explicitly.
native() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

ENVIRONMENT=${1:?environment: staging|production}
CMD=${2:-all}
ROOT=$(native "$(cd "$(dirname "$0")/../.." && pwd)")
RG="rg-yaqeen-$ENVIRONMENT"
LOCATION=${AZURE_LOCATION:-uaenorth}
# Staging runs inside an existing Container Apps environment: the subscription is a Free Trial, which
# allows one environment in total, and Mizan's staging uses it. Yaqeen keeps its own resource group,
# Postgres, registry, vault and identities; only the environment is shared (no VNet there, so no
# Redis: one API replica with in-memory cache). Production gets its own environment (unset this).
case "$ENVIRONMENT" in
  staging) SHARED_ENV=${AZURE_SHARED_ENVIRONMENT_ID-/subscriptions/b6a86f0e-e2a2-4e91-8bcf-5116f3c0159b/resourceGroups/rg-mizan-staging/providers/Microsoft.App/managedEnvironments/cae-mizan-staging} ;;
  *) SHARED_ENV=${AZURE_SHARED_ENVIRONMENT_ID:-} ;;
esac
if [[ -n "$SHARED_ENV" ]]; then
  ENV_RG=$(cut -d/ -f5 <<<"$SHARED_ENV") ENV_NAME=${SHARED_ENV##*/}
else
  ENV_RG=$RG ENV_NAME="cae-yaqeen-$ENVIRONMENT"
fi
case "$ENVIRONMENT" in
  staging) API_HOST=api-staging.yaqin-brand.com ADMIN_HOST=admin-staging.yaqin-brand.com CAMPAIGNS=false ;;
  production) API_HOST=api.yaqin-brand.com ADMIN_HOST=admin.yaqin-brand.com CAMPAIGNS=true ;;
  *) echo "unknown environment $ENVIRONMENT"; exit 2 ;;
esac
TAG=${TAG:-$(git -C "$ROOT" rev-parse --short=12 HEAD)}
WORK=$(native "$(mktemp -d)")
trap 'rm -rf "$WORK"' EXIT

log() { printf '\n== %s\n' "$*"; }
q() { az "$@" --only-show-errors -o tsv; }
die() { echo "error: $*" >&2; exit 1; }

# The environment's vault ('' before the first deploy). A failed lookup is an error, never "no vault":
# treating it as missing would generate new secrets and silently rotate every key.
vault() {
  [[ $(q group exists -n "$RG") == true ]] || return 0
  q keyvault list -g "$RG" --query '[0].name' || die "cannot list Key Vaults in $RG"
}

# A vault secret, or a fresh value from `gen` only when the secret does not exist yet.
secret_or() {
  local name=$1 gen=$2 kv=$3 out
  if [[ -n "$kv" ]]; then
    if out=$(az keyvault secret show --vault-name "$kv" -n "$name" --query value -o tsv --only-show-errors 2>&1); then
      printf '%s' "$out"
      return 0
    fi
    grep -q 'SecretNotFound' <<<"$out" || die "cannot read $name from $kv: $out"
  fi
  eval "$gen"
}

# Writes a vault secret from a private file (values never appear in a process list). Retries while a
# fresh role assignment propagates.
vault_set() {
  local kv=$1 name=$2 value=$3
  printf '%s' "$value" >"$WORK/v"
  for i in 1 2 3 4 5 6; do
    az keyvault secret set --vault-name "$kv" -n "$name" --file "$WORK/v" --encoding utf-8 --only-show-errors -o none && { rm -f "$WORK/v"; return 0; }
    sleep $((i * 10))
  done
  rm -f "$WORK/v"
  return 1
}

deployer() {
  if [[ $(q account show --query user.type) == servicePrincipal ]]; then
    echo "$(q ad sp show --id "$(q account show --query user.name)" --query id) ServicePrincipal"
  else
    echo "$(q ad signed-in-user show --query id) User"
  fi
}

# Hostnames already bound with managed certificates are kept on every redeploy.
domain_mode() {
  local certs hosts
  certs=$(q containerapp env certificate list -g "$ENV_RG" -n "$ENV_NAME" --managed-certificates-only --query "[?starts_with(name, 'cert-') && contains(name, 'yaqin-brand')].name" 2>/dev/null | grep -c . || true)
  hosts=$(q containerapp hostname list -g "$RG" -n yaqeen-api --query 'length(@)' 2>/dev/null || echo 0)
  if [[ "${certs:-0}" -ge 2 ]]; then echo bind; elif [[ "${hosts:-0}" -ge 1 ]]; then echo add; else echo none; fi
}

deploy() { # deploy <deployApps true|false> <domainMode>
  local apps=$1 mode=$2 kv acr settings='{}' extra='[]' storage principal ptype apps_location=$LOCATION
  kv=$(vault)
  [[ -z "$SHARED_ENV" ]] || apps_location=$(q containerapp env show --ids "$SHARED_ENV" --query location | tr -d ' ' | tr 'A-Z' 'a-z')
  read -r principal ptype <<<"$(deployer)"
  [[ -f "$ROOT/deploy/azure/$ENVIRONMENT.env.json" ]] && settings=$(cat "$ROOT/deploy/azure/$ENVIRONMENT.env.json")
  acr=$(q acr list -g "$RG" --query '[0].loginServer' 2>/dev/null || true)
  storage=$(q postgres flexible-server list -g "$RG" --query '[0].storage.storageSizeGb' 2>/dev/null || true)
  if [[ -n "$kv" ]]; then
    # env-<name> vault secrets → API env vars. Container Apps secret names must be lowercase (Key
    # Vault names are case-insensitive, so the reference still resolves).
    extra=$(q keyvault secret list --vault-name "$kv" --query "[?starts_with(name, 'env-')].name" | node -e '
      const n = require("fs").readFileSync(0, "utf8").split(/\s+/).filter(Boolean);
      console.log(JSON.stringify(n.map((s) => ({ env: s.slice(4).toUpperCase().replace(/-/g, "_"), secret: s.toLowerCase() }))));') ||
      die "cannot list secrets in $kv"
  fi
  # Each secret is resolved first so a failure stops here (set -e doesn't see failures inside the
  # environment of the node call below).
  local pg redis jwt ajwt ask bsk
  # Postgres needs 3 of 4 character classes; hex + a fixed prefix stays URL-safe for DATABASE_URL.
  pg=$(secret_or pg-password 'printf "Yq%s" "$(openssl rand -hex 24)"' "$kv")
  redis=$(secret_or redis-password 'openssl rand -hex 24' "$kv")
  jwt=$(secret_or jwt-secret 'openssl rand -base64 48' "$kv")
  ajwt=$(secret_or admin-jwt-secret 'openssl rand -base64 48' "$kv")
  ask=$(secret_or admin-secrets-key 'openssl rand -base64 32' "$kv")
  bsk=$(secret_or backup-secrets-key 'openssl rand -base64 32' "$kv")
  # Parameters (secrets included) go through a private temp file, not the command line.
  LOCATION="$LOCATION" APPS_LOCATION="$apps_location" SHARED_ENV="$SHARED_ENV" ENVIRONMENT="$ENVIRONMENT" PRINCIPAL="$principal" PTYPE="$ptype" \
  APPS="$apps" MODE="$mode" ACR="$acr" SETTINGS="$settings" EXTRA="$extra" STORAGE="${storage:-32}" TAG="$TAG" \
  API_HOST="$API_HOST" ADMIN_HOST="$ADMIN_HOST" CAMPAIGNS="$CAMPAIGNS" CIDRS="${ADMIN_ALLOWED_CIDRS:-}" \
  PG="$pg" REDIS="$redis" JWT="$jwt" AJWT="$ajwt" ASK="$ask" BSK="$bsk" \
  node -e '
    const e = process.env, v = (value) => ({ value });
    const img = (n) => (e.ACR ? `${e.ACR}/${n}` : "");
    const p = {
      envName: v(e.ENVIRONMENT), location: v(e.LOCATION), appsLocation: v(e.APPS_LOCATION),
      existingEnvironmentId: v(e.SHARED_ENV),
      deployerPrincipalId: v(e.PRINCIPAL), deployerPrincipalType: v(e.PTYPE),
      deployApps: v(e.APPS === "true"), domainMode: v(e.MODE), enableCampaigns: v(e.CAMPAIGNS === "true"),
      apiHost: v(e.API_HOST), adminHost: v(e.ADMIN_HOST), pgStorageGB: v(Number(e.STORAGE)),
      adminAllowedCidrs: v(e.CIDRS.split(",").map((s) => s.trim()).filter(Boolean)),
      apiImage: v(img(`yaqeen-api:${e.TAG}`)), adminImage: v(img(`yaqeen-admin:${e.TAG}`)), redisImage: v(img("redis:7-alpine")),
      apiSettings: v(JSON.parse(e.SETTINGS)), extraSecrets: v(JSON.parse(e.EXTRA)),
      pgPassword: v(e.PG), redisPassword: v(e.REDIS), jwtSecret: v(e.JWT), adminJwtSecret: v(e.AJWT),
      adminSecretsKey: v(e.ASK), backupSecretsKey: v(e.BSK),
    };
    require("fs").writeFileSync(process.argv[1], JSON.stringify({ $schema: "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#", contentVersion: "1.0.0.0", parameters: p }), { mode: 0o600 });
  ' "$WORK/params.json"
  # A resource created seconds earlier can still be unknown to the role-assignment API
  # (ResourceNotFound) — transient on first runs, so retry; other failures stop.
  local attempt out
  for attempt in 1 2 3 4; do
    if out=$(az deployment group create -g "$RG" -n "yaqeen-$(date +%Y%m%d%H%M%S)" --only-show-errors -o none \
      --template-file "$ROOT/deploy/azure/main.bicep" --parameters "@$WORK/params.json" 2>&1); then
      rm -f "$WORK/params.json"
      return 0
    fi
    grep -qE 'ResourceNotFound|SSL|Connection(Reset|Error)|timed out' <<<"$out" && [[ $attempt -lt 4 ]] || { rm -f "$WORK/params.json"; die "deployment failed: $out"; }
    echo "transient failure (new resource not visible yet, or a dropped connection) — retrying in 30 s"
    sleep 30
  done
}

infra() {
  log "resource group $RG ($LOCATION; environment ${SHARED_ENV:+shared }$ENV_RG/$ENV_NAME)"
  [[ $(q group exists -n "$RG") == true ]] ||
    az group create -n "$RG" -l "$LOCATION" --tags app=yaqeen env="$ENVIRONMENT" --only-show-errors -o none
  for p in Microsoft.App Microsoft.ContainerRegistry Microsoft.DBforPostgreSQL Microsoft.KeyVault Microsoft.OperationalInsights Microsoft.ManagedIdentity; do
    az provider register -n "$p" --wait --only-show-errors -o none
  done
  log "infrastructure (first run takes ~10 min: Postgres)"
  deploy false none
}

# Built locally/in CI with BuildKit (the admin Dockerfile mounts an optional build secret, which ACR
# quick builds don't support), then pushed to the environment's registry.
images() {
  local acr server
  acr=$(q acr list -g "$RG" --query '[0].name')
  [[ -n "$acr" ]] || die "no registry yet: run infra first"
  server=$(q acr show -n "$acr" --query loginServer)
  log "images :$TAG → $server"
  [[ -n "$SHARED_ENV" ]] || az acr import -n "$acr" --source docker.io/library/redis:7-alpine -t redis:7-alpine --force --only-show-errors -o none
  az acr login -n "$acr" --only-show-errors
  export DOCKER_BUILDKIT=1
  docker build -f "$ROOT/services/api/Dockerfile" --build-arg GIT_SHA="$TAG" -t "$server/yaqeen-api:$TAG" "$ROOT"
  docker build -f "$ROOT/apps/admin/Dockerfile" --build-arg GIT_SHA="$TAG" -t "$server/yaqeen-admin:$TAG" "$ROOT"
  docker push "$server/yaqeen-api:$TAG"
  docker push "$server/yaqeen-admin:$TAG"
}

apps() {
  log "apps :$TAG"
  deploy true "$(domain_mode)"
}

migrate() {
  log "migrations"
  local run status
  run=$(q containerapp job start -g "$RG" -n yaqeen-migrate --query name)
  for _ in $(seq 1 90); do
    status=$(q containerapp job execution show -g "$RG" -n yaqeen-migrate --job-execution-name "$run" --query properties.status)
    case "$status" in
      Succeeded) echo "migrations applied ($run)"; return 0 ;;
      Failed|Stopped|Degraded) die "migration $run: $status — logs: az containerapp job logs show -g $RG -n yaqeen-migrate --execution $run --container job" ;;
    esac
    sleep 10
  done
  die "migration $run still running after 15 min"
}

smoke() {
  local fqdn
  fqdn=$(q containerapp show -g "$RG" -n yaqeen-api --query properties.configuration.ingress.fqdn)
  log "smoke https://$fqdn"
  for path in /health /ready; do
    curl -fsS --retry 10 --retry-delay 6 --retry-all-errors "https://$fqdn$path" >/dev/null && echo "ok $path"
  done
}

# Runs here, not as a cloud job: the seed prints the admin's authenticator secret once, and it must not
# land in the platform's log store. Opens Postgres to this machine's IP only while it runs.
seed() {
  local kv pgname ip email pass out otp
  kv=$(vault)
  [[ -n "$kv" ]] || die "no vault yet: run infra first"
  pgname=$(q postgres flexible-server list -g "$RG" --query '[0].name')
  email=${SEED_ADMIN_EMAIL:?set SEED_ADMIN_EMAIL to the first super admin}
  ip=$(curl -fsS https://api.ipify.org)
  log "seed via $ip (temporary firewall rule)"
  az postgres flexible-server firewall-rule create -g "$RG" --server-name "$pgname" -n seed-temp --start-ip-address "$ip" --end-ip-address "$ip" --only-show-errors -o none
  # Expanded now: the function's locals are gone by the time the EXIT trap runs.
  trap "az postgres flexible-server firewall-rule delete -g '$RG' --server-name '$pgname' -n seed-temp --yes --only-show-errors -o none; rm -rf '$WORK'" EXIT
  pass=$(secret_or seed-admin-password 'openssl rand -base64 18 | tr -d "/+="' "$kv")
  vault_set "$kv" seed-admin-password "$pass" || die "cannot store the admin password in $kv"
  # Output stays in memory: the one-time authenticator link must not be left in a temp file.
  out=$(cd "$ROOT/services/api" &&
    DATABASE_URL=$(q keyvault secret show --vault-name "$kv" -n database-url --query value) \
    ADMIN_SECRETS_KEY=$(q keyvault secret show --vault-name "$kv" -n admin-secrets-key --query value) \
    SEED_ADMIN_EMAIL="$email" SEED_ADMIN_PASSWORD="$pass" pnpm exec tsx src/db/seed.ts)
  grep -v '^otpauth://' <<<"$out"
  if otp=$(grep -m1 '^otpauth://' <<<"$out"); then
    if vault_set "$kv" seed-admin-totp "$otp"; then
      echo "Authenticator link stored in $kv › seed-admin-totp."
    else
      # Shown once: the admin row exists now and a re-run won't print it again.
      echo "!! Could not store the authenticator link. Add it to an authenticator app NOW — it won't be shown again:"
      echo "$otp"
    fi
  fi
  echo "Sign-in: $email · password: az keyvault secret show --vault-name $kv -n seed-admin-password --query value -o tsv"
  echo "After the first sign-in, delete both from the vault: az keyvault secret delete --vault-name $kv -n seed-admin-password (and seed-admin-totp)"
}

dns() {
  local verification api admin
  verification=$(q containerapp env show -g "$ENV_RG" -n "$ENV_NAME" --query properties.customDomainConfiguration.customDomainVerificationId)
  api=$(q containerapp show -g "$RG" -n yaqeen-api --query properties.configuration.ingress.fqdn)
  admin=$(q containerapp show -g "$RG" -n yaqeen-admin --query properties.configuration.ingress.fqdn)
  log "DNS records for yaqin-brand.com"
  printf '%-6s %-28s %s\n' TYPE NAME VALUE
  printf '%-6s %-28s %s\n' CNAME "${API_HOST%%.yaqin-brand.com}" "$api"
  printf '%-6s %-28s %s\n' TXT "asuid.${API_HOST%%.yaqin-brand.com}" "$verification"
  printf '%-6s %-28s %s\n' CNAME "${ADMIN_HOST%%.yaqin-brand.com}" "$admin"
  printf '%-6s %-28s %s\n' TXT "asuid.${ADMIN_HOST%%.yaqin-brand.com}" "$verification"
}

domains() {
  for host in "$API_HOST" "$ADMIN_HOST"; do
    nslookup -type=CNAME "$host" 8.8.8.8 2>/dev/null | grep -qi 'canonical name' ||
      die "$host has no CNAME yet — create the records from: $0 $ENVIRONMENT dns"
  done
  log "hostnames (validation)"
  deploy true add
  log "managed certificates + SNI binding (a few minutes)"
  deploy true bind
  for host in "$API_HOST" "$ADMIN_HOST"; do echo "https://$host"; done
}

case "$CMD" in
  all) infra; images; apps; migrate; smoke; dns ;;
  infra|images|apps|migrate|smoke|seed|dns|domains) "$CMD" ;;
  *) echo "unknown command $CMD"; exit 2 ;;
esac
