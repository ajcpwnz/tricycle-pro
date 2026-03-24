#!/usr/bin/env bash
set -euo pipefail
# install.sh — Bootstrapper for one-off execution and system installation
# Usage:
#   One-off:  curl -sL https://github.com/ajcpwnz/tricycle-pro/raw/main/install.sh | bash -s init --preset single-app
#   Install:  curl -sL https://github.com/ajcpwnz/tricycle-pro/raw/main/install.sh | bash -s -- --install [target-path]

TARBALL_URL="${TRICYCLE_REPO:-https://github.com/ajcpwnz/tricycle-pro/archive/main.tar.gz}"
DEFAULT_INSTALL_PATH="$HOME/.tricycle-pro"

error() { echo "Error: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || error "curl is required but not installed."
command -v tar >/dev/null 2>&1 || error "tar is required but not installed."

fetch_tarball() {
  local dest="$1"
  curl -sL "$TARBALL_URL" | tar xz -C "$dest" --strip-components=1
}

if [ "${1:-}" = "--install" ]; then
  # ─── Install mode ────────────────────────────────────────────────────────
  TARGET="${2:-$DEFAULT_INSTALL_PATH}"

  echo "Installing Tricycle Pro to $TARGET..."
  mkdir -p "$TARGET"
  fetch_tarball "$TARGET"
  chmod +x "$TARGET/bin/tricycle"

  # Try to create symlink
  local_bin="$HOME/.local/bin"
  if [ -d "$local_bin" ]; then
    ln -sf "$TARGET/bin/tricycle" "$local_bin/tricycle"
    echo "Symlinked to $local_bin/tricycle"
    echo ""
    echo "Tricycle Pro installed. Run: tricycle --help"
  else
    echo ""
    echo "Tricycle Pro installed. Add to your PATH:"
    echo "  export PATH=\"$TARGET/bin:\$PATH\""
    echo ""
    echo "Or create a symlink:"
    echo "  ln -s $TARGET/bin/tricycle /usr/local/bin/tricycle"
  fi
else
  # ─── One-off mode ──────────────────────────────────────────────────────
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  echo "Fetching Tricycle Pro..." >&2
  fetch_tarball "$TMPDIR"

  chmod +x "$TMPDIR/bin/tricycle"
  "$TMPDIR/bin/tricycle" "$@"
fi
