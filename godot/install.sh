#!/usr/bin/env bash
#
# Install Godot from the official platform downloads.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Update this when adopting a newer stable release.
GODOT_VERSION="4.7.2"

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

GODOT_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/${GODOT_VERSION}"
GODOT_DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
GODOT_BIN_DIR="$HOME/.local/bin"

case "$OS" in
  linux)   GODOT_ARTIFACT="$GODOT_DATA_DIR/godot" ;;
  macos)   GODOT_ARTIFACT="$GODOT_DATA_DIR/Godot.app" ;;
  windows) GODOT_ARTIFACT="$GODOT_BIN_DIR/godot.exe" ;;
esac

if [ -e "$GODOT_ARTIFACT" ]; then
  echo "Godot ${GODOT_VERSION} is already installed. Skipping installation."
  exit 0
fi

command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Godot"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Link the launcher without replacing files or symlinks not managed by Godot.
link_godot_bin () {
  local target=$1 dest="$GODOT_BIN_DIR/godot"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "warning: $dest already exists; leaving it untouched. Godot is installed at $target." >&2
  elif [ -L "$dest" ]; then
    local current_target
    current_target="$(readlink "$dest")"
    case "$current_target" in
      "$GODOT_DATA_ROOT"/*)
        ln -sfn "$target" "$dest"
        ;;
      *)
        echo "warning: $dest points outside the Godot install directory; leaving it untouched. Godot is installed at $target." >&2
        ;;
    esac
  else
    ln -s "$target" "$dest"
  fi
}

GODOT_URL="https://downloads.godotengine.org/?version=${GODOT_VERSION}&flavor=stable&slug=${GODOT_SLUG}&platform=${GODOT_PLATFORM}"
GODOT_SUMS_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/SHA512-SUMS.txt"
GODOT_ARCHIVE="Godot_v${GODOT_VERSION}-stable_${GODOT_SLUG}"

echo "Downloading Godot ${GODOT_VERSION} from the official Godot downloads."
curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$TMP_DIR/godot.zip" "$GODOT_URL"
GODOT_SHA512="$(curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 "$GODOT_SUMS_URL" | awk -v f="$GODOT_ARCHIVE" '$NF == f {print $1}')"
sha512_verify "$TMP_DIR/godot.zip" "$GODOT_SHA512"
mkdir -p "$TMP_DIR/extracted" "$GODOT_DATA_DIR" "$GODOT_BIN_DIR"
unzip -q "$TMP_DIR/godot.zip" -d "$TMP_DIR/extracted"

case "$OS" in
  linux)
    install -m 0755 "$TMP_DIR/extracted/$GODOT_EXECUTABLE" "$GODOT_DATA_DIR/godot"
    link_godot_bin "$GODOT_DATA_DIR/godot"
    ;;
  macos)
    ditto "$TMP_DIR/extracted/Godot.app" "$GODOT_DATA_DIR/Godot.app"
    link_godot_bin "$GODOT_DATA_DIR/Godot.app/Contents/MacOS/Godot"
    ;;
  windows)
    cp "$TMP_DIR/extracted/$GODOT_EXECUTABLE" "$GODOT_BIN_DIR/godot.exe"
    ;;
esac

echo "Godot ${GODOT_VERSION} installed in $GODOT_BIN_DIR."
