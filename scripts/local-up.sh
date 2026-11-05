#!/usr/bin/env bash
# Reproduce the full stack on a single machine:
#   1. start a local Nomad dev agent (if one is not already reachable)
#   2. build the image with an injected build ID
#   3. deploy Loki, Promtail and Grafana
#   4. deploy the NGINX job and smoke-test it
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require nomad
require curl

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "error: the local Nomad job uses the Docker task driver, but Docker is not accessible." >&2
  echo "hint: sudo usermod -aG docker \$USER, then log out and back in." >&2
  exit 1
fi

if ! nomad_ready; then
  echo "Starting Nomad dev agent..."
  nohup nomad agent -dev -bind=127.0.0.1 \
    -config="$REPO_ROOT/nomad/local-agent.hcl" \
    >"$REPO_ROOT/.nomad-dev.log" 2>&1 &
  echo $! >"$REPO_ROOT/.nomad-dev.pid"

  for _ in $(seq 1 60); do
    if nomad_ready; then
      break
    fi
    sleep 1
  done

  if ! nomad_ready; then
    echo "error: Nomad did not become ready. Last log lines:" >&2
    tail -n 30 "$REPO_ROOT/.nomad-dev.log" >&2 || true
    exit 1
  fi
fi

"$REPO_ROOT/scripts/build.sh"

echo "Deploying observability stack..."
for job in loki promtail grafana; do
  nomad job run -detach "$REPO_ROOT/nomad/observability/${job}.nomad.hcl"
done

IMAGE_PULL_POLICY="if-not-present" "$REPO_ROOT/scripts/deploy.sh"

echo "Waiting for Grafana and Loki..."
wait_for_http "http://127.0.0.1:3100/ready" 90 || true
wait_for_http "http://127.0.0.1:3000/api/health" 90 || true

"$REPO_ROOT/scripts/smoke-test.sh"

cat <<EOF

Local stack is running:
  Application : http://127.0.0.1:8080
  Build info  : http://127.0.0.1:8080/build-info.json
  Grafana     : http://127.0.0.1:3000  (anonymous viewer; admin/admin)
  Loki        : http://127.0.0.1:3100
  Nomad UI    : http://127.0.0.1:4646

Tear down with: make local-down
EOF
