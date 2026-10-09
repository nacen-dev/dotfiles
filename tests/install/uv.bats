#!/usr/bin/env bats

# Tests for the uv installer. Downloads, installer execution, package managers,
# and PowerShell are stubbed so tests stay in a temporary environment.

UV_INSTALLER="$BATS_TEST_DIRNAME/../../uv/install.sh"
UV_VERSION="0.12.15"
UV_SH_SHA256="716a1d6844740756c68770fcec2f79c2013fb9b03869a113f61e15f6f482a6a1"
UV_PS1_SHA256="63f2d7e2ccc347cc018127b22f56f569080e5730a390dcb702b654daf6822193"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  SH_LOG="$TEST_ROOT/sh.log"
  PACKAGE_LOG="$TEST_ROOT/package.log"
  POWERSHELL_LOG="$TEST_ROOT/powershell.log"
  POWERSHELL_INPUT_LOG="$TEST_ROOT/powershell-input.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
  ln -s "$(command -v mktemp)" "$STUB_BIN/mktemp"
  ln -s "$(command -v rm)" "$STUB_BIN/rm"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$TEST_UNAME"
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$CURL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub uv installer' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "${ACTUAL_SHA256:-$EXPECTED_SHA256}" "$1"
EOF

  cat > "$STUB_BIN/sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$SH_LOG"
exit "${SH_STATUS:-0}"
EOF

  cat > "$STUB_BIN/powershell.exe" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$POWERSHELL_LOG"
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$POWERSHELL_INPUT_LOG"
done
exit "${POWERSHELL_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum" \
    "$STUB_BIN/sh" "$STUB_BIN/powershell.exe"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_uv_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/uv"
  chmod +x "$STUB_BIN/uv"
}

add_brew_stub() {
  cat > "$STUB_BIN/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$PACKAGE_LOG"
EOF
  chmod +x "$STUB_BIN/brew"
}

run_uv() {
  local platform=$1
  shift
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TMPDIR="$TEMP_DIR" \
    TEST_UNAME="$platform" CURL_LOG="$CURL_LOG" SH_LOG="$SH_LOG" \
    PACKAGE_LOG="$PACKAGE_LOG" POWERSHELL_LOG="$POWERSHELL_LOG" \
    POWERSHELL_INPUT_LOG="$POWERSHELL_INPUT_LOG" "$@" "$UV_INSTALLER"
}

# This verifies that an existing uv command skips all installation paths.
@test "skips installation when uv is already available" {
  add_uv_stub

  run_uv Linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"uv is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$PACKAGE_LOG" ]
}

# This verifies that Linux downloads the pinned shell installer, checks it, and invokes sh.
@test "runs the pinned shell installer on Linux" {
  run_uv Linux EXPECTED_SHA256="$UV_SH_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://astral.sh/uv/$UV_VERSION/install.sh"* ]]
  [ -n "$(<"$SH_LOG")" ]
}

# This verifies that macOS prefers Homebrew when it is available.
@test "uses Homebrew on macOS when available" {
  add_brew_stub

  run_uv Darwin

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "install uv" ]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that macOS uses the verified shell installer when Homebrew is absent.
@test "uses the shell installer on macOS without Homebrew" {
  run_uv Darwin EXPECTED_SHA256="$UV_SH_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://astral.sh/uv/$UV_VERSION/install.sh"* ]]
  [ -n "$(<"$SH_LOG")" ]
}

# This verifies that Windows verifies the PowerShell installer before invoking PowerShell.
@test "runs the verified PowerShell installer on Windows" {
  run_uv MINGW64_NT-10.0 EXPECTED_SHA256="$UV_PS1_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://astral.sh/uv/$UV_VERSION/install.ps1"* ]]
  [ "$(<"$POWERSHELL_LOG")" = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command -" ]
  [ "$(<"$POWERSHELL_INPUT_LOG")" = "stub uv installer" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that a bad Windows installer checksum blocks PowerShell and still cleans the temporary directory.
@test "rejects a Windows installer with the wrong checksum" {
  run_uv MINGW64_NT-10.0 EXPECTED_SHA256="$UV_PS1_SHA256" ACTUAL_SHA256=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$POWERSHELL_LOG" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that unsupported operating systems fail without attempting a download.
@test "fails on an unsupported operating system" {
  run_uv FreeBSD

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported OS"* ]]
  [ ! -e "$CURL_LOG" ]
}
