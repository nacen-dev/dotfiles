#!/usr/bin/env bats

# Tests for shared installation helpers.

setup() {
  TEST_ROOT="$(mktemp -d)"
  SOURCE="$TEST_ROOT/repo/config"
  DEST="$TEST_ROOT/home/config"
  mkdir -p "$TEST_ROOT/repo" "$TEST_ROOT/home"
  printf 'repository config\n' > "$SOURCE"
  source "$BATS_TEST_DIRNAME/../../install/lib.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

make_symlink_unavailable() {
  mkdir -p "$TEST_ROOT/no-symlink-bin"
  cat > "$TEST_ROOT/no-symlink-bin/ln" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$TEST_ROOT/no-symlink-bin/ln"
}

# This verifies that on a filesystem without symlinks the copy fallback is
# recognized on the next run, so it is skipped instead of prompting.
@test "skips an identical copied config when symlinks are unavailable" {
  make_symlink_unavailable
  cp "$SOURCE" "$DEST"

  output="$(PATH="$TEST_ROOT/no-symlink-bin:$PATH" link_file "$SOURCE" "$DEST" </dev/null)"

  [[ "$output" == *"skipped $SOURCE"* ]]
  [ "$(<"$DEST")" = "repository config" ]
}

# This verifies that on symlink-capable platforms an identical regular file is
# still adopted: link_config backs it up and replaces it with a managed symlink.
@test "adopts an identical regular file as a symlink when symlinks are supported" {
  if ! symlinks_supported "$DEST"; then
    skip "real symlinks are unavailable"
  fi
  cp "$SOURCE" "$DEST"

  link_config "$SOURCE" "$DEST" >/dev/null

  [ -L "$DEST" ]
  [ "$DEST" -ef "$SOURCE" ]
  [ "$(<"$DEST.backup")" = "repository config" ]
}

# This verifies that a relative symlink resolving to the source is recognized as managed.
@test "skips a relative symlink to the source without prompting" {
  if ! ln -s ../repo/config "$DEST" || [ ! -L "$DEST" ]; then
    skip "real symlinks are unavailable"
  fi

  output="$(link_file "$SOURCE" "$DEST" </dev/null)"

  [[ "$output" == *"skipped $SOURCE"* ]]
  [ "$(readlink "$DEST")" = "../repo/config" ]
}

# This verifies that a different regular file remains a conflict and can be skipped without being changed.
@test "prompts for a modified destination and preserves it when skipped" {
  printf 'user config\n' > "$DEST"

  output="$(link_file "$SOURCE" "$DEST" <<< 's')"

  [[ "$output" == *"File already exists: $DEST"* ]]
  [[ "$output" == *"skipped $SOURCE"* ]]
  [ "$(<"$DEST")" = "user config" ]
}

# This verifies that even on a platform without symlink support, an unrelated
# symlink with matching contents is not mistaken for a copied fallback file.
@test "prompts for a same-content symlink that points elsewhere" {
  printf 'repository config\n' > "$TEST_ROOT/other"
  if ! ln -s "$TEST_ROOT/other" "$DEST" || [ ! -L "$DEST" ]; then
    skip "real symlinks are unavailable"
  fi
  make_symlink_unavailable

  output="$(PATH="$TEST_ROOT/no-symlink-bin:$PATH" link_file "$SOURCE" "$DEST" <<< 's')"

  [[ "$output" == *"File already exists: $DEST"* ]]
  [[ "$output" == *"skipped $SOURCE"* ]]
  [ "$(readlink "$DEST")" = "$TEST_ROOT/other" ]
}

# This verifies that when symlink creation fails the config is copied into place.
@test "copies the config when symlink creation fails" {
  make_symlink_unavailable

  output="$(PATH="$TEST_ROOT/no-symlink-bin:$PATH" link_file "$SOURCE" "$DEST" </dev/null)"

  [[ "$output" == *"copied $SOURCE to $DEST"* ]]
  [ ! -L "$DEST" ]
  [ "$(<"$DEST")" = "repository config" ]
}

# This verifies that the overwrite prompt replaces the destination with a symlink.
@test "overwrites a modified destination when requested" {
  if ! symlinks_supported "$DEST"; then
    skip "real symlinks are unavailable"
  fi
  printf 'user config\n' > "$DEST"

  output="$(link_file "$SOURCE" "$DEST" <<< 'o')"

  [[ "$output" == *"removed $DEST"* ]]
  [ -L "$DEST" ]
  [ "$DEST" -ef "$SOURCE" ]
}

# This verifies that the backup prompt moves the destination aside and links.
@test "backs up a modified destination when requested" {
  if ! symlinks_supported "$DEST"; then
    skip "real symlinks are unavailable"
  fi
  printf 'user config\n' > "$DEST"

  link_file "$SOURCE" "$DEST" <<< 'b' >/dev/null

  [ -L "$DEST" ]
  [ "$DEST" -ef "$SOURCE" ]
  [ "$(<"$DEST.backup")" = "user config" ]
}

# This verifies that the probe template is created beside the destination, not
# under a potentially different system temporary filesystem.
@test "probes symlink support in the destination parent directory" {
  mkdir -p "$TEST_ROOT/recording-mktemp-bin"
  cat > "$TEST_ROOT/recording-mktemp-bin/mktemp" <<'EOF'
#!/bin/sh
printf '%s\n' "$2" > "$PROBE_LOG"
exec "$REAL_MKTEMP" "$@"
EOF
  chmod +x "$TEST_ROOT/recording-mktemp-bin/mktemp"

  REAL_MKTEMP="$(command -v mktemp)" PROBE_LOG="$TEST_ROOT/probe.log" \
    PATH="$TEST_ROOT/recording-mktemp-bin:$PATH" symlinks_supported "$DEST" || true

  [ "$(<"$TEST_ROOT/probe.log")" = "$TEST_ROOT/home/.dotfiles-symlink-probe.XXXXXX" ]
}

# This verifies that failure to make a probe directory is treated as unknown,
# without using mktemp's failed output to construct a path such as /target.
@test "handles failure to create the symlink probe directory safely" {
  mkdir -p "$TEST_ROOT/failing-mktemp-bin" "$TEST_ROOT/probe-dir"
  cat > "$TEST_ROOT/failing-mktemp-bin/mktemp" <<EOF
#!/bin/sh
printf '%s\\n' '$TEST_ROOT/probe-dir'
exit 1
EOF
  chmod +x "$TEST_ROOT/failing-mktemp-bin/mktemp"
  cp "$SOURCE" "$DEST"

  PATH="$TEST_ROOT/failing-mktemp-bin:$PATH" link_config "$SOURCE" "$DEST" >/dev/null

  [ -L "$DEST" ]
  [ "$DEST" -ef "$SOURCE" ]
  [ "$(<"$DEST.backup")" = "repository config" ]
  [ ! -e "$TEST_ROOT/probe-dir/target" ]
}
