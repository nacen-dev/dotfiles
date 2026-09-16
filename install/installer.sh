#!/usr/bin/env bash
#
# Run all dotfiles installers.
#
# Each installer runs in its own subshell so a failure in one does not stop the
# others (or the rest of bootstrap.sh) from running.
#
# Installers run in ascending priority order (lower first), then alphabetically.
# zsh is prioritized because oh-my-zsh requires it.

set -e

cd "$(dirname "$0")/.."

# Lower numbers run first. Unlisted installers use the default.
installer_priority () {
  case "$1" in
    ./zsh/install.sh) echo 0 ;;
    *)                echo 100 ;;
  esac
}

failed=()

while IFS=$'\t' read -r _ installer; do
  echo "==> $installer"
  if ! ( bash "$installer" ); then
    echo "  !! $installer failed; continuing" >&2
    failed+=("$installer")
  fi
done < <(
  while IFS= read -r installer; do
    printf '%s\t%s\n' "$(installer_priority "$installer")" "$installer"
  done < <(find . -path ./.git -prune -o -name install.sh -print) |
    sort -k1,1n -k2,2
)

if [ "${#failed[@]}" -gt 0 ]; then
  echo >&2
  echo "${#failed[@]} installer(s) failed; the rest installed successfully:" >&2
  printf '  - %s\n' "${failed[@]}" >&2
fi

exit 0
