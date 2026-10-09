#!/usr/bin/env bash
#
# oh-my-zsh
#

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

if [ "$OS" = windows ] || ! command -v zsh >/dev/null 2>&1; then
  echo "Skipping Oh My Zsh because zsh is unavailable on this platform."
  exit 0
fi

# Pinned to the commit below; update both together.
OMZ_INSTALL_COMMIT="0ee67f042872d1dfab74270c31867771ca35aef4"
OMZ_INSTALL_SHA256="5574b96e94dbcb769f0d1592fa83aeb6ca2caf41c6ae5d76fcc7f04c524b4f55"

is_oh_my_zsh_installed() {
  [ -d "$HOME/.oh-my-zsh" ]
}

# Check if Oh My Zsh is already installed
if is_oh_my_zsh_installed; then
  echo "Oh My Zsh is already installed. Skipping installation."
else
  echo "Installing Oh My Zsh."
  if [ -e "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; then
    echo "Existing $HOME/.zshrc found; keeping it and skipping the Oh My Zsh .zshrc setup."
  fi
  fetch_run \
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_INSTALL_COMMIT}/tools/install.sh" \
    "$OMZ_INSTALL_SHA256" sh --unattended --keep-zshrc
fi