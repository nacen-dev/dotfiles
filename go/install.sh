#!/usr/bin/env bash
#
# Go installer (official tarball on Linux/macOS).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

go_arch () {
  case "$(uname -m)" in
    x86_64|amd64)   echo amd64 ;;
    aarch64|arm64)  echo arm64 ;;
    armv6l)         echo armv6l ;;
    i386|i686)      echo 386 ;;
    *)              return 1 ;;
  esac
}

install_go_tarball () {
  local platform=$1
  local version arch tarball tmp
  if ! arch="$(go_arch)"; then
    fail "unsupported architecture: $(uname -m)"
  fi
  version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
  tarball="${version}.${platform}-${arch}.tar.gz"
  tmp="$(mktemp -d)"

  echo "Downloading ${tarball}"
  curl -fsSL -o "$tmp/$tarball" "https://go.dev/dl/${tarball}"

  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/$tarball"
  rm -rf "$tmp"
}

install_go () {
  case "$OS" in
    linux) install_go_tarball linux ;;
    macos) install_go_tarball darwin ;;
    windows)
      if command -v winget >/dev/null 2>&1; then
        winget install --silent GoLang.Go
      elif command -v choco >/dev/null 2>&1; then
        choco install -y golang
      else
        fail "install Go manually: https://go.dev/dl"
      fi
      ;;
    *)
      fail "unsupported OS"
      ;;
  esac
}

if command -v go >/dev/null 2>&1; then
  echo "Go is already installed. Skipping installation."
else
  echo "Installing Go."
  install_go
fi
