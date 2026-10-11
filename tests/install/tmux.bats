#!/usr/bin/env bats

# Tests for the tmux installer. Platform and package commands are stubbed so
# these tests never install software.

TMUX_INSTALLER="$BATS_TEST_DIRNAME/../../tmux/install.sh"
TMUX_CONFIG="$BATS_TEST_DIRNAME/../../tmux/tmux.conf.symlink"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  CALL_LOG="$TEST_ROOT/calls.log"
  TMUX_SOCKET="$TEST_ROOT/tmux.sock"
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
  if [ -S "${TMUX_SOCKET:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux -S "$TMUX_SOCKET" kill-server >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}

add_package_manager_stub() {
  local manager=$1
  cat > "$STUB_BIN/$manager" <<EOF
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >> "\$CALL_LOG"
EOF
  chmod +x "$STUB_BIN/$manager"
}

# This verifies that an available tmux executable makes the installer a no-op.
@test "skips installation when tmux is already available" {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/tmux"
  chmod +x "$STUB_BIN/tmux"

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$TMUX_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux is already installed"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that Linux installation dispatches through the shared package helper.
@test "uses the Linux package manager when tmux is missing" {
  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$TMUX_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing tmux."* ]]
  [ "$(<"$CALL_LOG")" = $'apt-get update\napt-get install -y tmux' ]
}

# This verifies that macOS installation uses Homebrew.
@test "uses Homebrew on macOS" {
  rm -f "$STUB_BIN/apt-get"
  add_package_manager_stub brew

  run env PATH="$STUB_BIN" TEST_UNAME=Darwin CALL_LOG="$CALL_LOG" "$TMUX_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "brew install tmux" ]
}

# This verifies that tmux is skipped on Windows Git Bash.
@test "skips installation on Windows" {
  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" "$TMUX_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux is not supported in Windows Git Bash"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that unknown operating systems fail instead of attempting installation.
@test "fails on an unsupported operating system" {
  run env PATH="$STUB_BIN" TEST_UNAME=FreeBSD CALL_LOG="$CALL_LOG" "$TMUX_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported OS for tmux installation"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies the config loads and sets session-scoped window renumbering.
@test "loads the tmux config and enables window renumbering" {
  if ! command -v tmux >/dev/null 2>&1; then
    skip "tmux is required to validate its config"
  fi

  run tmux -f "$TMUX_CONFIG" -S "$TMUX_SOCKET" new-session -d

  [ "$status" -eq 0 ]
  run tmux -S "$TMUX_SOCKET" show-option -gqv renumber-windows

  [ "$status" -eq 0 ]
  [ "$output" = "on" ]
}
