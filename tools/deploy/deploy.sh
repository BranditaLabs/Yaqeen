#!/usr/bin/env bash
# Deploy one environment (used by .github/workflows/deploy.yml; works from a laptop with a kubeconfig).
#
#   tools/deploy/deploy.sh <staging|production> <image-tag>      roll out that image tag
#   tools/deploy/deploy.sh <staging|production> --rollback       back to the previous ReplicaSets
#
# Order: render the overlay with the pinned images → run migrations (Job) and wait → apply → wait for
# the rollouts → smoke checks. A failed rollout or smoke check rolls both Deployments back and exits
# non-zero. Migrations are backwards compatible (docs/OPERATIONS.md), so a rollback never needs a
# down-migration.
set -euo pipefail

ENVIRONMENT=${1:?environment: staging|production}
TAG=${2:?image tag or --rollback}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OVERLAY="$ROOT/deploy/k8s/overlays/$ENVIRONMENT"
REGISTRY=${REGISTRY:-ghcr.io/branditalabs}
TIMEOUT=${ROLLOUT_TIMEOUT:-600s}
[[ -d "$OVERLAY" ]] || { echo "unknown environment $ENVIRONMENT"; exit 2; }
NS=$(awk '/^namespace:/ { print $2 }' "$OVERLAY/kustomization.yaml")

log() { printf '\n== %s\n' "$*"; }

rollback() {
  log "rolling back $NS"
  kubectl -n "$NS" rollout undo deploy/yaqeen-api || true
  kubectl -n "$NS" rollout undo deploy/yaqeen-admin || true
  kubectl -n "$NS" rollout status deploy/yaqeen-api --timeout="$TIMEOUT" || true
  kubectl -n "$NS" rollout status deploy/yaqeen-admin --timeout="$TIMEOUT" || true
}

if [[ "$TAG" == "--rollback" ]]; then
  rollback
  exit 0
fi

log "render $ENVIRONMENT with images :$TAG"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r "$ROOT/deploy/k8s" "$WORK/k8s"
OV="$WORK/k8s/overlays/$ENVIRONMENT"
sed -i -E "s#(name: $REGISTRY/yaqeen-api, newTag: )[^ }]+#\1$TAG#; s#(name: $REGISTRY/yaqeen-admin, newTag: )[^ }]+#\1$TAG#" "$OV/kustomization.yaml"
kubectl kustomize "$OV" > "$WORK/all.yaml"
grep -q "image: $REGISTRY/yaqeen-api:$TAG" "$WORK/all.yaml" || { echo "image pin failed"; exit 1; }

log "migrations"
# Jobs are immutable: replace the previous one, then wait for this image's migrate run.
kubectl -n "$NS" delete job yaqeen-migrate --ignore-not-found --wait=true
# Multi-character RS needs gawk (or mawk); busybox awk can't.
AWK=$(command -v gawk || command -v mawk || command -v awk)
"$AWK" 'BEGIN { RS="\n---\n"; ORS="\n---\n" } /kind: Job\n/ && /name: yaqeen-migrate/' "$WORK/all.yaml" > "$WORK/migrate.yaml"
grep -q 'name: yaqeen-migrate' "$WORK/migrate.yaml" || { echo "could not extract the migrate Job"; exit 1; }
kubectl apply -f "$WORK/migrate.yaml"
if ! kubectl -n "$NS" wait --for=condition=complete job/yaqeen-migrate --timeout=300s; then
  kubectl -n "$NS" logs job/yaqeen-migrate --tail=100 || true
  echo "migrations failed — nothing rolled out"
  exit 1
fi

log "apply"
kubectl apply -f "$WORK/all.yaml"

log "rollout"
if ! kubectl -n "$NS" rollout status deploy/yaqeen-api --timeout="$TIMEOUT" || ! kubectl -n "$NS" rollout status deploy/yaqeen-admin --timeout="$TIMEOUT"; then
  rollback
  exit 1
fi

if [[ -n "${API_URL:-}" ]]; then
  log "smoke checks"
  # Give the load balancer a moment to drain the old pods.
  sleep "${SMOKE_DELAY:-20}"
  if ! API_URL="$API_URL" ADMIN_URL="${ADMIN_URL:-}" bash "$ROOT/tools/synthetics/check.sh"; then
    rollback
    exit 1
  fi
fi

log "deployed $ENVIRONMENT :$TAG"
