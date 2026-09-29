#!/usr/bin/env bash
#
# Install Docker Engine on Linux for development use.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pin the docker/docker-install commit; update the URL and hash together.
DOCKER_INSTALL_COMMIT="2b32480025b223ebfddae9a3a8bef09027680f53"
DOCKER_INSTALL_URL="https://raw.githubusercontent.com/docker/docker-install/${DOCKER_INSTALL_COMMIT}/install.sh"
DOCKER_INSTALL_SHA256="fefa50ccd50efb42f438b506fc3a88574118f314aaf2a7cd5b6e1ffb1bffcf26"

case "$OS" in
  linux)
    ;;
  macos|windows)
    echo "Docker installation is skipped on $OS."
    exit 0
    ;;
  *)
    fail "unsupported OS for Docker"
    ;;
esac

if command -v docker >/dev/null 2>&1; then
  echo "Docker is already installed. Skipping installation."
  exit 0
fi

INSTALLER="$(mktemp)"
trap 'rm -f "$INSTALLER"' EXIT

echo "Downloading Docker's pinned development installer."
curl -fsSL -o "$INSTALLER" "$DOCKER_INSTALL_URL"
sha256_verify "$INSTALLER" "$DOCKER_INSTALL_SHA256"
sudo sh "$INSTALLER"
