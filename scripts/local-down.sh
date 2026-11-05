#!/usr/bin/env bash
# Stop the assessment jobs and the local Nomad agent started by local-up.sh.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if command -v nomad >/dev/null 2>&1 && nomad_ready; then
  for job in nginx grafana promtail loki; do
    echo "Stopping $job"
    nomad job stop -purge "$job" >/dev/null 2>&1 || true
  done
fi

if [[ -f "$REPO_ROOT/.nomad-dev.pid" ]]; then
  pid="$(cat "$REPO_ROOT/.nomad-dev.pid")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "Stopping Nomad agent (pid $pid)"
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$REPO_ROOT/.nomad-dev.pid"
fi

echo "Local stack stopped"
