#!/usr/bin/env bats

# Tests for the Docker installer. Docker, downloads, checksum tools, and sudo
# are stubbed so no host Docker installation or privileged command is touched.

DOCKER_INSTALLER="$BATS_TEST_DIRNAME/../../docker/install.sh"
DOCKER_COMMIT="2b32480025b223ebfddae9a3a8bef09027680f53"
DOCKER_SHA256="fefa50ccd50efb42f438b506fc3a88574118f314aaf2a7cd5b6e1ffb1bffcf26"

setup() {
  TEST_ROOT="$(mktemp -d)"
  STUB_BIN="$TEST_ROOT/bin"
  TEMP_DIR="$TEST_ROOT/tmp"
  CURL_LOG="$TEST_ROOT/curl.log"
  SUDO_LOG="$TEST_ROOT/sudo.log"
  DOCKER_LOG="$TEST_ROOT/docker.log"
  mkdir -p "$STUB_BIN" "$TEMP_DIR"

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
    printf '%s\n' 'stub Docker installer' > "$1"
  fi
  shift
done
exit "${CURL_STATUS:-0}"
EOF

  cat > "$STUB_BIN/sha256sum" <<'EOF'
#!/bin/sh
printf '%s  %s\n' "${ACTUAL_SHA256:-$EXPECTED_SHA256}" "$1"
EOF

  cat > "$STUB_BIN/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$SUDO_LOG"
exit "${SUDO_STATUS:-0}"
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/sha256sum" "$STUB_BIN/sudo"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

add_docker_stub() {
  cat > "$STUB_BIN/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$DOCKER_LOG"
exit "${DOCKER_INFO_STATUS:-0}"
EOF
  chmod +x "$STUB_BIN/docker"
}

add_dockerd_stub() {
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/dockerd"
  chmod +x "$STUB_BIN/dockerd"
}

run_docker() {
  local platform=$1
  shift
  run env PATH="$STUB_BIN" TEST_UNAME="$platform" TMPDIR="$TEMP_DIR" \
    CURL_LOG="$CURL_LOG" SUDO_LOG="$SUDO_LOG" DOCKER_LOG="$DOCKER_LOG" \
    "$@" "$DOCKER_INSTALLER"
}

# This verifies that Docker installation is skipped on macOS and does not download anything.
@test "skips installation on macOS" {
  run_docker Darwin

  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker installation is skipped on macos"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that Docker installation is skipped on Windows and does not download anything.
@test "skips installation on Windows" {
  run_docker MINGW64_NT-10.0

  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker installation is skipped on windows"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that a reachable Docker Engine makes the installer a no-op.
@test "skips installation when Docker Engine is reachable" {
  add_docker_stub

  run_docker Linux

  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Engine is reachable"* ]]
  [ "$(<"$DOCKER_LOG")" = "info" ]
  [ ! -e "$CURL_LOG" ]
}

# This verifies that an installed but unreachable dockerd produces a warning and skips reinstalling.
@test "warns and skips when dockerd exists but Docker is unreachable" {
  add_docker_stub
  add_dockerd_stub

  run_docker Linux DOCKER_INFO_STATUS=1

  [ "$status" -eq 0 ]
  [[ "$output" == *"dockerd is installed but Docker Engine is not reachable"* ]]
  [ ! -e "$CURL_LOG" ]
  [ ! -e "$SUDO_LOG" ]
}

# This verifies that Linux downloads the pinned installer, checks its digest, and passes it to sudo sh.
@test "runs the pinned installer when Docker is absent" {
  run_docker Linux EXPECTED_SHA256="$DOCKER_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://raw.githubusercontent.com/docker/docker-install/$DOCKER_COMMIT/install.sh"* ]]
  [[ "$(<"$SUDO_LOG")" == "sh "* ]]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that an unreachable Docker command without dockerd proceeds to installation.
@test "reinstalls when Docker is unreachable and dockerd is absent" {
  add_docker_stub

  run_docker Linux DOCKER_INFO_STATUS=1 EXPECTED_SHA256="$DOCKER_SHA256"

  [ "$status" -eq 0 ]
  [[ "$(<"$CURL_LOG")" == *"https://raw.githubusercontent.com/docker/docker-install/$DOCKER_COMMIT/install.sh"* ]]
  [[ "$(<"$SUDO_LOG")" == "sh "* ]]
}

# This verifies that a checksum mismatch prevents invoking the installer and cleans up its temporary file.
@test "rejects a Docker installer with the wrong checksum" {
  run_docker Linux EXPECTED_SHA256="$DOCKER_SHA256" ACTUAL_SHA256=invalid

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$SUDO_LOG" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that a failed sudo installer is reported and the temporary file is removed.
@test "propagates a sudo installer failure and cleans up" {
  run_docker Linux EXPECTED_SHA256="$DOCKER_SHA256" SUDO_STATUS=31

  [ "$status" -eq 31 ]
  [ -n "$(<"$SUDO_LOG")" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that download failures are returned without invoking sudo and still clean up.
@test "propagates a download failure and cleans up" {
  run_docker Linux CURL_STATUS=22

  [ "$status" -eq 22 ]
  [ ! -e "$SUDO_LOG" ]
  [ -z "$(compgen -G "$TEMP_DIR/*")" ]
}

# This verifies that unknown operating systems fail without attempting a download.
@test "fails on an unsupported operating system" {
  run_docker FreeBSD

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported OS for Docker"* ]]
  [ ! -e "$CURL_LOG" ]
}
