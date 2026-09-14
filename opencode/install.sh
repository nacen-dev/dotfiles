#!/usr/bin/env bash
#
# opencode installer + configuration setup.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

install_opencode () {
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install anomalyco/tap/opencode
      else
        curl -fsSL https://opencode.ai/install | bash
      fi
      ;;
    linux)
      if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm opencode
      else
        curl -fsSL https://opencode.ai/install | bash
      fi
      ;;
    windows)
      if command -v choco >/dev/null 2>&1; then
        choco install -y opencode
      elif command -v scoop >/dev/null 2>&1; then
        scoop install opencode
      else
        fail "install opencode manually: https://opencode.ai/docs"
      fi
      ;;
    *)
      fail "unsupported OS"
      ;;
  esac
}

if command -v opencode >/dev/null 2>&1; then
  echo "opencode is already installed. Skipping installation."
else
  echo "Installing opencode."
  install_opencode
fi

# Global config location is ~/.config/opencode/opencode.jsonc on Linux/macOS.
link_config "$DOTFILES_ROOT/opencode/opencode.jsonc" "$(config_home)/opencode/opencode.jsonc"