#!/usr/bin/env bats

# Tests for the micro installer. Package managers, downloads, and privileged
# installation commands are stubbed; configuration links stay inside a temp home.

MICRO_INSTALLER="$BATS_TEST_DIRNAME/../../micro/install.sh"
MICRO_BINDINGS="$BATS_TEST_DIRNAME/../../micro/bindings.json"
MICRO_VERSION="2.0.15"
MICRO_LINUX64_SHA256="dfa1b6ae53e4e0b063b54224fd2b6b0a3c3159ea09d042a3a8f5cd001844d44c"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  CONFIG_HOME="$TEST_ROOT/config"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  SUDO_LOG="$TEST_ROOT/sudo.log"
  PACKAGE_LOG="$TEST_ROOT/package.log"
  TAR_LOG="$TEST_ROOT/tar.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME" "$CONFIG_HOME" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v basename)" "$STUB_BIN/basename"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
  ln -s "$(command -v mkdir)" "$STUB_BIN/mkdir"
  ln -s "$(command -v ln)" "$STUB_BIN/ln"
  ln -s "$(command -v mktemp)" "$STUB_BIN/mktemp"
  ln -s "$(command -v rm)" "$STUB_BIN/rm"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "$TEST_UNAME" ;;
  -m) printf '%s\n' "${TEST_ARCH:-x86_64}" ;;
  *) exit 1 ;;
esac
EOF

  cat > "$STUB_BIN/apt-cache" <<'EOF'
#!/bin/sh
exit "${APT_CACHE_STATUS:-0}"
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$CURL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub micro archive' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "$ACTUAL_SHA256" "$1"
EOF

  cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SUDO_LOG"
exit "${SUDO_STATUS:-0}"
EOF

  cat > "$STUB_BIN/tar" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$TAR_LOG"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/apt-cache" "$STUB_BIN/curl" \
    "$STUB_BIN/sha256sum" "$STUB_BIN/sudo" "$STUB_BIN/tar"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_micro_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/micro"
  chmod +x "$STUB_BIN/micro"
}

add_package_manager_stub() {
  local manager=$1
  cat > "$STUB_BIN/$manager" <<EOF
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >> "\$PACKAGE_LOG"
EOF
  chmod +x "$STUB_BIN/$manager"
}

run_micro() {
  local os=$1 arch=$2
  shift 2
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" XDG_CONFIG_HOME="$CONFIG_HOME" \
    APPDATA="$CONFIG_HOME" TMPDIR="$TEMP_DIR" TEST_UNAME="$os" TEST_ARCH="$arch" \
    CURL_LOG="$CURL_LOG" SUDO_LOG="$SUDO_LOG" PACKAGE_LOG="$PACKAGE_LOG" \
    TAR_LOG="$TAR_LOG" "$@" "$MICRO_INSTALLER"
}

# This verifies that an existing micro executable skips installation but still links its configuration.
@test "skips an installed editor and links its configuration" {
  add_micro_stub

  run_micro Linux x86_64

  [ "$status" -eq 0 ]
  [[ "$output" == *"micro is already installed"* ]]
  [ -L "$CONFIG_HOME/micro/bindings.json" ]
  [ "$CONFIG_HOME/micro/bindings.json" -ef "$MICRO_BINDINGS" ]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that macOS installation dispatches through Homebrew.
@test "installs through Homebrew on macOS" {
  add_package_manager_stub brew

  run_micro Darwin x86_64 PACKAGE_LOG="$PACKAGE_LOG"

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "brew install micro" ]
  [ -L "$CONFIG_HOME/micro/bindings.json" ]
}

# This verifies that Linux uses apt when the repository provides micro.
@test "uses apt when micro is available in the Linux package index" {
  : > "$STUB_BIN/apt-get"
  chmod +x "$STUB_BIN/apt-get"

  run_micro Linux x86_64 APT_CACHE_STATUS=0 SUDO_STATUS=0

  [ "$status" -eq 0 ]
  [ "$(<"$SUDO_LOG")" = $'apt-get update\napt-get install -y micro' ]
  [ -L "$CONFIG_HOME/micro/bindings.json" ]
}

# This verifies that the Linux release fallback selects the expected archive, verifies it, and installs it.
@test "downloads and verifies the Linux release archive when apt lacks micro" {
  run_micro Linux x86_64 APT_CACHE_STATUS=1 ACTUAL_SHA256="$MICRO_LINUX64_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://github.com/micro-editor/micro/releases/download/v$MICRO_VERSION/micro-$MICRO_VERSION-linux64.tar.gz"* ]]
  [[ "$(<"$TAR_LOG")" == *"-xzf"*" -C "* ]]
  [[ "$(<"$SUDO_LOG")" == *"install -m 0755 "*"/usr/local/bin/micro" ]]
  [ -L "$CONFIG_HOME/micro/bindings.json" ]
}

# This verifies that Windows prefers WinGet when it is available.
@test "uses WinGet to install micro on Windows" {
  add_package_manager_stub winget

  run_micro MINGW64_NT-10.0 x86_64 PACKAGE_LOG="$PACKAGE_LOG"

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "winget install --silent --id zyedidia.micro --exact --version $MICRO_VERSION" ]
  [ -L "$CONFIG_HOME/micro/bindings.json" ]
}

# This verifies that Chocolatey is used when WinGet is unavailable.
@test "uses Chocolatey when WinGet is unavailable" {
  add_package_manager_stub choco

  run_micro MINGW64_NT-10.0 x86_64 PACKAGE_LOG="$PACKAGE_LOG"

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "choco install -y micro --version=2.0.11" ]
}

# This verifies that a checksum mismatch stops the Linux release install before privileged installation.
@test "rejects a Linux release archive with the wrong checksum" {
  run_micro Linux x86_64 APT_CACHE_STATUS=1 ACTUAL_SHA256=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$SUDO_LOG" ]
  [ ! -L "$CONFIG_HOME/micro/bindings.json" ]
}

# This verifies that unsupported Linux architectures fail before downloading an archive.
@test "fails on an unsupported Linux architecture" {
  run_micro Linux riscv64 APT_CACHE_STATUS=1

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported architecture for micro"* ]]
  [ ! -e "$CURL_LOG" ]
}
