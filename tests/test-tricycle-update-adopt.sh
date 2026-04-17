#!/usr/bin/env bash
# Covers the update auto-discovery fix from the April-17 bugfix batch:
# `tricycle update` must not silently drop files that exist in the consumer
# tree but are not in the lock (the pre-fix silent-drop bug that let
# trc.chain.md / chain-run.sh stay pinned to a pre-TRI-30 version).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Scaffold a fake toolkit root.
TOOLKIT="$TMP/toolkit"
mkdir -p "$TOOLKIT/bin/lib" "$TOOLKIT/core/commands" "$TOOLKIT/core/templates" \
         "$TOOLKIT/core/scripts/bash" "$TOOLKIT/core/hooks" "$TOOLKIT/core/blocks" \
         "$TOOLKIT/core/skills"

cp "$REPO_ROOT/bin/tricycle" "$TOOLKIT/bin/tricycle"
cp "$REPO_ROOT/bin/lib/"*.sh "$TOOLKIT/bin/lib/"
printf '0.1.0\n' > "$TOOLKIT/VERSION"

# Stable source files the consumer should receive.
printf 'NEW v2 content\n' > "$TOOLKIT/core/commands/trc.chain.md"
printf 'already present and clean\n' > "$TOOLKIT/core/commands/trc.existing.md"
printf 'worker helper\n' > "$TOOLKIT/core/scripts/bash/chain-run.sh"

# Scaffold a consumer project.
CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/.claude/commands" "$CONSUMER/.trc/templates" \
         "$CONSUMER/.trc/scripts/bash" "$CONSUMER/.claude/hooks" "$CONSUMER/.trc/blocks"

cat > "$CONSUMER/tricycle.config.yml" <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
worktree:
  enabled: false
YAML

# Case A: trc.chain.md exists in consumer (manually copied) but is NOT in the
# lock — this is the pre-fix silent-drop case.
printf 'NEW v2 content\n' > "$CONSUMER/.claude/commands/trc.chain.md"

# Case B: trc.existing.md is managed and clean — baseline.
printf 'already present and clean\n' > "$CONSUMER/.claude/commands/trc.existing.md"

# Case C: chain-run.sh is missing entirely — should be ADDed.

# Build a lock that only tracks trc.existing.md (the realistic pre-fix state).
cs_existing=$(printf 'already present and clean\n' | shasum -a 256 | cut -c1-16)
cat > "$CONSUMER/.tricycle.lock" <<EOF
{
  "version": "0.1.0",
  "installed": "2026-01-01",
  "files": {
    ".claude/commands/trc.existing.md": {
      "checksum": "$cs_existing",
      "customized": false
    }
  }
}
EOF

# Run update. Must not error.
cd "$CONSUMER"
OUTPUT=$("$TOOLKIT/bin/tricycle" update 2>&1)

echo "$OUTPUT" | grep -q 'adopted' || { echo "FAIL: summary does not mention adopted"; echo "$OUTPUT"; exit 1; }

# trc.chain.md (unmanaged, matches core) → adopted into lock.
grep -q '"\.claude/commands/trc\.chain\.md"' "$CONSUMER/.tricycle.lock" \
  || { echo "FAIL: trc.chain.md not adopted into lock"; cat "$CONSUMER/.tricycle.lock"; exit 1; }

# chain-run.sh (missing locally) → ADDed.
[ -f "$CONSUMER/.trc/scripts/bash/chain-run.sh" ] \
  || { echo "FAIL: chain-run.sh not added"; exit 1; }
grep -q '"\.trc/scripts/bash/chain-run\.sh"' "$CONSUMER/.tricycle.lock" \
  || { echo "FAIL: chain-run.sh not recorded in lock"; cat "$CONSUMER/.tricycle.lock"; exit 1; }

# Case D: unmanaged file that DIFFERS from core → skipped, recorded as customized.
printf 'user hand-edit\n' > "$CONSUMER/.claude/commands/trc.userfork.md"
printf 'upstream version\n' > "$TOOLKIT/core/commands/trc.userfork.md"
OUTPUT2=$("$TOOLKIT/bin/tricycle" update 2>&1)
echo "$OUTPUT2" | grep -q 'SKIP .claude/commands/trc.userfork.md' \
  || { echo "FAIL: unmanaged/modified file not surfaced as SKIP"; echo "$OUTPUT2"; exit 1; }
grep -q '"customized": true' "$CONSUMER/.tricycle.lock" \
  || { echo "FAIL: customized flag not recorded"; cat "$CONSUMER/.tricycle.lock"; exit 1; }

# Ensure the user's content was NOT overwritten.
grep -q '^user hand-edit$' "$CONSUMER/.claude/commands/trc.userfork.md" \
  || { echo "FAIL: user file overwritten"; exit 1; }

echo "tricycle-update-adopt: OK"
