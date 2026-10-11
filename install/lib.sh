#!/usr/bin/env bash
#
# Shared helpers for bootstrap.sh and application installers.
# Source this file (do not execute it):
#   source "$(dirname "$0")/../install/lib.sh"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$LIB_DIR")"

info () {
  printf "  [ \033[00;34m..\033[0m ] %s" "$1"
}

user () {
  printf "\r  [ \033[0;33m?\033[0m ] %s " "$1"
}

success () {
  printf "\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n" "$1"
}

fail () {
  printf "\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n" "$1"
  echo ''
  exit 1
}

detect_os () {
  case "$(uname -s)" in
    Darwin)               OS=macos ;;
    Linux)                OS=linux ;;
    MINGW*|MSYS*|CYGWIN*) OS=windows ;;
    *)                    OS=unknown ;;
  esac
}

pkg_install () {
  case "$OS" in
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y "$@"
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@"
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm "$@"
      elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$@"
      else
        fail "no supported package manager found"
      fi
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install "$@"
      else
        fail "Homebrew is required (https://brew.sh)"
      fi
      ;;
    windows)
      if command -v winget >/dev/null 2>&1; then
        winget install --silent "$@"
      elif command -v choco >/dev/null 2>&1; then
        choco install -y "$@"
      else
        fail "no supported package manager found"
      fi
      ;;
    *)
      fail "unsupported OS"
      ;;
  esac
}

git_credential_helper () {
  case "$OS" in
    macos)   echo osxkeychain ;;
    windows) echo manager ;;
    *)       if command -v secret-tool >/dev/null 2>&1; then echo libsecret; else echo cache; fi ;;
  esac
}

# Directory that holds per-application configuration.
config_home () {
  case "$OS" in
    windows) printf '%s' "${APPDATA:-$HOME/AppData/Roaming}" ;;
    *)       printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
  esac
}

# Add the dotfiles user binary directory to the persistent Windows user PATH.
add_local_bin_to_windows_path () {
  [ "$OS" = windows ] || return 0

  if ! command -v powershell.exe >/dev/null 2>&1 || ! command -v cygpath >/dev/null 2>&1; then
    echo "warning: unable to update Windows PATH; add $(cygpath -w "$HOME/.local/bin" 2>/dev/null || printf '%s' "$HOME/.local/bin") manually." >&2
    return 0
  fi

  local bin_dir
  bin_dir="$(cygpath -w "$HOME/.local/bin")"
  if MSYS_NO_PATHCONV=1 DOTFILES_LOCAL_BIN="$bin_dir" powershell.exe -NoProfile -NonInteractive -Command '
try {
  $bin = $env:DOTFILES_LOCAL_BIN.TrimEnd([char]92)
  $userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
  $present = $false
  if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    foreach ($entry in ($userPath -split ";")) {
      if ($entry.TrimEnd([char]92) -ieq $bin) { $present = $true; break }
    }
  }
  if (-not $present) {
    if ([string]::IsNullOrWhiteSpace($userPath)) { $userPath = $bin }
    else { $userPath = "$userPath;$bin" }
    [Environment]::SetEnvironmentVariable("Path", $userPath, [EnvironmentVariableTarget]::User)
  }
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
exit 0
'; then
    success "Windows user PATH includes $bin_dir (open a new Git Bash session)"
  else
    echo "warning: unable to update Windows PATH; add $bin_dir manually." >&2
  fi
}

# Verify the SHA256 of a file (sha256sum on Linux, shasum on macOS).
sha256_verify () {
  local file=$1 expected=$2 actual=
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    fail "no sha256 checksum tool found"
  fi
  [ "$actual" = "$expected" ] || fail "checksum mismatch for $file"
}

# Verify the SHA512 of a file (sha512sum on Linux, shasum on macOS).
sha512_verify () {
  local file=$1 expected=$2 actual=
  if command -v sha512sum >/dev/null 2>&1; then
    actual="$(sha512sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 512 "$file" | awk '{print $1}')"
  else
    fail "no sha512 checksum tool found"
  fi
  [ "$actual" = "$expected" ] || fail "checksum mismatch for $file"
}

# Download a pinned installer, verify its checksum, then run it.
# Usage: fetch_run <url> <sha256> <shell> [args...]
fetch_run () {
  local url=$1 sha=$2 shell=$3; shift 3
  local tmp status=0
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "$url"
  sha256_verify "$tmp" "$sha"
  "$shell" "$tmp" "$@" || status=$?
  rm -f "$tmp"
  return "$status"
}

