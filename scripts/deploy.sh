#!/usr/bin/env bash
# Deploy or update the NGINX Nomad job.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require nomad

if ! nomad_ready; then
  echo "error: cannot reach Nomad at $NOMAD_ADDR" >&2
  echo "hint: run 'make local-up' or set NOMAD_ADDR/NOMAD_TOKEN" >&2
  exit 1
fi

IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-if-not-present}"

echo "Deploying $IMAGE to $NOMAD_ADDR (pull policy: $IMAGE_PULL_POLICY)"
nomad job run \
  -var "image=$IMAGE" \
  -var "image_pull_policy=$IMAGE_PULL_POLICY" \
  "$REPO_ROOT/nomad/nginx.nomad.hcl"

nomad job status -short nginx
