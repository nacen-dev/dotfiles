#!/usr/bin/env bash
#
# Run all dotfiles installers.

set -e

cd "$(dirname "$0")/.."

find . -path ./.git -prune -o -name install.sh -print | sort | while IFS= read -r installer; do
  echo "==> $installer"
  bash "$installer"
done
