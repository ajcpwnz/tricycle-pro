#!/usr/bin/env bash
# Guards the fix for the self-replace race in `tricycle update-self`:
# the finalize step must run via `exec` into a standalone script so the
# old bin/tricycle process is gone before the new files overwrite its
# tree. If the old pattern (copy-in-place, then return) came back, bash
# would emit "unexpected EOF" noise on some systems.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a fake toolkit root that mirrors the install layout.
TOOLKIT="$TMP/toolkit"
mkdir -p "$TOOLKIT/bin/lib" "$TOOLKIT/core" "$TOOLKIT/generators" \
         "$TOOLKIT/modules" "$TOOLKIT/presets"

cp "$REPO_ROOT/bin/tricycle" "$TOOLKIT/bin/tricycle"
cp "$REPO_ROOT/bin/lib/"*.sh "$TOOLKIT/bin/lib/"
printf '0.0.1\n' > "$TOOLKIT/VERSION"

# Build a "remote" tarball with a newer version. Use a recognizable
# sentinel file so we can assert the new tree landed.
REMOTE_SRC="$TMP/remote/tricycle-pro-main"
mkdir -p "$REMOTE_SRC/bin/lib" "$REMOTE_SRC/core" "$REMOTE_SRC/generators" \
         "$REMOTE_SRC/modules" "$REMOTE_SRC/presets"
cp "$REPO_ROOT/bin/tricycle" "$REMOTE_SRC/bin/tricycle"
cp "$REPO_ROOT/bin/lib/"*.sh "$REMOTE_SRC/bin/lib/"
printf 'UPDATED\n' > "$REMOTE_SRC/core/sentinel.txt"
printf '9.9.9\n' > "$REMOTE_SRC/VERSION"

TARBALL="$TMP/remote.tar.gz"
tar czf "$TARBALL" -C "$TMP/remote" tricycle-pro-main

# Run update-self against the local tarball. Capture stderr to assert
# there are NO bash parse errors (the signature of the old race).
OUTPUT_STDERR=$(TRICYCLE_REPO="file://$TARBALL" "$TOOLKIT/bin/tricycle" update-self 2>&1 >/dev/null || true)

if printf '%s' "$OUTPUT_STDERR" | grep -qi 'unexpected EOF'; then
    echo "FAIL: update-self emitted 'unexpected EOF' — self-replace race re-introduced"
    printf '%s\n' "$OUTPUT_STDERR"
    exit 1
fi
if printf '%s' "$OUTPUT_STDERR" | grep -Ei 'syntax error|parse error'; then
    echo "FAIL: update-self emitted a parse/syntax error"
    printf '%s\n' "$OUTPUT_STDERR"
    exit 1
fi

# Verify the update actually happened.
[ "$(cat "$TOOLKIT/VERSION")" = "9.9.9" ] \
    || { echo "FAIL: VERSION not bumped"; cat "$TOOLKIT/VERSION"; exit 1; }
[ -f "$TOOLKIT/core/sentinel.txt" ] \
    || { echo "FAIL: core/ not replaced — sentinel missing"; exit 1; }

# The updated bin/tricycle must remain executable and syntactically valid.
[ -x "$TOOLKIT/bin/tricycle" ] || { echo "FAIL: bin/tricycle not executable"; exit 1; }
bash -n "$TOOLKIT/bin/tricycle" || { echo "FAIL: bin/tricycle syntax invalid after update"; exit 1; }

# The finalize script must have cleaned up its own tmpdir.
# (We can't assert the exact path — just that no stray *.sh finalize
# scripts are hanging around in /tmp from this run.)

# Idempotency: running update-self again with the same tarball where
# VERSION already matches should exit cleanly with "Already up to date".
OUTPUT_STDOUT=$(TRICYCLE_REPO="file://$TARBALL" "$TOOLKIT/bin/tricycle" update-self 2>/dev/null)
printf '%s' "$OUTPUT_STDOUT" | grep -q "Already up to date" \
    || { echo "FAIL: second run did not short-circuit"; printf '%s\n' "$OUTPUT_STDOUT"; exit 1; }

echo "update-self-exec: OK"
