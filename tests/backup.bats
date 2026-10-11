#!/usr/bin/env bats

# Tests for backup and restore using a temporary repository and home directory.

setup() {
  TEST_ROOT="$(mktemp -d)"
  DOTFILES_ROOT="$TEST_ROOT/dotfiles"
  TEST_HOME="$TEST_ROOT/home"
  TEST_CONFIG_HOME="$TEST_ROOT/config-home"
  STUB_BIN="$TEST_ROOT/bin"

  mkdir -p "$DOTFILES_ROOT/backup" "$DOTFILES_ROOT/install" "$DOTFILES_ROOT/config" \
    "$TEST_HOME" "$TEST_CONFIG_HOME" "$STUB_BIN"
  cp "$BATS_TEST_DIRNAME/../backup/backup.sh" "$DOTFILES_ROOT/backup/backup.sh"
  cp "$BATS_TEST_DIRNAME/../backup/restore.sh" "$DOTFILES_ROOT/backup/restore.sh"
  cp "$BATS_TEST_DIRNAME/../install/lib.sh" "$DOTFILES_ROOT/install/lib.sh"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF
  chmod +x "$STUB_BIN/uname"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_backup() {
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_CONFIG_HOME" PATH="$STUB_BIN:$PATH" \
    "$BASH" "$DOTFILES_ROOT/backup/backup.sh"
}

run_restore() {
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_CONFIG_HOME" PATH="$STUB_BIN:$PATH" \
    "$BASH" "$DOTFILES_ROOT/backup/restore.sh"
}

# This verifies manifest backup flags and expansion of both HOME and CONFIG_HOME paths.
@test "backs up eligible HOME and config files and skips backup=no entries" {
  printf 'app\tconfig/home.conf\t$HOME/home.conf\tyes\n' > "$DOTFILES_ROOT/backup/manifest"
  printf 'app\tconfig/ignored.conf\t$HOME/ignored.conf\tno\n' >> "$DOTFILES_ROOT/backup/manifest"
  printf 'app\tconfig/settings.json\t$CONFIG_HOME/app/settings.json\tyes\n' >> "$DOTFILES_ROOT/backup/manifest"
  printf 'home snapshot\n' > "$TEST_HOME/home.conf"
  printf 'do not snapshot\n' > "$TEST_HOME/ignored.conf"
  mkdir -p "$TEST_CONFIG_HOME/app"
  printf 'config snapshot\n' > "$TEST_CONFIG_HOME/app/settings.json"

  run_backup

  [ "$status" -eq 0 ]
  [ "$(<"$DOTFILES_ROOT/config/home.conf")" = "home snapshot" ]
  [ "$(<"$DOTFILES_ROOT/config/settings.json")" = "config snapshot" ]
  [ ! -e "$DOTFILES_ROOT/config/ignored.conf" ]
  [[ "$output" == *"2 file(s) backed up."* ]]
}

# This verifies that manifest comments and blank lines are ignored.
@test "ignores manifest comments and blank lines" {
  {
    printf '# managed files\n'
    printf '\n'
    printf 'app\tconfig/home.conf\t$HOME/home.conf\tyes\n'
  } > "$DOTFILES_ROOT/backup/manifest"
  printf 'home snapshot\n' > "$TEST_HOME/home.conf"

  run_backup

  [ "$status" -eq 0 ]
  [ "$(<"$DOTFILES_ROOT/config/home.conf")" = "home snapshot" ]
  [[ "$output" == *"1 file(s) backed up."* ]]
}

# This verifies that a missing live file is skipped rather than treated as an error.
@test "skips missing live files" {
  printf 'app\tconfig/absent.conf\t$HOME/absent.conf\tyes\n' > "$DOTFILES_ROOT/backup/manifest"

  run_backup

  [ "$status" -eq 0 ]
  [[ "$output" == *"[ skip ] $TEST_HOME/absent.conf (missing)"* ]]
  [[ "$output" == *"0 file(s) backed up."* ]]
}

# This verifies that backup does not copy files that are already identical.
@test "skips unchanged live files" {
  printf 'app\tconfig/same.conf\t$HOME/same.conf\tyes\n' > "$DOTFILES_ROOT/backup/manifest"
  printf 'unchanged config\n' > "$DOTFILES_ROOT/config/same.conf"
  cp "$DOTFILES_ROOT/config/same.conf" "$TEST_HOME/same.conf"

  run_backup

  [ "$status" -eq 0 ]
  [[ "$output" == *"[ same ] config/same.conf"* ]]
  [[ "$output" == *"0 file(s) backed up."* ]]
}

# This verifies that backup does not copy live files already symlinked into the repository.
@test "skips live files symlinked into the repository" {
  printf 'app\tconfig/linked.conf\t$HOME/linked.conf\tyes\n' > "$DOTFILES_ROOT/backup/manifest"
  printf 'linked repository config\n' > "$DOTFILES_ROOT/config/linked.conf"
  if ! ln -s "$DOTFILES_ROOT/config/linked.conf" "$TEST_HOME/linked.conf" ||
     [ ! -L "$TEST_HOME/linked.conf" ]; then
    skip "symlinks are unavailable"
  fi

  run_backup

  [ "$status" -eq 0 ]
  [[ "$output" == *"[ link ] $TEST_HOME/linked.conf"* ]]
  [[ "$output" == *"0 file(s) backed up."* ]]
}

# This verifies that restore backs up conflicting files, expands CONFIG_HOME, and is repeatable.
@test "restores managed configs as symlinks while preserving conflicts" {
  printf 'app\tconfig/home.conf\t$HOME/home.conf\tno\n' > "$DOTFILES_ROOT/backup/manifest"
  printf 'app\tconfig/settings.json\t$CONFIG_HOME/app/settings.json\tyes\n' >> "$DOTFILES_ROOT/backup/manifest"
  printf 'app\tconfig/missing.conf\t$HOME/missing.conf\tno\n' >> "$DOTFILES_ROOT/backup/manifest"
  printf 'repository home config\n' > "$DOTFILES_ROOT/config/home.conf"
  printf 'repository settings\n' > "$DOTFILES_ROOT/config/settings.json"
  printf 'existing user config\n' > "$TEST_HOME/home.conf"

  run_restore

  [ "$status" -eq 0 ]
  if [ -L "$TEST_HOME/home.conf" ]; then
    [ "$TEST_HOME/home.conf" -ef "$DOTFILES_ROOT/config/home.conf" ]
  else
    [ "$(<"$TEST_HOME/home.conf")" = "repository home config" ]
  fi
  [ "$(<"$TEST_HOME/home.conf.backup")" = "existing user config" ]
  if [ -L "$TEST_CONFIG_HOME/app/settings.json" ]; then
    [ "$TEST_CONFIG_HOME/app/settings.json" -ef "$DOTFILES_ROOT/config/settings.json" ]
  else
    [ "$(<"$TEST_CONFIG_HOME/app/settings.json")" = "repository settings" ]
  fi
  [ ! -e "$TEST_HOME/missing.conf" ]

  run_restore

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_HOME/home.conf.backup")" = "existing user config" ]
}

# This verifies that restore creates a managed link when no live file exists yet.
@test "restores an absent destination without a conflict backup" {
  printf 'app\tconfig/home.conf\t$HOME/home.conf\tno\n' > "$DOTFILES_ROOT/backup/manifest"
  printf 'repository home config\n' > "$DOTFILES_ROOT/config/home.conf"

  run_restore

  [ "$status" -eq 0 ]
  if [ -L "$TEST_HOME/home.conf" ]; then
    [ "$TEST_HOME/home.conf" -ef "$DOTFILES_ROOT/config/home.conf" ]
  else
    [ "$(<"$TEST_HOME/home.conf")" = "repository home config" ]
  fi
  [ ! -e "$TEST_HOME/home.conf.backup" ]
}
