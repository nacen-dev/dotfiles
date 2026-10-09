#!/usr/bin/env bats

# Tests for the Go installer. Downloads and privileged filesystem commands are
# stubbed so no Go installation is downloaded, removed, or unpacked.

GO_INSTALLER="$BATS_TEST_DIRNAME/../../go/install.sh"
GO_VERSION="go1.99.0"

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
  ln -s "$(command -v head)" "$STUB_BIN/head"
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
if [ "$2" = 'https://go.dev/VERSION?m=text' ]; then
  printf '%s\n' "$GO_VERSION"
  exit 0
fi

printf '%s\n' "$*" > "$CURL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub Go archive' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
exit "${SUDO_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sudo"
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
    GO_VERSION="$GO_VERSION" TMPDIR="$TEMP_DIR" CURL_LOG="$CURL_LOG" \
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
  [[ "$(<"$SUDO_LOG")" == $'rm -rf /usr/local/go\ntar -C /usr/local -xzf '*"$GO_VERSION.linux-amd64.tar.gz" ]]
}

# This verifies that macOS maps ARM64 to the Darwin ARM64 tarball.
@test "selects the Darwin arm64 tarball on macOS" {
  run_go Darwin arm64

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://go.dev/dl/$GO_VERSION.darwin-arm64.tar.gz"* ]]
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
