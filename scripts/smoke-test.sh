#!/usr/bin/env bash
# Verify the deployed application and its build metadata.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require curl
require jq

URL="${URL:-http://127.0.0.1:8080}"

echo "Waiting for $URL/healthz"
wait_for_http "$URL/healthz" 60

echo "Checking static page..."
curl -fsS "$URL/" | grep -Fq "Md Faiz Farooqui"
curl -fsS "$URL/" | grep -Fq "2026-11-05"

echo "Checking build-info.json..."
BUILD_INFO="$(curl -fsS "$URL/build-info.json")"
echo "$BUILD_INFO" | jq -e '.build_id != "" and .git_sha != ""'

if [[ -n "${EXPECTED_BUILD_ID:-}" ]]; then
  echo "$BUILD_INFO" | jq -e --arg id "$EXPECTED_BUILD_ID" '.build_id == $id'
  echo "Build ID matches EXPECTED_BUILD_ID=$EXPECTED_BUILD_ID"
else
  echo "Deployed build: $(echo "$BUILD_INFO" | jq -r '.build_id')"
fi

echo "Smoke test passed"
