#!/usr/bin/env bash
# Install a pinned Nomad CLI/agent into .tools/bin, verifying the checksum.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${NOMAD_VERSION:-2.1.1}"
DEST="${NOMAD_INSTALL_DIR:-$REPO_ROOT/.tools/bin}"

case "$(uname -m)" in
  x86_64 | amd64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *)
    echo "error: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

ZIP="nomad_${VERSION}_linux_${ARCH}.zip"
BASE="https://releases.hashicorp.com/nomad/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"

echo "Downloading Nomad ${VERSION} (linux/${ARCH})..."
curl -fsSL --retry 3 -o "$TMP/$ZIP" "$BASE/$ZIP"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$BASE/nomad_${VERSION}_SHA256SUMS"

(cd "$TMP" && grep " ${ZIP}\$" SHA256SUMS | sha256sum -c -)
unzip -oq "$TMP/$ZIP" nomad -d "$DEST"
chmod +x "$DEST/nomad"

echo "Installed $("$DEST/nomad" version)"
echo "Add $DEST to PATH, for example:"
echo "  export PATH=\"$DEST:\$PATH\""
