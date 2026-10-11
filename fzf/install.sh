#!/usr/bin/env bash
#
# fzf installer.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

install_fzf () {
  case "$OS" in
    linux|macos)
      pkg_install fzf
      ;;
    windows)
      if command -v winget >/dev/null 2>&1; then
        winget install --silent --id junegunn.fzf --exact
      elif command -v choco >/dev/null 2>&1; then
        choco install -y fzf
      else
        fail "no supported package manager found"
      fi
      ;;
    *)
      fail "unsupported OS for fzf installation"
      ;;
  esac
}

if command -v fzf >/dev/null 2>&1; then
  echo "fzf is already installed. Skipping installation."
else
  echo "Installing fzf."
  install_fzf
fi
