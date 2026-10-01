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
  if docker info >/dev/null 2>&1; then
    echo "Docker Engine is reachable. Skipping installation."
    exit 0
  elif command -v dockerd >/dev/null 2>&1; then
    echo "warning: dockerd is installed but Docker Engine is not reachable; check the service and permissions. Skipping installation." >&2
    exit 0
  fi
fi

INSTALLER="$(mktemp)"
trap 'rm -f "$INSTALLER"' EXIT

echo "Downloading Docker's pinned development installer."
curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$INSTALLER" "$DOCKER_INSTALL_URL"
sha256_verify "$INSTALLER" "$DOCKER_INSTALL_SHA256"
sudo sh "$INSTALLER"
