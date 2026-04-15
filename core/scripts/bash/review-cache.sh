#!/usr/bin/env bash
set -euo pipefail

# review-cache.sh — cache-path helper for /trc.review remote sources.
#
# Usage:
#   review-cache.sh path <url>        # print the cache file path for <url>
#   review-cache.sh ensure-dir        # mkdir -p the cache directory
#   review-cache.sh cache-dir         # print the cache directory path
#
# Cache layout: .trc/cache/review-sources/<sha256(url)>.md
# The cache is gitignored via the project-wide .trc/ ignore.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/bin/lib/helpers.sh"

CACHE_DIR="$REPO_ROOT/.trc/cache/review-sources"

cmd="${1:-}"

case "$cmd" in
  path)
    url="${2:-}"
    if [ -z "$url" ]; then
      echo "error: review-cache.sh path <url> requires a URL" >&2
      exit 2
    fi
    detect_sha256
    hash="$(sha256_str "$url")"
    echo "$CACHE_DIR/$hash.md"
    ;;
  ensure-dir)
    mkdir -p "$CACHE_DIR"
    echo "$CACHE_DIR"
    ;;
  cache-dir)
    echo "$CACHE_DIR"
    ;;
  *)
    echo "usage: review-cache.sh {path <url>|ensure-dir|cache-dir}" >&2
    exit 2
    ;;
esac
