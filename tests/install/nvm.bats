#!/usr/bin/env bats

# Tests for the nvm and nvm-windows installer. Platform commands and network
# access are stubbed so these tests do not modify the host environment.

NVM_INSTALLER="$BATS_TEST_DIRNAME/../../nvm/install.sh"
NVM_VERSION="v0.39.7"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  NVM_DIR="$TEST_ROOT/nvm"
  CALL_LOG="$TEST_ROOT/calls.log"
  CURL_LOG="$TEST_ROOT/curl.log"
  mkdir -p "$STUB_BIN" "$NVM_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$TEST_UNAME"
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$CURL_LOG"
[ "${CURL_STATUS:-0}" -eq 0 ] || exit "$CURL_STATUS"
printf '%s\n' 'printf "%s\n" "$NVM_SCRIPT_MARKER" >> "$CALL_LOG"'
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_command_stub() {
  local command_name=$1 log_prefix=$2 status_variable=$3
  cat > "$STUB_BIN/$command_name" <<EOF
#!/bin/sh
printf '%s %s\n' '$log_prefix' "\$*" >> "\$CALL_LOG"
exit "\${$status_variable:-0}"
EOF
  chmod +x "$STUB_BIN/$command_name"
}

# This verifies that a nonempty nvm.sh file makes the Unix installer idempotent.
@test "skips Unix installation when nvm is already installed" {
  printf '%s\n' '# existing nvm installation' > "$NVM_DIR/nvm.sh"

  run env PATH="$STUB_BIN" TEST_UNAME=Linux NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"NVM is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that Unix installation downloads and executes the pinned nvm installer.
@test "downloads and runs the pinned installer on Linux" {
  run env PATH="$STUB_BIN" TEST_UNAME=Linux NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" NVM_SCRIPT_MARKER=ran \
    "$NVM_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing NVM."* ]]
  [ "$(<"$CURL_LOG")" = "-o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" ]
  [ "$(<"$CALL_LOG")" = ran ]
}

# This verifies that an available nvm command makes the Windows installer a no-op.
@test "skips Windows installation when nvm is already available" {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/nvm"
  chmod +x "$STUB_BIN/nvm"

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"nvm-windows is already installed"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that WinGet is preferred when installing nvm-windows.
@test "uses WinGet to install nvm-windows when available" {
  add_command_stub winget winget WINGET_STATUS

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing nvm-windows."* ]]
  [ "$(<"$CALL_LOG")" = "winget install --silent CoreyButler.NVMforWindows" ]
}

# This verifies that Chocolatey is used when WinGet is unavailable.
@test "uses Chocolatey when WinGet is unavailable" {
  add_command_stub choco choco CHOCO_STATUS

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "choco install -y nvm" ]
}

# This verifies that a failed WinGet installation is returned as a failure.
@test "propagates a WinGet installation failure" {
  add_command_stub winget winget WINGET_STATUS

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" WINGET_STATUS=23 "$NVM_INSTALLER"

  [ "$status" -eq 23 ]
  [ "$(<"$CALL_LOG")" = "winget install --silent CoreyButler.NVMforWindows" ]
}

# This verifies that Windows without either supported package manager fails clearly.
@test "fails when no Windows package manager is available" {
  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Install nvm-windows manually"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that unsupported operating systems fail without running an installer.
@test "fails on an unsupported operating system" {
  run env PATH="$STUB_BIN" TEST_UNAME=FreeBSD NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" "$NVM_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported OS for nvm installation"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that a failed Unix installer download is propagated and no script runs.
@test "propagates a Unix installer download failure" {
  run env PATH="$STUB_BIN" TEST_UNAME=Linux NVM_DIR="$NVM_DIR" \
    CALL_LOG="$CALL_LOG" CURL_LOG="$CURL_LOG" CURL_STATUS=6 "$NVM_INSTALLER"

  [ "$status" -eq 6 ]
  [ ! -e "$CALL_LOG" ]
}
