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

runtime=
for candidate in docker podman nerdctl; do
  command -v "$candidate" >/dev/null 2>&1 || continue
  [ -n "$runtime" ] || runtime=$candidate
  if "$candidate" info >/dev/null 2>&1; then
    runtime=$candidate
    break
  fi
done

if [ -z "$runtime" ]; then
  if [ "$PLATFORM" = "linux" ]; then
    fail "kind requires Docker, Podman, or nerdctl; Docker is installed by docker/ on Linux only"
  fi
  echo "warning: kind requires Docker, Podman, or nerdctl to create clusters; install one before 'kind create cluster'." >&2
fi

if [ -n "$runtime" ] && ! "$runtime" info >/dev/null 2>&1; then
  echo "warning: $runtime is installed but not reachable; start it and check permissions before 'kind create cluster'." >&2
fi

if [ "$PLATFORM" = "windows" ]; then
  KUBECTL_NAME="kubectl.exe"
  KIND_NAME="kind.exe"
else
  KUBECTL_NAME="kubectl"
  KIND_NAME="kind"
fi

BIN_DIR="$HOME/.local/bin"
kubectl_installed=false
kind_installed=false
if command -v "$KUBECTL_NAME" >/dev/null 2>&1 || [ -x "$BIN_DIR/$KUBECTL_NAME" ]; then
  kubectl_installed=true
fi
if command -v "$KIND_NAME" >/dev/null 2>&1 || [ -x "$BIN_DIR/$KIND_NAME" ]; then
  kind_installed=true
fi

if [ "$kubectl_installed" = true ] && [ "$kind_installed" = true ]; then
  echo "kubectl and kind are already installed. Skipping installation."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$BIN_DIR"

if [ "$kubectl_installed" = false ]; then
  KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${PLATFORM}/${ARCH}/${KUBECTL_NAME}"
  KUBECTL_SHA256="$(curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 "${KUBECTL_URL}.sha256")"
  echo "Installing kubectl ${KUBECTL_VERSION}."
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$TMP_DIR/$KUBECTL_NAME" "$KUBECTL_URL"
  sha256_verify "$TMP_DIR/$KUBECTL_NAME" "$KUBECTL_SHA256"
  cp "$TMP_DIR/$KUBECTL_NAME" "$BIN_DIR/$KUBECTL_NAME"
  if [ "$PLATFORM" != "windows" ]; then
    chmod 0755 "$BIN_DIR/$KUBECTL_NAME"
  fi
else
  echo "kubectl is already installed. Skipping installation."
fi

if [ "$kind_installed" = false ]; then
  KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-${PLATFORM}-${ARCH}"
  KIND_SHA256="$(curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 "${KIND_URL}.sha256sum" | awk '{print $1}')"
  echo "Installing kind v${KIND_VERSION}."
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$TMP_DIR/$KIND_NAME" "$KIND_URL"
  sha256_verify "$TMP_DIR/$KIND_NAME" "$KIND_SHA256"
  cp "$TMP_DIR/$KIND_NAME" "$BIN_DIR/$KIND_NAME"
  if [ "$PLATFORM" != "windows" ]; then
    chmod 0755 "$BIN_DIR/$KIND_NAME"
  fi
else
  echo "kind is already installed. Skipping installation."
fi

echo "Kubernetes tools installed in $BIN_DIR. Create a local cluster with: kind create cluster"
