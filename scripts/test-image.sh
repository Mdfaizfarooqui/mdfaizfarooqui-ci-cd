#!/usr/bin/env bash
# Start the built image and assert that the build metadata was injected.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require "$ENGINE"
require curl
require jq

TEST_PORT="${TEST_PORT:-18080}"
NAME="nginx-pipeline-test-$$"

cleanup() {
  "$ENGINE" rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting $IMAGE on 127.0.0.1:${TEST_PORT}"
"$ENGINE" run --detach --name "$NAME" \
  --publish "127.0.0.1:${TEST_PORT}:8080" \
  "$IMAGE" >/dev/null

wait_for_http "http://127.0.0.1:${TEST_PORT}/healthz" 60

echo "Checking rendered page..."
curl -fsS "http://127.0.0.1:${TEST_PORT}/" | grep -Fq "Md Faiz Farooqui"
curl -fsS "http://127.0.0.1:${TEST_PORT}/" | grep -Fq "2026-11-05"
curl -fsS "http://127.0.0.1:${TEST_PORT}/" | grep -Fq "$BUILD_ID"

echo "Checking build-info.json..."
curl -fsS "http://127.0.0.1:${TEST_PORT}/build-info.json" | jq -e \
  --arg build_id "$BUILD_ID" \
  --arg git_sha "$GIT_SHA" \
  '.build_id == $build_id and .git_sha == $git_sha'

echo "Image smoke test passed (BUILD_ID=$BUILD_ID)"
