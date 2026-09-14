#!/usr/bin/env bash
#
# Python installer, managed via uv.

set -e

source "$(cd "$(dirname "$0")" && pwd)/../install/lib.sh"

# Pin the minor version so patch releases update but majors do not surprise.
PYTHON_VERSION="3.14"

# uv provides Python management; ensure it is available first.
if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required to manage Python; installing it."
  bash "$DOTFILES_ROOT/uv/install.sh"
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "Installing Python ${PYTHON_VERSION} (default)."
uv python install "$PYTHON_VERSION" --default