# Expand the variables allowed inside backup/manifest paths, without eval.
expand_vars () {
  local s=$1
  s=${s//\$HOME/$HOME}
  s=${s//\$CONFIG_HOME/$CONFIG_HOME}
  printf '%s' "$s"
}

# Whether the destination's filesystem allows creating real symlinks.
#
# link_file falls back to copying when it cannot create a symlink, and on a
# later run that copied destination is a plain file that should be recognized as
# already deployed. That recognition is only safe where symlinks are genuinely
# unavailable, because on Linux/macOS an identical regular file should still be
# treated as a conflict and adopted as a managed symlink.
#
# Some Windows (Git Bash) setups make `ln -s` "succeed" by creating a copy
# instead of a symlink, so `[ -L ]` confirms a real symlink was produced. The
# probe is made in the destination's parent directory because symlink support
# can differ between filesystems.
#
# If the probe cannot be created, support is treated as unknown and this helper
# returns success. That disables the content-based skip: it is safer to handle
# an identical regular file as a conflict than to claim it is a managed copy
# without having confirmed that symlinks are unavailable.
symlinks_supported () {
  local destination=$1 parent probe_dir probe_target supported=true
  parent="$(dirname "$destination")"

  if ! probe_dir="$(mktemp -d "$parent/.dotfiles-symlink-probe.XXXXXX" 2>/dev/null)"; then
    return 0
  fi

  probe_target="$probe_dir/target"
  if ! : > "$probe_target"; then
    rm -rf "$probe_dir" >/dev/null 2>&1 || true
    return 0
  fi

  if ! ln -s "$probe_target" "$probe_dir/probe" 2>/dev/null ||
     [ ! -L "$probe_dir/probe" ]; then
    supported=false
  fi

  rm -rf "$probe_dir" >/dev/null 2>&1 || true
  [ "$supported" = true ]
}

# Link a single file, prompting if the destination already exists.
# Uses (dynamically scoped) overwrite_all / backup_all / skip_all when set.
link_file () {
  local src=$1 dst=$2
  local overwrite= backup= skip=
  local action=

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local currentSrc
    currentSrc="$(readlink "$dst" 2>/dev/null || true)"

    # Treat the destination as already deployed when it is provably the managed
    # source: an exact symlink target, or `-ef` (both paths resolve to the same
    # inode, e.g. a relative symlink spelled differently).
    #
    # When symlinks are unavailable (see symlinks_supported), an earlier run may
    # have fallen back to copying the config, so a regular file whose contents
    # match the source is the deployed config and is skipped. `[ ! -L "$dst" ]`
    # excludes symlink destinations (`-f` follows symlinks), while the `-f`
    # checks require file paths and `cmp -s` compares their contents. This check
    # is gated on symlinks being unavailable: on a platform that can create
    # symlinks, an identical regular file is still a conflict and should be
    # adopted (backed up and linked) rather than silently skipped.
    if [ "$currentSrc" = "$src" ] || [ "$dst" -ef "$src" ] ||
       { ! symlinks_supported "$dst" && [ ! -L "$dst" ] && [ -f "$dst" ] && [ -f "$src" ] && cmp -s "$dst" "$src"; }; then
      skip=true
    elif [ "${overwrite_all:-false}" = "false" ] && [ "${backup_all:-false}" = "false" ] && [ "${skip_all:-false}" = "false" ]; then
      user "File already exists: $dst ($(basename "$src")), what do you want to do?\n\
      [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
      read -n 1 action
      echo ''

      case "$action" in
        o) overwrite=true ;;
        O) overwrite_all=true ;;
        b) backup=true ;;
        B) backup_all=true ;;
        s) skip=true ;;
        S) skip_all=true ;;
        *) ;;
      esac
    fi

    overwrite=${overwrite:-${overwrite_all:-false}}
    backup=${backup:-${backup_all:-false}}
    skip=${skip:-${skip_all:-false}}

    if [ "$skip" = "true" ]; then
      success "skipped $src"
    else
      if [ "$overwrite" = "true" ]; then
        rm -rf "$dst"
        success "removed $dst"
      fi

      if [ "$backup" = "true" ]; then
        mv "$dst" "${dst}.backup"
        success "moved $dst to ${dst}.backup"
      fi
    fi
  fi

  # On platforms without symlink support `ln -s` fails, and some Windows setups
  # make it "succeed" by copying. A real symlink is confirmed with `-L`; when it
  # is not one, the artifact left behind is removed and replaced by a clean copy
  # so the result matches what symlinks_supported reports. (`-L` is only checked
  # after a successful `ln -s`, so a pre-existing user file that made `ln -s`
  # fail is never removed here.)
  if [ "$skip" != "true" ]; then
    if ln -s "$src" "$dst" 2>/dev/null; then
      if [ -L "$dst" ]; then
        success "linked $src to $dst"
      else
        rm -rf "$dst"
        cp -R "$src" "$dst"
        success "copied $src to $dst (symlinks unavailable)"
      fi
    else
      cp -R "$src" "$dst"
      success "copied $src to $dst (symlinks unavailable)"
    fi
  fi
}

# Link an application config file non-interactively, backing up any existing
# destination first.
link_config () {
  local src=$1 dst=$2
  local overwrite_all=false backup_all=true skip_all=false
  mkdir -p "$(dirname "$dst")"
  info "linking $(basename "$src")"
  link_file "$src" "$dst"
}

detect_os
