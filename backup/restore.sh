#!/usr/bin/env bash
#
# Deploy this repository's configuration files onto the machine as symlinks,
# backing up any conflicting files first.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

CONFIG_HOME="$(config_home)"
export CONFIG_HOME

while IFS=$'\t' read -r app repo live backup || [ -n "$app" ]; do
  case "$app" in ''|\#*) continue ;; esac

  local_live="$(eval printf '%s' "$live")"
  repo_path="$DOTFILES_ROOT/$repo"

  if [ ! -e "$repo_path" ]; then
    printf '  [ skip ] %s (not in repo)\n' "$live"
    continue
  fi

  link_config "$repo_path" "$local_live"
done < "$DOTFILES_ROOT/backup/manifest"

success 'configuration restored'