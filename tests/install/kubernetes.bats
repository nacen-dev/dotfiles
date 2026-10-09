#!/usr/bin/env bats

# Tests for kubectl and kind installation. Downloads are stubbed, and installed
# binaries are written only inside a temporary HOME directory.

KUBERNETES_INSTALLER="$BATS_TEST_DIRNAME/../../kubernetes/install.sh"
KUBECTL_VERSION="v1.37.1"
KIND_VERSION="0.33.0"
TEST_SHA256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  RUNTIME_LOG="$TEST_ROOT/runtime.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
  ln -s "$(command -v chmod)" "$STUB_BIN/chmod"
  ln -s "$(command -v cp)" "$STUB_BIN/cp"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v mkdir)" "$STUB_BIN/mkdir"
  ln -s "$(command -v mktemp)" "$STUB_BIN/mktemp"
  ln -s "$(command -v rm)" "$STUB_BIN/rm"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "$TEST_UNAME" ;;
  -m) printf '%s\n' "$TEST_ARCH" ;;
  *) exit 1 ;;
esac
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
has_output=false
last=
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub binary' > "$1"
    has_output=true
  fi
  last=$1
  shift
done

if [ "$has_output" = true ]; then
  exit "${CURL_STATUS:-0}"
fi

case "$last" in
  *.sha256)
    printf '%s\n' "$KUBECTL_SHA256"
    ;;
  *.sha256sum)
    printf '%s  kind\n' "$KIND_SHA256"
    ;;
  *)
    exit 1
    ;;
esac
exit "${CURL_STATUS:-0}"
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "${ACTUAL_SHA256:-$EXPECTED_SHA256}" "$1"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_runtime_stub() {
  local runtime=$1 status_variable=${2:-RUNTIME_STATUS}
  cat > "$STUB_BIN/$runtime" <<EOF
#!/bin/sh
printf '%s %s\\n' '$runtime' "\$*" >> "\$RUNTIME_LOG"
exit "\${$status_variable:-0}"
EOF
  chmod +x "$STUB_BIN/$runtime"
}

add_installed_tool() {
  local tool=$1
  mkdir -p "$TEST_HOME/.local/bin"
  printf '%s\n' 'existing tool' > "$TEST_HOME/.local/bin/$tool"
  chmod +x "$TEST_HOME/.local/bin/$tool"
}

run_kubernetes() {
  local os=$1 arch=$2
  shift 2
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TMPDIR="$TEMP_DIR" \
    TEST_UNAME="$os" TEST_ARCH="$arch" CURL_LOG="$CURL_LOG" \
    RUNTIME_LOG="$RUNTIME_LOG" EXPECTED_SHA256="$TEST_SHA256" \
    KUBECTL_SHA256="$TEST_SHA256" KIND_SHA256="$TEST_SHA256" \
    "$@" "$KUBERNETES_INSTALLER"
}

# This verifies that Linux requires an available container runtime before downloading tools.
@test "fails on Linux when no container runtime is available" {
  run_kubernetes Linux x86_64

  [ "$status" -ne 0 ]
  [[ "$output" == *"kind requires Docker, Podman, or nerdctl"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies Linux selects amd64 URLs, validates downloads, and marks both tools executable.
@test "installs Linux amd64 kubectl and kind when Docker is available" {
  add_runtime_stub docker

  run_kubernetes Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"/bin/linux/amd64/kubectl"* ]]
  [[ "$(<"$CURL_LOG")" == *"kind-linux-amd64"* ]]
  [ -x "$TEST_HOME/.local/bin/kubectl" ]
  [ -x "$TEST_HOME/.local/bin/kind" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies macOS warns about a missing runtime but still installs Darwin ARM64 tools.
@test "warns but installs Darwin ARM64 tools without a runtime" {
  run_kubernetes Darwin arm64

  [ "$status" -eq 0 ]
  [[ "$output" == *"kind requires Docker, Podman, or nerdctl"* ]]
  [[ "$(<"$CURL_LOG")" == *"/bin/darwin/arm64/kubectl"* ]]
  [[ "$(<"$CURL_LOG")" == *"kind-darwin-arm64"* ]]
  [ -x "$TEST_HOME/.local/bin/kubectl" ]
  [ -x "$TEST_HOME/.local/bin/kind" ]
}

# This verifies Windows selects .exe artifacts, warns about the missing runtime, and skips chmod.
@test "installs Windows executables without a runtime" {
  run_kubernetes MINGW64_NT-10.0 x86_64

  [ "$status" -eq 0 ]
  [[ "$output" == *"kind requires Docker, Podman, or nerdctl"* ]]
  [[ "$(<"$CURL_LOG")" == *"/bin/windows/amd64/kubectl.exe"* ]]
  [[ "$(<"$CURL_LOG")" == *"kind-windows-amd64"* ]]
  [ -f "$TEST_HOME/.local/bin/kubectl.exe" ]
  [ -f "$TEST_HOME/.local/bin/kind.exe" ]
  [ ! -x "$TEST_HOME/.local/bin/kubectl.exe" ]
  [ ! -x "$TEST_HOME/.local/bin/kind.exe" ]
}

# This verifies that having both tools already installed skips downloads.
@test "skips downloads when kubectl and kind are already installed" {
  add_runtime_stub docker
  add_installed_tool kubectl
  add_installed_tool kind

  run_kubernetes Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl and kind are already installed"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that an existing kubectl is preserved while only kind is downloaded.
@test "installs only kind when kubectl is already present" {
  add_runtime_stub docker
  add_installed_tool kubectl

  run_kubernetes Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" != *"/bin/linux/amd64/kubectl"* ]]
  [[ "$(<"$CURL_LOG")" == *"kind-linux-amd64"* ]]
  [ -x "$TEST_HOME/.local/bin/kubectl" ]
  [ -x "$TEST_HOME/.local/bin/kind" ]
}

# This verifies that a checksum mismatch prevents copying the binary and cleans temporary files.
@test "rejects a kubectl download with the wrong checksum" {
  add_runtime_stub docker

  run_kubernetes Linux x86_64 ACTUAL_SHA256=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$TEST_HOME/.local/bin/kubectl" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that unsupported Windows architectures fail before any download.
@test "fails on unsupported Windows architectures" {
  run_kubernetes MINGW64_NT-10.0 aarch64

  [ "$status" -ne 0 ]
  [[ "$output" == *"kind does not provide a Windows binary"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that an installed but unreachable runtime produces a warning while installation proceeds.
@test "warns when a runtime is installed but unreachable" {
  add_runtime_stub docker DOCKER_STATUS

  run_kubernetes Linux x86_64 DOCKER_STATUS=1

  [ "$status" -eq 0 ]
  [[ "$output" == *"docker is installed but not reachable"* ]]
  [ -x "$TEST_HOME/.local/bin/kubectl" ]
}

# This verifies that a reachable runtime is preferred over an unreachable earlier candidate.
@test "prefers a reachable runtime over an unreachable one" {
  add_runtime_stub docker DOCKER_STATUS
  add_runtime_stub podman PODMAN_STATUS

  run_kubernetes Linux x86_64 DOCKER_STATUS=1 PODMAN_STATUS=0

  [ "$status" -eq 0 ]
  [[ "$output" != *"not reachable"* ]]
  [ -x "$TEST_HOME/.local/bin/kind" ]
}
