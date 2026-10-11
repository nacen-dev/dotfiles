#!/usr/bin/env bash
#
# Go installer (official tarball on Linux/macOS).

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pin the Go version and its per-platform checksums together.
GO_VERSION="go1.27.2"

go_arch () {
  case "$(uname -m)" in
    x86_64|amd64)   echo amd64 ;;
    aarch64|arm64)  echo arm64 ;;
    armv6l)         echo armv6l ;;
    i386|i686)      echo 386 ;;
    *)              return 1 ;;
  esac
}

go_archive_sha256 () {
  case "$1-$2" in
    linux-amd64)  printf '%s\n' 'ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5' ;;
    linux-arm64)  printf '%s\n' '94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8' ;;
    linux-armv6l) printf '%s\n' 'e25a174051d8675f87ac720aedcd25bf89ac652c4b82f26aa47919524725ed95' ;;
    linux-386)    printf '%s\n' '93dae4b7f463ed1e9c65e05561ce9fc5f7cd5c4ffca5e336248d48f3a2eab5fc' ;;
    darwin-amd64) printf '%s\n' '587b59182488b23aa6e5fc25110405a3e0e5b38ed2f5b2f46ed13c32aee356fe' ;;
    darwin-arm64) printf '%s\n' '76812b213b1b2302c978d28fa52fa92d541704b9e7d9d5db8002c50e4018c4c5' ;;
    *) return 1 ;;
  esac
}

install_go_tarball () {
  local platform=$1
  local arch expected_sha tarball tmp
  if ! arch="$(go_arch)"; then
    fail "unsupported architecture: $(uname -m)"
  fi

  if ! expected_sha="$(go_archive_sha256 "$platform" "$arch")"; then
    fail "no pinned Go checksum for ${platform}/${arch}"
  fi

  tarball="${GO_VERSION}.${platform}-${arch}.tar.gz"
  tmp="$(mktemp -d)"

  echo "Downloading ${tarball}"
  curl -fsSL -o "$tmp/$tarball" "https://go.dev/dl/${tarball}"
  sha256_verify "$tmp/$tarball" "$expected_sha"

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
