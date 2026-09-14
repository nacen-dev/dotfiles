#!/usr/bin/env bash
#
# micro installer + configuration setup.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

install_micro () {
  case "$OS" in
    macos)
      pkg_install micro
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1 && apt-cache show micro >/dev/null 2>&1; then
        pkg_install micro
      else
        local tmp
        tmp="$(mktemp -d)"
        (cd "$tmp" && curl -fsSL https://getmic.ro | bash)
        sudo install -m 0755 "$tmp/micro" /usr/local/bin/micro
        rm -rf "$tmp"
      fi
      ;;
    windows)
      if command -v scoop >/dev/null 2>&1; then
        scoop install micro
      elif command -v winget >/dev/null 2>&1; then
        winget install --silent zyedidia.micro
      else
        fail "install micro manually: https://micro-editor.github.io"
      fi
      ;;
    *)
      fail "unsupported OS"
      ;;
  esac
}

if command -v micro >/dev/null 2>&1; then
  echo "micro is already installed. Skipping installation."
else
  echo "Installing micro."
  install_micro
fi

link_config "$DOTFILES_ROOT/micro/bindings.json" "$(config_home)/micro/bindings.json"