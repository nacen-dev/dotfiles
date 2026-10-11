#!/usr/bin/env bats

# Tests for fzf's Zsh startup integration. A fake fzf executable avoids
# depending on an installed fzf version or changing the user's shell setup.

ZSHRC="$BATS_TEST_DIRNAME/../../zsh/zshrc.symlink"

setup() {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "Zsh is required to test shell integration"
  fi

  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  FZF_LOG="$TEST_ROOT/fzf.log"
  ZSH_BIN="$(command -v zsh)"
  mkdir -p "$STUB_BIN" "$TEST_HOME"
}

teardown() {
  [ -z "${TEST_ROOT:-}" ] || rm -rf "$TEST_ROOT"
}

add_fzf_stub() {
  cat > "$STUB_BIN/fzf" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FZF_LOG"
if [ "${FZF_STATUS:-0}" -ne 0 ]; then
  printf '%s\n' 'unsupported fzf shell integration' >&2
  exit "$FZF_STATUS"
fi
printf '%s\n' 'FZF_INTEGRATION_LOADED=yes'
EOF
  chmod +x "$STUB_BIN/fzf"
}

run_zshrc() {
  local command=$1
  run env HOME="$TEST_HOME" PATH="$STUB_BIN" FZF_LOG="$FZF_LOG" \
    ZSHRC_PATH="$ZSHRC" "$ZSH_BIN" -f -c "$command"
}

# This verifies a supported fzf initializes Zsh integration from the startup config.
@test "loads fzf shell integration when supported" {
  add_fzf_stub

  run_zshrc 'source "$ZSHRC_PATH"; print -r -- "$FZF_INTEGRATION_LOADED"'

  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]
  [ "$(<"$FZF_LOG")" = "--zsh" ]
}

# This verifies Zsh startup remains quiet when fzf is not installed.
@test "starts without fzf installed" {
  run_zshrc 'source "$ZSHRC_PATH"; print -r -- "started"'

  [ "$status" -eq 0 ]
  [ "$output" = "started" ]
  [ ! -e "$FZF_LOG" ]
}

# This verifies unsupported fzf versions do not interrupt Zsh startup or print errors.
@test "starts quietly when fzf does not support the Zsh integration option" {
  add_fzf_stub

  run env HOME="$TEST_HOME" PATH="$STUB_BIN" FZF_LOG="$FZF_LOG" \
    FZF_STATUS=2 ZSHRC_PATH="$ZSHRC" "$ZSH_BIN" -f -c \
    'source "$ZSHRC_PATH"; print -r -- "started"'

  [ "$status" -eq 0 ]
  [ "$output" = "started" ]
  [ "$(<"$FZF_LOG")" = "--zsh" ]
}
