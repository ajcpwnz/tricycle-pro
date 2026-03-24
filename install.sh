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

detect_shell_rc() {
  local shell_name
  shell_name=$(basename "${SHELL:-/bin/bash}")
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash)
      # Prefer .bashrc, fall back to .bash_profile (macOS default)
      if [ -f "$HOME/.bashrc" ]; then
        echo "$HOME/.bashrc"
      else
        echo "$HOME/.bash_profile"
      fi
      ;;
    fish) echo "$HOME/.config/fish/config.fish" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

add_to_path() {
  local bin_dir="$1"
  local rc_file
  rc_file=$(detect_shell_rc)
  local export_line="export PATH=\"$bin_dir:\$PATH\""

  # Already on PATH — nothing to do
  case ":$PATH:" in
    *":$bin_dir:"*) return 0 ;;
  esac

  # Already in rc file — just source it
  if [ -f "$rc_file" ] && grep -qF "$bin_dir" "$rc_file"; then
    export PATH="$bin_dir:$PATH"
    return 0
  fi

  # Append to rc file
  printf '\n# Tricycle Pro\n%s\n' "$export_line" >> "$rc_file"
  export PATH="$bin_dir:$PATH"
  echo "Added $bin_dir to PATH in $rc_file"
}

if [ "${1:-}" = "--install" ]; then
  # ─── Install mode ────────────────────────────────────────────────────────
  TARGET="${2:-$DEFAULT_INSTALL_PATH}"

  echo "Installing Tricycle Pro to $TARGET..."
  mkdir -p "$TARGET"
  fetch_tarball "$TARGET"
  chmod +x "$TARGET/bin/tricycle"

  # Try to symlink to a dir already on PATH, otherwise add to PATH via shell rc
  if [ -w /usr/local/bin ]; then
    ln -sf "$TARGET/bin/tricycle" /usr/local/bin/tricycle
    echo "Symlinked to /usr/local/bin/tricycle"
  elif [ -d "$HOME/.local/bin" ]; then
    ln -sf "$TARGET/bin/tricycle" "$HOME/.local/bin/tricycle"
    echo "Symlinked to $HOME/.local/bin/tricycle"
    add_to_path "$HOME/.local/bin"
  else
    mkdir -p "$HOME/.local/bin"
    ln -sf "$TARGET/bin/tricycle" "$HOME/.local/bin/tricycle"
    echo "Symlinked to $HOME/.local/bin/tricycle"
    add_to_path "$HOME/.local/bin"
  fi

  installed_version="unknown"
  [ -f "$TARGET/VERSION" ] && installed_version=$(cat "$TARGET/VERSION" | tr -d '[:space:]')

  echo ""
  echo "Tricycle Pro v${installed_version} installed. Run: tricycle --help"
else
  # ─── One-off mode ──────────────────────────────────────────────────────
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  echo "Fetching Tricycle Pro..." >&2
  fetch_tarball "$TMPDIR"

  chmod +x "$TMPDIR/bin/tricycle"
  "$TMPDIR/bin/tricycle" "$@"
fi
