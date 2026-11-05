#!/usr/bin/env bash
# Shared helpers for the local and CI scripts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Use the repository-local Nomad install without requiring a manual PATH edit.
if [[ -d "$REPO_ROOT/.tools/bin" ]]; then
  case ":$PATH:" in
    *":$REPO_ROOT/.tools/bin:"*) ;;
    *) export PATH="$REPO_ROOT/.tools/bin:$PATH" ;;
  esac
fi

NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"
export NOMAD_ADDR
if [[ -n "${NOMAD_TOKEN:-}" ]]; then
  export NOMAD_TOKEN
fi

ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z "$ENGINE" ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ENGINE="docker"
  elif command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
  else
    echo "error: neither docker (accessible) nor podman is available" >&2
    echo "hint: add your user to the docker group, or set CONTAINER_ENGINE=podman" >&2
    exit 1
  fi
fi
export ENGINE

BUILD_ID="${BUILD_ID:-$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo local)}"
GIT_SHA="${GIT_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
BUILD_REPOSITORY="${BUILD_REPOSITORY:-local/nginx-nomad-pipeline}"
IMAGE="${IMAGE:-nginx-nomad-pipeline:${BUILD_ID}}"
export BUILD_ID GIT_SHA BUILD_DATE BUILD_REPOSITORY IMAGE

require() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' is not installed" >&2
    exit 1
  fi
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-60}"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "error: timed out waiting for $url" >&2
  return 1
}

nomad_ready() {
  curl -fsS --max-time 2 "$NOMAD_ADDR/v1/status/leader" >/dev/null 2>&1
}
