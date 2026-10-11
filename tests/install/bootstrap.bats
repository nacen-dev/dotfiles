#!/usr/bin/env bats

# Tests for bootstrap orchestration using a minimal fixture repository.

setup() {
  TEST_ROOT="$(mktemp -d)"
  DOTFILES_ROOT="$TEST_ROOT/dotfiles"
  TEST_HOME="$TEST_ROOT/home"
  STUB_BIN="$TEST_ROOT/bin"
  NEXT_INSTALLER="$TEST_ROOT/next-installer.sh"
  PATH_MARKER="$TEST_ROOT/path-inherited"

  mkdir -p "$DOTFILES_ROOT/install" "$DOTFILES_ROOT/zsh" "$TEST_HOME" "$STUB_BIN"
  cp "$BATS_TEST_DIRNAME/../../install/bootstrap.sh" "$DOTFILES_ROOT/install/bootstrap.sh"
  cp "$BATS_TEST_DIRNAME/../../install/lib.sh" "$DOTFILES_ROOT/install/lib.sh"
  touch "$TEST_HOME/.gitconfig"
  : > "$DOTFILES_ROOT/zsh/zshrc.local.example"

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
exit 0
EOF

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' Linux ;;
  *) exit 1 ;;
esac
EOF

  cat > "$DOTFILES_ROOT/install/installer.sh" <<'EOF'
#!/usr/bin/env bash
set -e
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/bootstrap-path-probe"
chmod +x "$HOME/.local/bin/bootstrap-path-probe"
bash "$NEXT_INSTALLER"
EOF

  cat > "$NEXT_INSTALLER" <<'EOF'
#!/usr/bin/env bash
command -v bootstrap-path-probe >/dev/null
printf 'found\n' > "$PATH_MARKER"
EOF

  chmod +x "$STUB_BIN/curl" "$STUB_BIN/uname" "$DOTFILES_ROOT/install/installer.sh" "$NEXT_INSTALLER"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

# This verifies that later installer processes inherit ~/.local/bin on PATH.
@test "adds local bin to PATH before running application installers" {
  run env HOME="$TEST_HOME" PATH="$STUB_BIN:$PATH" \
    NEXT_INSTALLER="$NEXT_INSTALLER" PATH_MARKER="$PATH_MARKER" \
    "$BASH" "$DOTFILES_ROOT/install/bootstrap.sh"

  [ "$status" -eq 0 ]
  [ "$(<"$PATH_MARKER")" = "found" ]
}

# This verifies that a failing application installer is reported while the
# remaining bootstrap setup steps still run.
@test "reports application failures but still completes setup" {
  cat > "$DOTFILES_ROOT/install/installer.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$DOTFILES_ROOT/install/installer.sh"

  run env HOME="$TEST_HOME" PATH="$STUB_BIN:$PATH" \
    NEXT_INSTALLER="$NEXT_INSTALLER" PATH_MARKER="$PATH_MARKER" \
    "$BASH" "$DOTFILES_ROOT/install/bootstrap.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"one or more application installers failed"* ]]
  [ -f "$TEST_HOME/.zshrc.local" ]
}
