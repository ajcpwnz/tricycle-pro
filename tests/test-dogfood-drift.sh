#!/usr/bin/env bash
# TRI-33/TRI-34 US3: fail CI if core/ files drift from their mirrored
# consumer paths in the tricycle-pro meta-repo. Silent skip in ordinary
# consumer fixtures.
#
# One-way check (TRI-34): walks core/<src> for each mapping pair and
# asserts a byte-identical file exists at <dst>/<rel>. Extras in <dst>
# (runtime-generated files like .claude/hooks/.session-context.conf,
# orphans, etc.) are NOT drift — they match what `tricycle dogfood --yes`
# would-or-would-not touch. See
# specs/TRI-34-drift-one-way/contracts/drift-check.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$REPO_ROOT/core" ]; then
    echo "dogfood-drift: skipped (not a meta-repo)"
    exit 0
fi

# Kept in lockstep with TRICYCLE_MANAGED_PATHS in bin/tricycle. If that
# array grows, update this list too (see TRI-34 research R3).
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
    if [ ! -d "$dst" ]; then
        drifted+=("$dst_rel (missing directory)")
        continue
    fi

    while IFS= read -r src_path; do
        # Skip OS-noise files — matches cmd_dogfood's mirror pass,
        # which never copies .DS_Store/Thumbs.db into the mirror.
        case "$(basename "$src_path")" in
            .DS_Store|Thumbs.db) continue ;;
        esac
        rel="${src_path#$src/}"
        dst_path="$dst/$rel"
        if [ ! -f "$dst_path" ]; then
            drifted+=("$dst_rel/$rel (missing)")
            continue
        fi
        if ! cmp -s "$src_path" "$dst_path"; then
            drifted+=("$dst_rel/$rel")
            diff_out=$(diff "$src_path" "$dst_path" 2>&1 || true)
            details="${details}--- diff $src_rel/$rel vs $dst_rel/$rel ---"$'\n'"$diff_out"$'\n'
        fi
    done < <(find "$src" -type f | sort)
done

if [ ${#drifted[@]} -gt 0 ]; then
    echo "FAIL: dogfood drift detected between core/ and mirrored paths."
    echo "Drifted paths:"
    for d in "${drifted[@]}"; do
        echo "  $d"
    done
    if [ -n "$details" ]; then
        echo ""
        echo "Detail:"
        printf '%s' "$details"
    fi
    echo ""
    echo "Fix: run \`tricycle dogfood --yes\` from the repo root to re-mirror core/,"
    echo "or intentional divergence must be lifted into core/."
    exit 1
fi

echo "dogfood-drift: OK"
