#!/usr/bin/env bash
#
# tmux installer.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

case "$OS" in
  windows)
    echo "tmux is not supported in Windows Git Bash; skipping installation."
    ;;

  macos|linux)
    if command -v tmux >/dev/null 2>&1; then
      echo "tmux is already installed. Skipping installation."
    else
      echo "Installing tmux."
      pkg_install tmux
    fi
    ;;

  *)
    fail "unsupported OS for tmux installation"
    ;;
esac
