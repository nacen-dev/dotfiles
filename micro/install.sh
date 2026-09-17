#!/usr/bin/env bash
#
# micro installer + configuration setup.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pinned micro release; update the version and per-arch hashes together.
MICRO_VERSION="2.0.15"

# Emits "<asset-arch> <sha256>" for the current machine.
micro_release_target () {
  case "$(uname -m)" in
    x86_64|amd64)  echo "linux64 dfa1b6ae53e4e0b063b54224fd2b6b0a3c3159ea09d042a3a8f5cd001844d44c" ;;
    i386|i686)     echo "linux32 a105dcf5407760d11dd29c6e014238c655b1db2b0c3f08eb0e83fc986fbda196" ;;
    armv6l|armv7l) echo "linux-arm 54e5bc8a786ca103ec7e3c6d81c2799e21b21660e92edfbbdaa0561a6e601797" ;;
    aarch64|arm64) echo "linux-arm64 5ca127857bf5500be3879f1a70b27556e737a49da04a1be5334de9e8e8781ad9" ;;
    *)             fail "unsupported architecture for micro: $(uname -m)" ;;
  esac
}

install_micro_release () {
  local arch sha file tmp
  read -r arch sha < <(micro_release_target)
  file="micro-${MICRO_VERSION}-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/$file" "https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/${file}"
  sha256_verify "$tmp/$file" "$sha"
  tar -xzf "$tmp/$file" -C "$tmp"
  sudo install -m 0755 "$tmp/micro-${MICRO_VERSION}/micro" /usr/local/bin/micro
  rm -rf "$tmp"
}

install_micro () {
  case "$OS" in
    macos)
      pkg_install micro
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1 && apt-cache show micro >/dev/null 2>&1; then
        pkg_install micro
      else
        install_micro_release
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