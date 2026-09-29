#!/usr/bin/env bash
#
# Install kubectl and kind for local Kubernetes development.

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# kind v0.33.0 defaults to Kubernetes v1.37.0; keep kubectl in that minor.
KUBECTL_VERSION="v1.37.1"
KIND_VERSION="0.33.0"

case "$OS" in
  linux)   PLATFORM="linux" ;;
  macos)   PLATFORM="darwin" ;;
  windows) PLATFORM="windows" ;;
  *)       fail "unsupported OS for Kubernetes tooling" ;;
esac

if [ "$PLATFORM" = "windows" ]; then
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    *) fail "kind does not provide a Windows binary for $(uname -m)" ;;
  esac
else
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "unsupported architecture for Kubernetes tooling: $(uname -m)" ;;
  esac
fi

if ! command -v docker >/dev/null 2>&1 &&
   ! command -v podman >/dev/null 2>&1 &&
   ! command -v nerdctl >/dev/null 2>&1; then
  fail "kind requires Docker, Podman, or nerdctl; Docker is installed by docker/ on Linux only"
fi

BIN_DIR="$HOME/.local/bin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$BIN_DIR"

if [ "$PLATFORM" = "windows" ]; then
  KUBECTL_NAME="kubectl.exe"
  KIND_NAME="kind.exe"
else
  KUBECTL_NAME="kubectl"
  KIND_NAME="kind"
fi

KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${PLATFORM}/${ARCH}/${KUBECTL_NAME}"
KUBECTL_SHA256="$(curl -fsSL "${KUBECTL_URL}.sha256")"
echo "Installing kubectl ${KUBECTL_VERSION}."
curl -fsSL -o "$TMP_DIR/$KUBECTL_NAME" "$KUBECTL_URL"
sha256_verify "$TMP_DIR/$KUBECTL_NAME" "$KUBECTL_SHA256"
cp "$TMP_DIR/$KUBECTL_NAME" "$BIN_DIR/$KUBECTL_NAME"
chmod 0755 "$BIN_DIR/$KUBECTL_NAME"

KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-${PLATFORM}-${ARCH}"
echo "Installing kind v${KIND_VERSION}."
curl -fsSL -o "$TMP_DIR/$KIND_NAME" "$KIND_URL"
cp "$TMP_DIR/$KIND_NAME" "$BIN_DIR/$KIND_NAME"
chmod 0755 "$BIN_DIR/$KIND_NAME"

echo "Kubernetes tools installed in $BIN_DIR. Create a local cluster with: kind create cluster"
