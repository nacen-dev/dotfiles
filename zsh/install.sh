#!/usr/bin/env bash
#
# zsh installer.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

install_zsh () {
  case "$OS" in
    macos|linux)
      pkg_install zsh
      ;;
    *)
      fail "install zsh manually: https://www.zsh.org"
      ;;
  esac
}

if command -v zsh >/dev/null 2>&1; then
  echo "zsh is already installed. Skipping installation."
else
  echo "Installing zsh."
  install_zsh
fi
