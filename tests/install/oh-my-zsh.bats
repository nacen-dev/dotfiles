#!/usr/bin/env bats

# Tests for the Oh My Zsh installer. Network access and installer execution
# are replaced with stubs so these tests never download or install software.

OH_MY_ZSH_INSTALLER="$BATS_TEST_DIRNAME/../../oh-my-zsh/install.sh"
OH_MY_ZSH_COMMIT="0ee67f042872d1dfab74270c31867771ca35aef4"
OH_MY_ZSH_SHA256="5574b96e94dbcb769f0d1592fa83aeb6ca2caf41c6ae5d76fcc7f04c524b4f55"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  CURL_LOG="$TEST_ROOT/curl.log"
  SHA256_LOG="$TEST_ROOT/sha256.log"
  SH_LOG="$TEST_ROOT/sh.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME"

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
    printf '%s\n' 'stub installer' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$SHA256_LOG"
printf '%s  %s\n' "${ACTUAL_SHA256:-$EXPECTED_SHA256}" "$1"
EOF

  cat > "$STUB_BIN/sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$SH_LOG"
exit "${SH_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum" "$STUB_BIN/sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_zsh_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/zsh"
  chmod +x "$STUB_BIN/zsh"
}

# This verifies that Windows skips Oh My Zsh without attempting a download.
@test "skips installation on Windows" {
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TEST_UNAME=MINGW64_NT-10.0 \
    CURL_LOG="$CURL_LOG" SHA256_LOG="$SHA256_LOG" SH_LOG="$SH_LOG" \
    "$OH_MY_ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping Oh My Zsh because zsh is unavailable"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that Oh My Zsh is skipped on Unix when Zsh itself is unavailable.
@test "skips installation when Zsh is unavailable" {
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TEST_UNAME=Linux \
    CURL_LOG="$CURL_LOG" SHA256_LOG="$SHA256_LOG" SH_LOG="$SH_LOG" \
    "$OH_MY_ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping Oh My Zsh because zsh is unavailable"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that an existing Oh My Zsh directory prevents downloads and reinstalling.
@test "skips installation when Oh My Zsh is already installed" {
  add_zsh_stub
  mkdir -p "$TEST_HOME/.oh-my-zsh"

  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TEST_UNAME=Linux \
    CURL_LOG="$CURL_LOG" SHA256_LOG="$SHA256_LOG" SH_LOG="$SH_LOG" \
    "$OH_MY_ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that a fresh install uses the pinned script and preserves an existing .zshrc.
@test "runs the pinned installer and keeps an existing zshrc" {
  add_zsh_stub
  printf '%s\n' 'user zsh configuration' > "$TEST_HOME/.zshrc"

  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TEST_UNAME=Linux \
    CURL_LOG="$CURL_LOG" SHA256_LOG="$SHA256_LOG" SH_LOG="$SH_LOG" \
    EXPECTED_SHA256="$OH_MY_ZSH_SHA256" "$OH_MY_ZSH_INSTALLER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping it and skipping the Oh My Zsh .zshrc setup"* ]]
  [[ "$(<"$CURL_LOG")" == *"https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/$OH_MY_ZSH_COMMIT/tools/install.sh"* ]]
  [ "$(<"$SHA256_LOG")" != "" ]
  [[ "$(<"$SH_LOG")" == *" --unattended --keep-zshrc" ]]
  [ "$(<"$TEST_HOME/.zshrc")" = "user zsh configuration" ]
}

# This verifies that a downloaded installer with the wrong checksum is rejected before execution.
@test "rejects a downloaded installer with the wrong checksum" {
  add_zsh_stub

  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TEST_UNAME=Linux \
    CURL_LOG="$CURL_LOG" SHA256_LOG="$SHA256_LOG" SH_LOG="$SH_LOG" \
    EXPECTED_SHA256="$OH_MY_ZSH_SHA256" ACTUAL_SHA256=invalid \
    "$OH_MY_ZSH_INSTALLER"

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$SH_LOG" ]
}
