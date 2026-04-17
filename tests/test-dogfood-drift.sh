#!/usr/bin/env bash
# TRI-33 US3: fail CI if core/ and its mirrored consumer paths drift in
# the tricycle-pro meta-repo. Silent skip in ordinary consumer fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$REPO_ROOT/core" ]; then
    echo "dogfood-drift: skipped (not a meta-repo)"
    exit 0
fi

# Kept in lockstep with TRICYCLE_MANAGED_PATHS in bin/tricycle. If that
# array grows, update this list too. (A test-time source-and-eval of the
# array is possible but couples the test to bin/tricycle's load order.)
MAPPINGS=(
  "core/commands:.claude/commands"
  "core/templates:.trc/templates"
  "core/scripts/bash:.trc/scripts/bash"
  "core/hooks:.claude/hooks"
  "core/blocks:.trc/blocks"
)

drifted=()
details=""

for mapping in "${MAPPINGS[@]}"; do
    src_rel="${mapping%%:*}"
    dst_rel="${mapping#*:}"
    src="$REPO_ROOT/$src_rel"
    dst="$REPO_ROOT/$dst_rel"
    [ -d "$src" ] || continue
    # Missing destination directory is itself a drift.
    if [ ! -d "$dst" ]; then
        drifted+=("$dst_rel (missing)")
        continue
    fi
    diff_out=$(diff -r "$src" "$dst" 2>&1 || true)
    if [ -n "$diff_out" ]; then
        drifted+=("$dst_rel")
        details="${details}--- diff $src_rel vs $dst_rel ---"$'\n'"$diff_out"$'\n'
    fi
done

if [ ${#drifted[@]} -gt 0 ]; then
    echo "FAIL: dogfood drift detected between core/ and mirrored paths."
    echo "Drifted paths:"
    for d in "${drifted[@]}"; do
        echo "  $d"
    done
    echo ""
    echo "Detail:"
    printf '%s' "$details"
    echo ""
    echo "Fix: run \`tricycle dogfood --yes\` from the repo root to re-mirror core/,"
    echo "or intentional divergence must be lifted into core/."
    exit 1
fi

echo "dogfood-drift: OK"
