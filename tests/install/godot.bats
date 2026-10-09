#!/usr/bin/env bats

# Tests for the Godot installer. Downloads and archive extraction are stubbed,
# and all artifacts, launchers, and markers live in a temporary home/data tree.

GODOT_INSTALLER="$BATS_TEST_DIRNAME/../../godot/install.sh"
GODOT_VERSION="4.7.2"
GODOT_SHA512="cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEST_HOME="$TEST_ROOT/home"
  DATA_HOME="$TEST_ROOT/data"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  UNZIP_LOG="$TEST_ROOT/unzip.log"
  INSTALL_LOG="$TEST_ROOT/install.log"
  DITTO_LOG="$TEST_ROOT/ditto.log"
  mkdir -p "$STUB_BIN" "$TEST_HOME" "$DATA_HOME" "$TEMP_DIR"

  ln -s "$BASH" "$STUB_BIN/bash"
  ln -s "$(command -v dirname)" "$STUB_BIN/dirname"
  ln -s "$(command -v awk)" "$STUB_BIN/awk"
  ln -s "$(command -v chmod)" "$STUB_BIN/chmod"
  ln -s "$(command -v cp)" "$STUB_BIN/cp"
  ln -s "$(command -v ln)" "$STUB_BIN/ln"
  ln -s "$(command -v mkdir)" "$STUB_BIN/mkdir"
  ln -s "$(command -v mktemp)" "$STUB_BIN/mktemp"
  ln -s "$(command -v readlink)" "$STUB_BIN/readlink"
  ln -s "$(command -v rm)" "$STUB_BIN/rm"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "$TEST_UNAME" ;;
  -m) printf '%s\n' "$TEST_ARCH" ;;
  *) exit 1 ;;
esac
EOF

  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
has_output=false
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    printf '%s\n' 'stub Godot archive' > "$1"
    has_output=true
  fi
  shift
done
if [ "$has_output" = false ]; then
  printf '%s  %s\n' "$EXPECTED_SHA512" "$EXPECTED_ARCHIVE"
fi
EOF

  cat > "$STUB_BIN/sha512sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "${ACTUAL_SHA512:-$EXPECTED_SHA512}" "$1"
EOF

  cat > "$STUB_BIN/unzip" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$UNZIP_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-d" ]; then
    shift
    dest=$1
  fi
  shift
done
if [ "$TEST_GODOT_OS" = macos ]; then
  mkdir -p "$dest/Godot.app/Contents/MacOS"
  printf '%s\n' 'fake Godot app' > "$dest/Godot.app/Contents/MacOS/Godot"
  chmod +x "$dest/Godot.app/Contents/MacOS/Godot"
else
  mkdir -p "$dest"
  printf '%s\n' 'fake Godot executable' > "$dest/$TEST_GODOT_EXECUTABLE"
  chmod +x "$dest/$TEST_GODOT_EXECUTABLE"
fi
EOF

  cat > "$STUB_BIN/install" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$INSTALL_LOG"
printf '%s\n' 'fake Godot executable' > "$4"
chmod +x "$4"
EOF

  cat > "$STUB_BIN/ditto" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$DITTO_LOG"
mkdir -p "$2/Contents/MacOS"
printf '%s\n' 'fake Godot executable' > "$2/Contents/MacOS/Godot"
chmod +x "$2/Contents/MacOS/Godot"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha512sum" \
    "$STUB_BIN/unzip" "$STUB_BIN/install" "$STUB_BIN/ditto"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_godot_command_stub() {
  local command_name=$1
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/$command_name"
  chmod +x "$STUB_BIN/$command_name"
}

run_godot() {
  local os=$1 arch=$2 godot_os=$3 executable=$4 archive=$5
  shift 5
  run env PATH="$STUB_BIN" HOME="$TEST_HOME" XDG_DATA_HOME="$DATA_HOME" \
    TMPDIR="$TEMP_DIR" TEST_UNAME="$os" TEST_ARCH="$arch" \
    TEST_GODOT_OS="$godot_os" TEST_GODOT_EXECUTABLE="$executable" \
    EXPECTED_ARCHIVE="$archive" EXPECTED_SHA512="$GODOT_SHA512" \
    CURL_LOG="$CURL_LOG" UNZIP_LOG="$UNZIP_LOG" INSTALL_LOG="$INSTALL_LOG" \
    DITTO_LOG="$DITTO_LOG" "$@" "$GODOT_INSTALLER"
}

# This verifies that Linux x86_64 selects the expected artifact and creates a managed launcher symlink.
@test "installs the Linux x86_64 artifact and links the launcher" {
  local archive="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  local executable="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/godot"

  run_godot Linux x86_64 linux "$executable" "$archive"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"slug=linux.x86_64.zip&platform=linux.64"* ]]
  [ -x "$artifact" ]
  [ -L "$TEST_HOME/.local/bin/godot" ]
  [ "$(readlink "$TEST_HOME/.local/bin/godot")" = "$artifact" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that Linux ARM64 chooses the matching official archive and executable name.
@test "selects the Linux ARM64 artifact" {
  local archive="Godot_v${GODOT_VERSION}-stable_linux.arm64.zip"
  local executable="Godot_v${GODOT_VERSION}-stable_linux.arm64"

  run_godot Linux aarch64 linux "$executable" "$archive"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"slug=linux.arm64.zip&platform=linux.arm64"* ]]
  [ -x "$DATA_HOME/godot/$GODOT_VERSION/godot" ]
}

