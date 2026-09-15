#!/usr/bin/env bash
#
# Run all dotfiles installers.
#
# Each installer runs in its own subshell so a failure in one does not stop the
# others (or the rest of bootstrap.sh) from running.

set -e

cd "$(dirname "$0")/.."

failed=()

while IFS= read -r installer; do
  echo "==> $installer"
  if ! ( bash "$installer" ); then
    echo "  !! $installer failed; continuing" >&2
    failed+=("$installer")
  fi
done < <(find . -path ./.git -prune -o -name install.sh -print | sort)

if [ "${#failed[@]}" -gt 0 ]; then
  echo >&2
  echo "${#failed[@]} installer(s) failed; the rest installed successfully:" >&2
  printf '  - %s\n' "${failed[@]}" >&2
fi

exit 0
