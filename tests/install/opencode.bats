#!/usr/bin/env bats

# Tests for the OpenCode installer. Network, package managers, and privileged
# commands are stubbed; configuration links are kept inside a temporary home.

OPENCODE_INSTALLER="$BATS_TEST_DIRNAME/../../opencode/install.sh"
OPENCODE_CONFIG="$BATS_TEST_DIRNAME/../../opencode/opencode.jsonc"
OPENCODE_VERSION="1.18.31"
OPENCODE_SHA256="fc3c1b2123f49b6df545a7622e5127d21cd794b15134fc3b66e1ca49f7fb297e"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  CONFIG_HOME="$TEST_ROOT/config"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  INSTALL_LOG="$TEST_ROOT/install.log"
  PACKAGE_LOG="$TEST_ROOT/package.log"
  SUDO_LOG="$TEST_ROOT/sudo.log"
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
printf '%s\n' "$TEST_UNAME"
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$CURL_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'printf "installer %s\\n" "$*" >> "$INSTALL_LOG"' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "$EXPECTED_SHA256" "$1"
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

add_command_stub() {
  local command_name=$1 status_variable=$2
  cat > "$STUB_BIN/$command_name" <<EOF
#!/bin/sh
printf '%s %s\\n' '$command_name' "\$*" >> "\$PACKAGE_LOG"
exit "\${$status_variable:-0}"
EOF
  chmod +x "$STUB_BIN/$command_name"
}

add_opencode_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/opencode"
  chmod +x "$STUB_BIN/opencode"
}

run_opencode() {
  local platform=$1
  shift
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" XDG_CONFIG_HOME="$CONFIG_HOME" \
    APPDATA="$CONFIG_HOME" TMPDIR="$TEMP_DIR" TEST_UNAME="$platform" \
    CURL_LOG="$CURL_LOG" INSTALL_LOG="$INSTALL_LOG" PACKAGE_LOG="$PACKAGE_LOG" \
    SUDO_LOG="$SUDO_LOG" "$@" "$OPENCODE_INSTALLER"
}

# This verifies that an existing OpenCode executable skips installation but still links its config.
@test "skips installation when OpenCode is available and links its config" {
  add_opencode_stub

  run_opencode Linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode is already installed"* ]]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$PACKAGE_LOG" ]
}

# This verifies that Linux uses the pinned, checksum-verified upstream installer when pacman is absent.
@test "runs the pinned installer on Linux when pacman is unavailable" {
  run_opencode Linux EXPECTED_SHA256="$OPENCODE_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://raw.githubusercontent.com/anomalyco/opencode/v$OPENCODE_VERSION/install"* ]]
  [ "$(<"$INSTALL_LOG")" = "installer --version $OPENCODE_VERSION" ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
}

# This verifies that macOS without Homebrew falls back to the pinned upstream installer.
@test "runs the pinned installer on macOS without Homebrew" {
  run_opencode Darwin EXPECTED_SHA256="$OPENCODE_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://raw.githubusercontent.com/anomalyco/opencode/v$OPENCODE_VERSION/install"* ]]
  [ "$(<"$INSTALL_LOG")" = "installer --version $OPENCODE_VERSION" ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
}

# This verifies that Linux uses pacman with elevated privileges when it is available.
@test "uses pacman on Linux when available" {
  add_command_stub pacman PACMAN_STATUS

  run_opencode Linux

  [ "$status" -eq 0 ]
  [ "$(<"$SUDO_LOG")" = "pacman -S --noconfirm opencode" ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that macOS prefers Homebrew over the upstream installer.
@test "uses Homebrew on macOS when available" {
  add_command_stub brew BREW_STATUS

  run_opencode Darwin

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "brew install anomalyco/tap/opencode" ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
}

# This verifies that Windows prefers WinGet and links the global configuration.
@test "uses WinGet on Windows when available" {
  add_command_stub winget WINGET_STATUS

  run_opencode MINGW64_NT-10.0

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = "winget install --silent -e --id SST.opencode --accept-source-agreements --accept-package-agreements" ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
}

# This verifies that a failed WinGet attempt falls back to Chocolatey.
@test "falls back to Chocolatey when WinGet fails" {
  add_command_stub winget WINGET_STATUS
  add_command_stub choco CHOCO_STATUS

  run_opencode MINGW64_NT-10.0 WINGET_STATUS=17

  [ "$status" -eq 0 ]
  [ "$(<"$PACKAGE_LOG")" = $'winget install --silent -e --id SST.opencode --accept-source-agreements --accept-package-agreements\nchoco install -y opencode' ]
  [ "$CONFIG_HOME/opencode/opencode.jsonc" -ef "$OPENCODE_CONFIG" ]
}

# This verifies that Windows without either supported package manager fails without linking config.
@test "fails on Windows when neither package manager is available" {
  run_opencode MINGW64_NT-10.0

  [ "$status" -ne 0 ]
  [[ "$output" == *"Neither WinGet nor Chocolatey is installed"* ]]
  [ ! -L "$CONFIG_HOME/opencode/opencode.jsonc" ]
}

# This verifies that checksum mismatch prevents the downloaded installer from running.
@test "rejects an upstream installer with the wrong checksum" {
  run_opencode Linux EXPECTED_SHA256=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$INSTALL_LOG" ]
  [ ! -L "$CONFIG_HOME/opencode/opencode.jsonc" ]
}
