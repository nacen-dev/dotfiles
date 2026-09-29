#!/usr/bin/env bash
#
# Install Godot from the official platform downloads.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Update this when adopting a newer stable release.
GODOT_VERSION="4.7.2"

if command -v godot >/dev/null 2>&1 || command -v godot.exe >/dev/null 2>&1; then
  echo "Godot is already installed. Skipping installation."
  exit 0
fi

case "$OS" in
  linux)
    case "$(uname -m)" in
      x86_64|amd64)
        GODOT_SLUG="linux.x86_64.zip"
        GODOT_PLATFORM="linux.64"
        GODOT_EXECUTABLE="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
        ;;
      aarch64|arm64)
        GODOT_SLUG="linux.arm64.zip"
        GODOT_PLATFORM="linux.arm64"
        GODOT_EXECUTABLE="Godot_v${GODOT_VERSION}-stable_linux.arm64"
        ;;
      *)
        fail "unsupported architecture for Godot: $(uname -m)"
        ;;
    esac
    ;;
  macos)
    GODOT_SLUG="macos.universal.zip"
    GODOT_PLATFORM="macos.universal"
    ;;
  windows)
    GODOT_SLUG="win64.exe.zip"
    GODOT_PLATFORM="windows.64"
    GODOT_EXECUTABLE="Godot_v${GODOT_VERSION}-stable_win64.exe"
    ;;
  *)
    fail "unsupported OS for Godot"
    ;;
esac

command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Godot"

GODOT_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/${GODOT_VERSION}"
GODOT_BIN_DIR="$HOME/.local/bin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GODOT_URL="https://downloads.godotengine.org/?version=${GODOT_VERSION}&flavor=stable&slug=${GODOT_SLUG}&platform=${GODOT_PLATFORM}"

echo "Downloading Godot ${GODOT_VERSION} from the official Godot downloads."
curl -fsSL -o "$TMP_DIR/godot.zip" "$GODOT_URL"
mkdir -p "$TMP_DIR/extracted" "$GODOT_DATA_DIR" "$GODOT_BIN_DIR"
unzip -q "$TMP_DIR/godot.zip" -d "$TMP_DIR/extracted"

case "$OS" in
  linux)
    install -m 0755 "$TMP_DIR/extracted/$GODOT_EXECUTABLE" "$GODOT_DATA_DIR/godot"
    ln -sfn "$GODOT_DATA_DIR/godot" "$GODOT_BIN_DIR/godot"
    ;;
  macos)
    ditto "$TMP_DIR/extracted/Godot.app" "$GODOT_DATA_DIR/Godot.app"
    ln -sfn "$GODOT_DATA_DIR/Godot.app/Contents/MacOS/Godot" "$GODOT_BIN_DIR/godot"
    ;;
  windows)
    cp "$TMP_DIR/extracted/$GODOT_EXECUTABLE" "$GODOT_BIN_DIR/godot.exe"
    ;;
esac

echo "Godot ${GODOT_VERSION} installed in $GODOT_BIN_DIR."
