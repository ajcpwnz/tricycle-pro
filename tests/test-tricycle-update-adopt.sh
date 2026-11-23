#!/usr/bin/env bash
# `tricycle update` treats every core copy as an output:
#   - a file missing locally is added;
#   - a file present but untracked and identical to core is adopted;
#   - a file that differs from core, tracked or not, is overwritten;
#   - a tracked file whose core source is gone is removed.
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
cp "$REPO_ROOT/core/scripts/bash/assemble-commands.sh" "$REPO_ROOT/core/scripts/bash/common.sh" "$TOOLKIT/core/scripts/bash/"
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

# Case D: unmanaged file that DIFFERS from core → overwritten and tracked.
printf 'user hand-edit\n' > "$CONSUMER/.claude/commands/trc.userfork.md"
printf 'upstream version\n' > "$TOOLKIT/core/commands/trc.userfork.md"
"$TOOLKIT/bin/tricycle" update >/dev/null 2>&1
grep -q '^upstream version$' "$CONSUMER/.claude/commands/trc.userfork.md" \
  || { echo "FAIL: unmanaged hand edit survived update"; exit 1; }
grep -q '"\.claude/commands/trc\.userfork\.md"' "$CONSUMER/.tricycle.lock" \
  || { echo "FAIL: overwritten file not tracked in lock"; cat "$CONSUMER/.tricycle.lock"; exit 1; }

# Case E: tracked file edited locally → overwritten.
printf 'local tweak\n' > "$CONSUMER/.claude/commands/trc.existing.md"
"$TOOLKIT/bin/tricycle" update >/dev/null 2>&1
grep -q '^already present and clean$' "$CONSUMER/.claude/commands/trc.existing.md" \
  || { echo "FAIL: tracked hand edit survived update"; exit 1; }

# Case F: core drops a file → the consumer copy and its lock entry go.
rm "$TOOLKIT/core/scripts/bash/chain-run.sh"
OUT=$("$TOOLKIT/bin/tricycle" update 2>&1)
echo "$OUT" | grep -q 'REMOVE .trc/scripts/bash/chain-run.sh' \
  || { echo "FAIL: dropped core file not reported as REMOVE"; echo "$OUT"; exit 1; }
[ ! -e "$CONSUMER/.trc/scripts/bash/chain-run.sh" ] || { echo "FAIL: dropped core file still on disk"; exit 1; }
! grep -q 'chain-run\.sh' "$CONSUMER/.tricycle.lock" || { echo "FAIL: dropped core file still in lock"; exit 1; }

# A file the repo owns (never shipped by core) is never touched.
printf 'repo hook\n' > "$CONSUMER/.claude/hooks/repo-own.sh"
"$TOOLKIT/bin/tricycle" update >/dev/null 2>&1
grep -q '^repo hook$' "$CONSUMER/.claude/hooks/repo-own.sh" || { echo "FAIL: repo-owned file touched"; exit 1; }

echo "tricycle-update-adopt: OK"
