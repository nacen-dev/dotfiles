#!/usr/bin/env bats

# Tests for the fzf installer. Platform and package commands are stubbed so
# these tests never install software.

FZF_INSTALLER="$BATS_TEST_DIRNAME/../../fzf/install.sh"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  CALL_LOG="$TEST_ROOT/calls.log"
  mkdir -p "$STUB_BIN"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$TEST_UNAME"
EOF

  cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALL_LOG"
EOF

  : > "$STUB_BIN/apt-get"
  chmod +x "$STUB_BIN/uname" "$STUB_BIN/sudo" "$STUB_BIN/apt-get"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_package_manager_stub() {
  local manager=$1
  cat > "$STUB_BIN/$manager" <<EOF
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >> "\$CALL_LOG"
exit "\${PACKAGE_STATUS:-0}"
EOF
  chmod +x "$STUB_BIN/$manager"
}

# This verifies that an available fzf executable makes the installer a no-op.
@test "skips installation when fzf is already available" {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/fzf"
  chmod +x "$STUB_BIN/fzf"

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"fzf is already installed"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies Linux installation dispatches through the shared package helper.
@test "uses the Linux package manager when fzf is missing" {
  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = $'apt-get update\napt-get install -y fzf' ]
}

# This verifies macOS installation uses Homebrew.
@test "uses Homebrew on macOS" {
  rm -f "$STUB_BIN/apt-get"
  add_package_manager_stub brew

  run env PATH="$STUB_BIN" TEST_UNAME=Darwin CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "brew install fzf" ]
}

# This verifies Windows prefers the exact WinGet package identifier.
@test "uses WinGet on Windows when available" {
  add_package_manager_stub winget

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "winget install --silent --id junegunn.fzf --exact" ]
}

# This verifies Chocolatey is used when WinGet is unavailable.
@test "uses Chocolatey on Windows when WinGet is unavailable" {
  add_package_manager_stub choco

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "choco install -y fzf" ]
}

# This verifies Windows without a supported package manager fails clearly.
@test "fails on Windows without a supported package manager" {
  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no supported package manager found"* ]]
}

# This verifies a package-manager failure is returned to the installer caller.
@test "propagates a WinGet installation failure" {
  add_package_manager_stub winget

  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" \
    PACKAGE_STATUS=1 "$FZF_INSTALLER"

  [ "$status" -ne 0 ]
  [ "$(<"$CALL_LOG")" = "winget install --silent --id junegunn.fzf --exact" ]
}

# This verifies unknown operating systems fail instead of attempting installation.
@test "fails on an unsupported operating system" {
  run env PATH="$STUB_BIN" TEST_UNAME=FreeBSD CALL_LOG="$CALL_LOG" "$FZF_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported OS for fzf installation"* ]]
  [ ! -e "$CALL_LOG" ]
}
