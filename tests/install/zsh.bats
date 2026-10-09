#!/usr/bin/env bats

# Tests for the Zsh application installer. External platform and package
# commands are isolated in a temporary PATH so these tests never install Zsh.

ZSH_INSTALLER="$BATS_TEST_DIRNAME/../../zsh/install.sh"

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
exit "${SUDO_STATUS:-0}"
EOF

  : > "$STUB_BIN/apt-get"
  chmod +x "$STUB_BIN/uname" "$STUB_BIN/sudo" "$STUB_BIN/apt-get"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_pkg_manager_stub() {
  local manager=$1
  cat > "$STUB_BIN/$manager" <<EOF
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >> "\$CALL_LOG"
EOF
  chmod +x "$STUB_BIN/$manager"
}

# This verifies that an available Zsh executable makes the installer a no-op.
@test "skips installation when Zsh is already available" {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/zsh"
  chmod +x "$STUB_BIN/zsh"

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh is already installed"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that Linux installation dispatches to the package manager.
@test "uses the Linux package manager when Zsh is missing" {
  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing zsh."* ]]
  [ "$(<"$CALL_LOG")" = $'apt-get update\napt-get install -y zsh' ]
}

# This verifies that Windows is treated as an unsupported platform for Zsh and is skipped.
@test "skips installation on Windows" {
  run env PATH="$STUB_BIN" TEST_UNAME=MINGW64_NT-10.0 CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Zsh is not supported on Windows"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that unknown operating systems fail instead of attempting installation.
@test "fails on an unsupported operating system" {
  run env PATH="$STUB_BIN" TEST_UNAME=FreeBSD CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported OS for zsh installation"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that macOS installs Zsh through Homebrew.
@test "uses Homebrew on macOS" {
  add_pkg_manager_stub brew

  run env PATH="$STUB_BIN" TEST_UNAME=Darwin CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "brew install zsh" ]
}

# This verifies that macOS without Homebrew fails with an actionable message.
@test "fails on macOS without Homebrew" {
  run env PATH="$STUB_BIN" TEST_UNAME=Darwin CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Homebrew is required"* ]]
  [ ! -e "$CALL_LOG" ]
}

# This verifies that Linux uses dnf when apt is unavailable.
@test "uses dnf when apt is unavailable" {
  rm -f "$STUB_BIN/apt-get"
  add_pkg_manager_stub dnf

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "dnf install -y zsh" ]
}

# This verifies that Linux falls back to pacman when apt and dnf are unavailable.
@test "uses pacman when apt and dnf are unavailable" {
  rm -f "$STUB_BIN/apt-get"
  add_pkg_manager_stub pacman

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "pacman -Sy --noconfirm zsh" ]
}

# This verifies that Linux falls back to zypper when it is the only package manager.
@test "uses zypper when it is the only package manager" {
  rm -f "$STUB_BIN/apt-get"
  add_pkg_manager_stub zypper

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = "zypper install -y zsh" ]
}

# This verifies that Linux without a supported package manager fails clearly.
@test "fails on Linux without a supported package manager" {
  rm -f "$STUB_BIN/apt-get"

  run env PATH="$STUB_BIN" TEST_UNAME=Linux CALL_LOG="$CALL_LOG" "$ZSH_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no supported package manager found"* ]]
  [ ! -e "$CALL_LOG" ]
}
