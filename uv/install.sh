#!/usr/bin/env bash
#
# uv installer.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

install_uv () {
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install uv
      else
        curl -LsSf https://astral.sh/uv/install.sh | sh
      fi
      ;;
    linux)
      curl -LsSf https://astral.sh/uv/install.sh | sh
      ;;
    windows)
      powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
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