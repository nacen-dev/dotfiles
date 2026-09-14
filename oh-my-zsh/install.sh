#!/usr/bin/env bash
#
# oh-my-zsh
#

is_oh_my_zsh_installed() {
  [ -d "$HOME/.oh-my-zsh" ]
}

# Check if Oh My Zsh is already installed
if is_oh_my_zsh_installed; then
  echo "Oh My Zsh is already installed. Skipping installation."
else
  echo "Installing Oh My Zsh."
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi