#!/usr/bin/env bash
#
# bootstrap installs packages, applications, and dotfiles.

set -e

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

install_packages () {
  if ! command -v curl >/dev/null 2>&1; then
    info 'installing curl'
    pkg_install curl
  fi
  success 'curl'
}

setup_gitconfig () {
  local target="$DOTFILES_ROOT/git/gitconfig.symlink"
  if [ -f "$target" ]; then
    success 'gitconfig already exists'
    return
  fi
  info 'setup gitconfig'

  user ' - What is your github author name?'
  read -e git_authorname
  user ' - What is your github author email?'
  read -e git_authoremail

  sed -e "s/AUTHORNAME/$git_authorname/g" \
      -e "s/AUTHOREMAIL/$git_authoremail/g" \
      -e "s/GIT_CREDENTIAL_HELPER/$(git_credential_helper)/g" \
      "$DOTFILES_ROOT/git/gitconfig.symlink.example" > "$target"

  success 'gitconfig'
}

setup_zshrc_local () {
  if [ ! -f "$HOME/.zshrc.local" ]; then
    cp "$DOTFILES_ROOT/zsh/zshrc.local.example" "$HOME/.zshrc.local"
    success 'zshrc.local'
  fi
}

install_dotfiles () {
  info 'installing dotfiles'

  local overwrite_all=false backup_all=false skip_all=false

  while IFS= read -r src; do
    local dst="$HOME/.$(basename "${src%.symlink}")"
    link_file "$src" "$dst"
  done < <(find "$DOTFILES_ROOT" -maxdepth 2 -name '*.symlink' -not -path '*/.git/*' | sort)
}

install_apps () {
  info 'installing applications'
  "$DOTFILES_ROOT/install/installer.sh"
}

install_packages
setup_gitconfig
install_apps
install_dotfiles
setup_zshrc_local

success 'all done'