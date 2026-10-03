#!/usr/bin/env bash
#
# nvm installer

set -euo pipefail

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NVM_VERSION="v0.39.7"

case "$(uname -s)" in
  Linux|Darwin)
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      echo "NVM is already installed. Skipping installation."
      exit 0
    fi
    echo "Installing NVM."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if command -v nvm.exe >/dev/null 2>&1; then
      echo "nvm-windows is already installed. Skipping installation."
      exit 0
    fi
    echo "Installing nvm-windows."
    if command -v winget >/dev/null 2>&1; then
      winget install --silent CoreyButler.NVMforWindows
    elif command -v choco >/dev/null 2>&1; then
      choco install -y nvm
    else
      echo "Install nvm-windows manually: https://github.com/coreybutler/nvm-windows"
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS for nvm installation."
    exit 1
    ;;
esac
