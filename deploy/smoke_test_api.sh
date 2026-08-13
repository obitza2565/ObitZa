#!/usr/bin/env bash
set -euo pipefail

API_BASE="${1:-}"
if [[ -z "${API_BASE}" ]]; then
  echo "Usage: bash deploy/smoke_test_api.sh https://api.your-domain.com"
  exit 1
fi

API_BASE="${API_BASE%/}"

check(){
  local path="$1"
  local name="$2"
  if curl -fsS "${API_BASE}${path}" >/dev/null; then
    echo "OK: ${name}"
  else
    echo "FAIL: ${name} (${path})"
    return 1
  fi
}

check "/docs" "Docs"
check "/api/mining/network" "Mining network"
check "/api/mining/leaderboard?limit=5" "Leaderboard"

echo "Smoke test passed for ${API_BASE}"