# This verifies that macOS downloads the universal app and installs its executable with ditto.
@test "installs the macOS universal app" {
  local archive="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/Godot.app/Contents/MacOS/Godot"

  run_godot Darwin arm64 macos unused "$archive"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"slug=macos.universal.zip&platform=macos.universal"* ]]
  [ -x "$artifact" ]
  [ -n "$(<"$DITTO_LOG")" ]
  [ -L "$TEST_HOME/.local/bin/godot" ]
}

# This verifies that Windows installs the x64 executable, launcher copy, and version marker.
@test "installs the Windows executable and records its managed version" {
  local archive="Godot_v${GODOT_VERSION}-stable_win64.exe.zip"
  local executable="Godot_v${GODOT_VERSION}-stable_win64.exe"
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/godot.exe"
  local launcher="$TEST_HOME/.local/bin/godot.exe"

  run_godot MINGW64_NT-10.0 x86_64 windows "$executable" "$archive"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"slug=win64.exe.zip&platform=windows.64"* ]]
  [ -f "$artifact" ]
  [ -f "$launcher" ]
  [ "$(<"$TEST_HOME/.local/bin/.godot-managed-version")" = "$GODOT_VERSION" ]
}

# This verifies that an existing Godot command skips download and extraction.
@test "skips installation when a Godot command is available" {
  add_godot_command_stub godot

  run_godot Linux x86_64 linux "Godot_v${GODOT_VERSION}-stable_linux.x86_64" \
    "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Godot is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$UNZIP_LOG" ]
}

# This verifies that an existing executable artifact under the data directory is treated as installed.
@test "skips download when the versioned Linux artifact already exists" {
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/godot"
  mkdir -p "$(dirname "$artifact")"
  printf '%s\n' 'existing Godot' > "$artifact"
  chmod +x "$artifact"

  run_godot Linux x86_64 linux "Godot_v${GODOT_VERSION}-stable_linux.x86_64" \
    "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Godot $GODOT_VERSION is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that a checksum mismatch blocks extraction and removes the temporary download directory.
@test "rejects an archive with the wrong checksum and cleans temporary files" {
  run_godot Linux x86_64 linux "Godot_v${GODOT_VERSION}-stable_linux.x86_64" \
    "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" ACTUAL_SHA512=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$UNZIP_LOG" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that an unsupported Linux architecture fails before any download.
@test "fails before downloading on an unsupported Linux architecture" {
  run_godot Linux riscv64 linux unused unused

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported architecture for Godot: riscv64"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that the installer reports a missing unzip dependency before downloading.
@test "fails when unzip is unavailable" {
  rm "$STUB_BIN/unzip"

  run_godot Linux x86_64 linux "Godot_v${GODOT_VERSION}-stable_linux.x86_64" \
    "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unzip is required to install Godot"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that an unrelated existing launcher file is preserved after installation.
@test "preserves an unmanaged Linux launcher" {
  local launcher="$TEST_HOME/.local/bin/godot"
  local archive="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  local executable="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
  mkdir -p "$(dirname "$launcher")"
  printf '%s\n' 'user launcher' > "$launcher"

  run_godot Linux x86_64 linux "$executable" "$archive"

  [ "$status" -eq 0 ]
  [ ! -L "$launcher" ]
  [ "$(<"$launcher")" = "user launcher" ]
  [[ "$output" == *"already exists; leaving it untouched"* ]]
}

# This verifies that an existing symlink inside Godot's managed data root is updated to the current artifact.
@test "updates a launcher symlink managed by Godot" {
  local launcher="$TEST_HOME/.local/bin/godot"
  local archive="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  local executable="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
  mkdir -p "$(dirname "$launcher")" "$DATA_HOME/godot/old"
  ln -s "$DATA_HOME/godot/old/godot" "$launcher"

  run_godot Linux x86_64 linux "$executable" "$archive"

  [ "$status" -eq 0 ]
  [ "$(readlink "$launcher")" = "$DATA_HOME/godot/$GODOT_VERSION/godot" ]
}

# This verifies that a current Windows artifact and matching marker make installation idempotent.
@test "skips a current managed Windows installation" {
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/godot.exe"
  local launcher="$TEST_HOME/.local/bin/godot.exe"
  mkdir -p "$(dirname "$artifact")" "$(dirname "$launcher")"
  printf '%s\n' 'Godot executable' > "$artifact"
  printf '%s\n' 'Godot launcher' > "$launcher"
  printf '%s\n' "$GODOT_VERSION" > "$TEST_HOME/.local/bin/.godot-managed-version"

  run_godot MINGW64_NT-10.0 x86_64 windows unused unused

  [ "$status" -eq 0 ]
  [[ "$output" == *"Godot $GODOT_VERSION is already installed"* ]]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that a stale marker causes the managed Windows launcher to be updated.
@test "updates a Windows launcher with a stale managed version marker" {
  local artifact="$DATA_HOME/godot/$GODOT_VERSION/godot.exe"
  local launcher="$TEST_HOME/.local/bin/godot.exe"
  mkdir -p "$(dirname "$artifact")" "$(dirname "$launcher")"
  printf '%s\n' 'current artifact' > "$artifact"
  printf '%s\n' 'old launcher' > "$launcher"
  printf '%s\n' '4.0.0' > "$TEST_HOME/.local/bin/.godot-managed-version"

  run_godot MINGW64_NT-10.0 x86_64 windows unused unused

  [ "$status" -eq 0 ]
  [ "$(<"$launcher")" = "current artifact" ]
  [ "$(<"$TEST_HOME/.local/bin/.godot-managed-version")" = "$GODOT_VERSION" ]
  [ ! -e "$CURL_LOG" ]
}
