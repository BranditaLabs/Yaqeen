#!/usr/bin/env bash
# Synthetic checks of a Yaqeen environment, from outside the cluster (CI, a laptop).
#   API_URL=https://api.yaqin-brand.com ADMIN_URL=https://admin.yaqin-brand.com bash tools/synthetics/check.sh
# Exits non-zero when any check fails; prints one line per check with status and time.
set -uo pipefail
API_URL=${API_URL:?set API_URL}
ADMIN_URL=${ADMIN_URL:-}
MAX_MS=${MAX_MS:-2000}
fail=0

check() { # name url expected-status [must-contain]
  local name=$1 url=$2 want=$3 needle=${4:-}
  local out code ms body
  body=$(mktemp)
  out=$(curl -sS -o "$body" -w '%{http_code} %{time_total}' -A 'yaqeen-synthetics' --max-time 15 "$url" 2>&1) || out="000 15"
  code=${out%% *}
  ms=$(awk -v t="${out##* }" 'BEGIN { printf "%d", t * 1000 }')
  local ok=1
  [[ "$code" == "$want" ]] || ok=0
  [[ -z "$needle" ]] || grep -q -- "$needle" "$body" || ok=0
  (( ms <= MAX_MS )) || ok=0
  rm -f "$body"
  if (( ok )); then echo "ok   $name $code ${ms}ms"; else echo "FAIL $name $code ${ms}ms ($url)"; fail=1; fi
}

check health "$API_URL/health" 200 '"ok":true'
check ready "$API_URL/ready" 200 '"ok":true'
check config "$API_URL/v1/config" 200 '"features"'
check hijri "$API_URL/v1/calendar/hijri?year=2026&month=1" 200 '"days"'
check card-404 "$API_URL/u/zz_synthetic_missing" 404 'يقين'
check get-app "$API_URL/get-app" 302
[[ -z "$ADMIN_URL" ]] || check admin-login "$ADMIN_URL/login" 200

exit $fail
