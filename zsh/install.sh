#!/usr/bin/env bash
#
# zsh installer.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

case "$OS" in
  windows)
    echo "Zsh is not supported on Windows; skipping installation."
    ;;

  macos|linux)
    if command -v zsh >/dev/null 2>&1; then
      echo "zsh is already installed. Skipping installation."
    else
      echo "Installing zsh."
      pkg_install zsh
    fi
    ;;

  *)
    fail "unsupported OS for zsh installation"
    ;;
esac
