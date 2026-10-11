#!/usr/bin/env bash
#
# bootstrap installs packages, applications, and dotfiles.

set -e

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

apps_failed=false

install_packages () {
  if ! command -v curl >/dev/null 2>&1; then
    if [ "$OS" = windows ]; then
      fail 'curl is required on Windows but was not found; install curl and rerun bootstrap'
    fi
    info 'installing curl'
    pkg_install curl
  fi
  success 'curl'
}

setup_gitconfig () {
  local target="$DOTFILES_ROOT/git/gitconfig.symlink"
  if [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    success 'existing gitconfig found; leaving it untouched'
    return
  fi
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

  # Read NUL-delimited paths from fd 3, leaving stdin available for link_file prompts.
  while IFS= read -r -d '' src <&3; do
    local dst="$HOME/.$(basename "${src%.symlink}")"
    if [ "$src" = "$DOTFILES_ROOT/git/gitconfig.symlink" ] &&
       { [ -e "$dst" ] || [ -L "$dst" ]; } &&
       ! [ "$dst" -ef "$src" ]; then
      success "existing gitconfig at $dst; leaving it untouched"
      continue
    fi
    link_file "$src" "$dst"
  # Feed find's NUL-delimited output to fd 3, keeping stdin free for prompts.
  done 3< <(
    find "$DOTFILES_ROOT" -maxdepth 2 -name '*.symlink' \
      -not -path '*/.git/*' -print0
  )
}

install_apps () {
  info 'installing applications'
  if ! "$DOTFILES_ROOT/install/installer.sh"; then
    apps_failed=true
  fi
}

setup_local_bin_path () {
  # Let later installers find tools installed in ~/.local/bin during this run.
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac

  add_local_bin_to_windows_path
}

setup_git_hooks () {
  if [ -d "$DOTFILES_ROOT/.git" ]; then
    git -C "$DOTFILES_ROOT" config core.hooksPath .githooks
    success 'git hooks'
  fi
}

install_packages
setup_gitconfig
setup_local_bin_path
install_apps
install_dotfiles
setup_zshrc_local
setup_git_hooks

if [ "$apps_failed" = true ]; then
  fail 'one or more application installers failed'
fi

success 'all done'
