#!/usr/bin/env bash
#
# Install Docker Engine on Linux for development use.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

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

echo "Downloading Docker's official development installer."
curl -fsSL https://get.docker.com -o "$INSTALLER"
sudo sh "$INSTALLER"
