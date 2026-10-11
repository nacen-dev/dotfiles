#!/usr/bin/env bats

# Tests for the installer runner using a minimal fixture repository.

setup() {
  TEST_ROOT="$(mktemp -d)"
  DOTFILES_ROOT="$TEST_ROOT/dotfiles"
  INSTALL_LOG="$TEST_ROOT/install.log"
  mkdir -p "$DOTFILES_ROOT/install"
  cp "$BATS_TEST_DIRNAME/../../install/installer.sh" "$DOTFILES_ROOT/install/installer.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_installer() {
  local name=$1 status=${2:-0}
  mkdir -p "$DOTFILES_ROOT/$name"
  cat > "$DOTFILES_ROOT/$name/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' '$name' >> "\$INSTALL_LOG"
exit $status
EOF
  chmod +x "$DOTFILES_ROOT/$name/install.sh"
}

# This verifies that Zsh runs before the other installers, regardless of alphabetical order.
@test "runs Zsh first and then installers in alphabetical order" {
  add_installer zsh
  add_installer alpha
  add_installer beta

  run env INSTALL_LOG="$INSTALL_LOG" "$BASH" "$DOTFILES_ROOT/install/installer.sh"

  [ "$status" -eq 0 ]
  [ "$(<"$INSTALL_LOG")" = $'zsh\nalpha\nbeta' ]
}

# This verifies that failures are collected while remaining installers still run.
@test "continues after failures and reports all failed installers" {
  add_installer zsh
  add_installer alpha 1
  add_installer beta 1
  add_installer gamma

  run env INSTALL_LOG="$INSTALL_LOG" "$BASH" "$DOTFILES_ROOT/install/installer.sh"

  [ "$status" -eq 1 ]
  [ "$(<"$INSTALL_LOG")" = $'zsh\nalpha\nbeta\ngamma' ]
  [[ "$output" == *"2 installer(s) failed"* ]]
  [[ "$output" == *"./alpha/install.sh"* ]]
  [[ "$output" == *"./beta/install.sh"* ]]
}

# This verifies that a repository with no installers succeeds quietly.
@test "succeeds when there are no installers" {
  run env INSTALL_LOG="$INSTALL_LOG" "$BASH" "$DOTFILES_ROOT/install/installer.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$INSTALL_LOG" ]
}

# This verifies that installers under .git are pruned and never executed.
@test "ignores installers inside the .git directory" {
  mkdir -p "$DOTFILES_ROOT/.git/hooks"
  cat > "$DOTFILES_ROOT/.git/hooks/install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'git-hook\n' >> "$INSTALL_LOG"
exit 0
EOF
  add_installer alpha

  run env INSTALL_LOG="$INSTALL_LOG" "$BASH" "$DOTFILES_ROOT/install/installer.sh"

  [ "$status" -eq 0 ]
  [ "$(<"$INSTALL_LOG")" = "alpha" ]
}
