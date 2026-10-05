#!/usr/bin/env bash
#
# opencode installer + configuration setup.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pinned opencode version and installer (raw script at that release tag).
OPENCODE_VERSION="1.18.31"
OPENCODE_INSTALL_URL="https://raw.githubusercontent.com/anomalyco/opencode/v${OPENCODE_VERSION}/install"
OPENCODE_INSTALL_SHA256="fc3c1b2123f49b6df545a7622e5127d21cd794b15134fc3b66e1ca49f7fb297e"

install_opencode () {
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install anomalyco/tap/opencode
      else
        fetch_run "$OPENCODE_INSTALL_URL" "$OPENCODE_INSTALL_SHA256" bash --version "$OPENCODE_VERSION"
      fi
      ;;
    linux)
      if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm opencode
      else
        fetch_run "$OPENCODE_INSTALL_URL" "$OPENCODE_INSTALL_SHA256" bash --version "$OPENCODE_VERSION"
      fi
      ;;
    windows)
      local winget_available=false
      if command -v winget >/dev/null 2>&1; then
        winget_available=true
        if winget install --silent -e --id SST.opencode \
          --accept-source-agreements --accept-package-agreements; then
          return 0
        fi
        echo "WinGet failed to install OpenCode; checking for Chocolatey." >&2
      fi

      if command -v choco >/dev/null 2>&1; then
        echo "Installing OpenCode with Chocolatey."
        if choco install -y opencode; then
          return 0
        fi
        if [ "$winget_available" = true ]; then
          fail "OpenCode installation failed with both WinGet and Chocolatey."
        fi
        fail "OpenCode installation failed with Chocolatey."
      fi

      if [ "$winget_available" = true ]; then
        fail "WinGet failed to install OpenCode, and Chocolatey is not installed. Install Chocolatey or install OpenCode manually: https://opencode.ai/docs"
      fi
      fail "Neither WinGet nor Chocolatey is installed; install OpenCode manually: https://opencode.ai/docs"
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
