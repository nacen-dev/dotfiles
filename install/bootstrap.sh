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
  read -er git_authorname
  user ' - What is your github author email?'
  read -er git_authoremail

  git_authorname=$(printf '%s' "$git_authorname" | sed 's/[&/\\]/\\&/g')
  git_authoremail=$(printf '%s' "$git_authoremail" | sed 's/[&/\\]/\\&/g')

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

  # Flags consumed by link_file via dynamic scope (see install/lib.sh).
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

setup_git_hooks () {
  if [ -d "$DOTFILES_ROOT/.git" ]; then
    git -C "$DOTFILES_ROOT" config core.hooksPath .githooks
    success 'git hooks'
  fi
}

install_packages
setup_gitconfig
install_apps
install_dotfiles
setup_zshrc_local
setup_git_hooks

success 'all done'