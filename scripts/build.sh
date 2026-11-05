#!/usr/bin/env bash
# Build the NGINX image with provenance metadata baked in at build time.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require "$ENGINE"

echo "Building $IMAGE"
echo "  BUILD_ID         = $BUILD_ID"
echo "  GIT_SHA          = $GIT_SHA"
echo "  BUILD_DATE       = $BUILD_DATE"
echo "  BUILD_REPOSITORY = $BUILD_REPOSITORY"

"$ENGINE" build \
  --file "$REPO_ROOT/app/Dockerfile" \
  --tag "$IMAGE" \
  --build-arg "BUILD_ID=$BUILD_ID" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  --build-arg "BUILD_DATE=$BUILD_DATE" \
  --build-arg "BUILD_REPOSITORY=$BUILD_REPOSITORY" \
  "$REPO_ROOT/app"

echo "Built $IMAGE"
