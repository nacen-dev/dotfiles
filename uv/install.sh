#!/usr/bin/env bash
#
# uv installer.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pinned uv version; update the hashes together with the version.
UV_VERSION="0.12.15"
UV_INSTALL_SH_URL="https://astral.sh/uv/${UV_VERSION}/install.sh"
UV_INSTALL_SH_SHA256="716a1d6844740756c68770fcec2f79c2013fb9b03869a113f61e15f6f482a6a1"
UV_INSTALL_PS1_URL="https://astral.sh/uv/${UV_VERSION}/install.ps1"
UV_INSTALL_PS1_SHA256="63f2d7e2ccc347cc018127b22f56f569080e5730a390dcb702b654daf6822193"
UV_INSTALL_TMP_DIR=

install_uv () {
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install uv
      else
        fetch_run "$UV_INSTALL_SH_URL" "$UV_INSTALL_SH_SHA256" sh
      fi
      ;;
    linux)
      fetch_run "$UV_INSTALL_SH_URL" "$UV_INSTALL_SH_SHA256" sh
      ;;
    windows)
      local tmp
      UV_INSTALL_TMP_DIR="$(mktemp -d)"
      trap 'rm -rf -- "$UV_INSTALL_TMP_DIR"' EXIT
      tmp="$UV_INSTALL_TMP_DIR/install.ps1"
      curl -fsSL -o "$tmp" "$UV_INSTALL_PS1_URL"
      sha256_verify "$tmp" "$UV_INSTALL_PS1_SHA256"
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - < "$tmp"
      ;;
    *)
      fail "unsupported OS"
      ;;
  esac
}

if command -v uv >/dev/null 2>&1; then
  echo "uv is already installed. Skipping installation."
else
  echo "Installing uv."
  install_uv
fi
