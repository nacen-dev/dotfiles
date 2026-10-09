#!/usr/bin/env bats

# Tests for the Python installer. uv installation and invocation are stubbed,
# and all files are contained in a temporary home directory.

PYTHON_INSTALLER="$BATS_TEST_DIRNAME/../../python/install.sh"
UV_INSTALLER_SHA256="716a1d6844740756c68770fcec2f79c2013fb9b03869a113f61e15f6f482a6a1"
UV_VERSION="0.12.15"
PYTHON_VERSION="3.14"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  SH_LOG="$TEST_ROOT/sh.log"
  UV_LOG="$TEST_ROOT/uv.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
  ln -s "$(command -v chmod)" "$STUB_BIN/chmod"
  ln -s "$(command -v mkdir)" "$STUB_BIN/mkdir"
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
    printf '%s\n' 'stub uv installer' > "$1"
  fi
  shift
done
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "$EXPECTED_SHA256" "$1"
EOF

  cat > "$STUB_BIN/sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$SH_LOG"
mkdir -p "$HOME/.local/bin"
printf '%s\n' '#!/bin/sh' \
  'printf "%s\\n" "$*" > "$UV_LOG"' \
  'exit "${UV_STATUS:-0}"' > "$HOME/.local/bin/uv"
chmod +x "$HOME/.local/bin/uv"
exit "${SH_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum" "$STUB_BIN/sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_python3_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/python3"
  chmod +x "$STUB_BIN/python3"
}

add_uv_stub() {
  printf '%s\n' '#!/bin/sh' \
    'printf "%s\\n" "$*" > "$UV_LOG"' \
    'exit "${UV_STATUS:-0}"' > "$STUB_BIN/uv"
  chmod +x "$STUB_BIN/uv"
}

run_python() {
  local platform=$1
  shift
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" TMPDIR="$TEMP_DIR" \
    TEST_UNAME="$platform" CURL_LOG="$CURL_LOG" SH_LOG="$SH_LOG" \
    UV_LOG="$UV_LOG" "$@" "$PYTHON_INSTALLER"
}

# This verifies that an existing python3 command skips uv and Python installation.
@test "skips installation when python3 is already available" {
  add_python3_stub

  run_python Linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Python is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$UV_LOG" ]
}

# This verifies that an available uv receives the pinned default Python version.
@test "installs the pinned Python version with existing uv" {
  add_uv_stub

  run_python Linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing Python $PYTHON_VERSION (default)"* ]]
  [ "$(<"$UV_LOG")" = "python install $PYTHON_VERSION --default" ]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that missing uv is installed first, then used to install Python.
@test "installs uv before installing Python when uv is missing" {
  run_python Linux EXPECTED_SHA256="$UV_INSTALLER_SHA256"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uv is required to manage Python"* ]]
  [[ "$output" == *"Installing Python $PYTHON_VERSION (default)"* ]]
  [[ "$(<"$CURL_LOG")" == *"https://astral.sh/uv/$UV_VERSION/install.sh"* ]]
  [ -n "$(<"$SH_LOG")" ]
  [ "$(<"$UV_LOG")" = "python install $PYTHON_VERSION --default" ]
}

# This verifies that a failing uv Python-install command propagates its exit status.
@test "propagates a Python installation failure from uv" {
  add_uv_stub

  run_python Linux UV_STATUS=29

  [ "$status" -eq 29 ]
  [ "$(<"$UV_LOG")" = "python install $PYTHON_VERSION --default" ]
}

# This verifies that a failure in the uv bootstrap stops before installing Python.
@test "fails when the uv bootstrap installer fails" {
  run_python Linux EXPECTED_SHA256="$UV_INSTALLER_SHA256" SH_STATUS=9

  [ "$status" -eq 9 ]
  [ ! -e "$UV_LOG" ]
}
