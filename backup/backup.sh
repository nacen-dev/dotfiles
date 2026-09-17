#!/usr/bin/env bash
#
# Snapshot live configuration files back into this repository.
#
# Only entries marked "yes" in backup/manifest are captured. Files that are
# already symlinked into the repository need no snapshot: editing the live
# file already edits the repo.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

CONFIG_HOME="$(config_home)"
export CONFIG_HOME

changed=0

while IFS=$'\t' read -r app repo live backup || [ -n "$app" ]; do
  case "$app" in ''|\#*) continue ;; esac
  [ "$backup" = "yes" ] || continue

  local_live="$(expand_vars "$live")"
  repo_path="$DOTFILES_ROOT/$repo"

  if [ ! -e "$local_live" ] && [ ! -L "$local_live" ]; then
    printf '  [ skip ] %s (missing)\n' "$local_live"
    continue
  fi

  if [ -L "$local_live" ]; then
    printf '  [ link ] %s -> %s\n' "$local_live" "$(readlink "$local_live")"
    continue
  fi

  if [ -f "$repo_path" ] && cmp -s "$local_live" "$repo_path"; then
    printf '  [ same ] %s\n' "$repo"
    continue
  fi

  mkdir -p "$(dirname "$repo_path")"
  cp "$local_live" "$repo_path"
  printf '  [ save ] %s -> %s\n' "$local_live" "$repo"
  changed=$((changed + 1))
done < "$DOTFILES_ROOT/backup/manifest"

printf '\n%s file(s) backed up.\n' "$changed"