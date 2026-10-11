#!/usr/bin/env bats

# Tests for the Go installer. Downloads and privileged filesystem commands are
# stubbed so no Go installation is downloaded, removed, or unpacked.

GO_INSTALLER="$BATS_TEST_DIRNAME/../../go/install.sh"
GO_VERSION="go1.27.2"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  SUDO_LOG="$TEST_ROOT/sudo.log"
  PACKAGE_LOG="$TEST_ROOT/package.log"
  mkdir -p "$STUB_BIN" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
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
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub Go archive' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
if [ "${CHECKSUM_MISMATCH:-false}" = true ]; then
  printf '%064d  %s\n' 0 "$1"
  exit 0
fi

case "$1" in
  *go1.27.2.linux-amd64.tar.gz)  checksum=ecbadb99091a3f46e31f5f934b068b1864eafa7995211b39eaddf76996045fe5 ;;
  *go1.27.2.linux-arm64.tar.gz)  checksum=94f3e30b8e374bc285e7dadc11e0865726b9bc6e85b841ccceaabc0214c6b7c8 ;;
  *go1.27.2.linux-armv6l.tar.gz) checksum=e25a174051d8675f87ac720aedcd25bf89ac652c4b82f26aa47919524725ed95 ;;
  *go1.27.2.linux-386.tar.gz)    checksum=93dae4b7f463ed1e9c65e05561ce9fc5f7cd5c4ffca5e336248d48f3a2eab5fc ;;
  *go1.27.2.darwin-amd64.tar.gz) checksum=587b59182488b23aa6e5fc25110405a3e0e5b38ed2f5b2f46ed13c32aee356fe ;;
  *go1.27.2.darwin-arm64.tar.gz) checksum=76812b213b1b2302c978d28fa52fa92d541704b9e7d9d5db8002c50e4018c4c5 ;;
  *) exit 1 ;;
esac

printf '%s  %s\n' "$checksum" "$1"
EOF

  cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
exit "${SUDO_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum" "$STUB_BIN/sudo"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_go_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/go"
  chmod +x "$STUB_BIN/go"
}

add_package_manager_stub() {
  local manager=$1 status_variable=$2
  cat > "$STUB_BIN/$manager" <<EOF
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >> "\$PACKAGE_LOG"
exit "\${$status_variable:-0}"
EOF
  chmod +x "$STUB_BIN/$manager"
}

run_go() {
  local os=$1 arch=$2
  shift 2
  run env PATH="$STUB_BIN" TEST_UNAME="$os" TEST_ARCH="$arch" \
    TMPDIR="$TEMP_DIR" CURL_LOG="$CURL_LOG" \
    SUDO_LOG="$SUDO_LOG" PACKAGE_LOG="$PACKAGE_LOG" "$@" "$GO_INSTALLER"
}

# This verifies that an existing Go executable prevents any installation work.
@test "skips installation when Go is already available" {
  add_go_stub

  run_go Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$output" == *"Go is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that Linux selects the matching official tarball and uses sudo for replacement and extraction.
@test "downloads and installs the Linux amd64 tarball" {
  run_go Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://go.dev/dl/$GO_VERSION.linux-amd64.tar.gz"* ]]
  [[ "$(<"$CURL_LOG")" != *"VERSION"* ]]
  [[ "$(<"$SUDO_LOG")" == $'rm -rf /usr/local/go\ntar -C /usr/local -xzf '*"$GO_VERSION.linux-amd64.tar.gz" ]]
}

# This verifies that every supported Unix architecture resolves to its own pinned
# checksum, so a bad mapping for any of them is caught.
@test "installs each supported Unix architecture from its pinned tarball" {
  for pair in "Linux arm64" "Linux armv6l" "Linux i686" "Darwin amd64" "Darwin arm64"; do
    # shellcheck disable=SC2086
    set -- $pair
    run_go "$1" "$2"
    [ "$status" -eq 0 ]
    rm -f "$CURL_LOG" "$SUDO_LOG"
  done
}

# This verifies that a platform/architecture without a pinned checksum fails
# cleanly, before downloading or invoking sudo.
@test "fails when no pinned checksum exists for the platform and architecture" {
  run_go Darwin armv6l

  [ "$status" -ne 0 ]
  [[ "$output" == *"no pinned Go checksum for darwin/armv6l"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that macOS maps ARM64 to the Darwin ARM64 tarball.
@test "selects the Darwin arm64 tarball on macOS" {
  run_go Darwin arm64

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://go.dev/dl/$GO_VERSION.darwin-arm64.tar.gz"* ]]
}

# This verifies that a downloaded archive with the wrong checksum is rejected before privileged installation.
@test "rejects a Go archive with an incorrect checksum before sudo installation" {
  run_go Linux x86_64 CHECKSUM_MISMATCH=true

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that Windows prefers WinGet when installing Go.
@test "uses WinGet to install Go on Windows" {
  add_package_manager_stub winget WINGET_STATUS

  run_go MINGW64_NT-10.0 x86_64

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "winget install --silent GoLang.Go" ]
}

# This verifies that Chocolatey is used when WinGet is unavailable.
@test "uses Chocolatey when WinGet is unavailable" {
  add_package_manager_stub choco CHOCO_STATUS

  run_go MINGW64_NT-10.0 x86_64

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "choco install -y golang" ]
}

# This verifies that Windows without a supported package manager fails without attempting installation.
@test "fails on Windows when no package manager is available" {
  run_go MINGW64_NT-10.0 x86_64

  [ "$status" -ne 0 ]
  [[ "$output" == *"install Go manually"* ]]
  [ ! -e "$PACKAGE_LOG" ]
}

# This verifies that an unsupported Unix architecture fails before a tarball is downloaded.
@test "fails on an unsupported Linux architecture before downloading" {
  run_go Linux riscv64

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported architecture: riscv64"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}
