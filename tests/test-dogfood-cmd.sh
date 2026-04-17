#!/usr/bin/env bash
# TRI-33: fixture-based test of `tricycle dogfood`.
# Covers User Story 1 (contributor sync in a meta-repo) and
# User Story 2 (no-op in ordinary consumer repos).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_SRC="$REPO_ROOT/bin/tricycle"
LIB_SRC="$REPO_ROOT/bin/lib"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Build a synthetic meta-repo fixture ───────────────────────────────────
#
# Layout mirrors what tricycle-pro itself has: bin/ + core/ + existing
# .trc/ + .claude/ + .tricycle.lock + tricycle.config.yml.
META="$TMP/meta"
mkdir -p "$META/bin/lib"
mkdir -p "$META/core/commands" "$META/core/scripts/bash" "$META/core/hooks" \
         "$META/core/templates" "$META/core/blocks"
mkdir -p "$META/.claude/commands" "$META/.trc/scripts/bash" "$META/.claude/hooks" \
         "$META/.trc/templates" "$META/.trc/blocks"

cp "$CLI_SRC" "$META/bin/tricycle"
cp "$LIB_SRC"/*.sh "$META/bin/lib/"
chmod +x "$META/bin/tricycle"

cat > "$META/tricycle.config.yml" <<'YAML'
project:
  name: meta-fixture
  type: single-app
  package_manager: npm
  base_branch: main
YAML

# Seed core/ content.
printf 'original command\n' > "$META/core/commands/cmd1.md"
printf '#!/bin/sh\necho v1\n' > "$META/core/scripts/bash/helper.sh"
chmod +x "$META/core/scripts/bash/helper.sh"
printf '#!/bin/sh\necho hook v1\n' > "$META/core/hooks/test-hook.sh"
chmod +x "$META/core/hooks/test-hook.sh"

# Seed matching .trc/.claude content — start in sync.
cp "$META/core/commands/cmd1.md" "$META/.claude/commands/cmd1.md"
cp "$META/core/scripts/bash/helper.sh" "$META/.trc/scripts/bash/helper.sh"
chmod +x "$META/.trc/scripts/bash/helper.sh"
cp "$META/core/hooks/test-hook.sh" "$META/.claude/hooks/test-hook.sh"
chmod +x "$META/.claude/hooks/test-hook.sh"

# Seed a lock file that records these paths as clean.
seed_cs() { shasum -a 256 "$1" | cut -c1-16; }
cs_cmd1=$(seed_cs "$META/core/commands/cmd1.md")
cs_helper=$(seed_cs "$META/core/scripts/bash/helper.sh")
cs_hook=$(seed_cs "$META/core/hooks/test-hook.sh")
cat > "$META/.tricycle.lock" <<EOF
{
  "version": "0.1.0",
  "installed": "2026-01-01",
  "files": {
    ".claude/commands/cmd1.md": { "checksum": "$cs_cmd1", "customized": false },
    ".trc/scripts/bash/helper.sh": { "checksum": "$cs_helper", "customized": false },
    ".claude/hooks/test-hook.sh": { "checksum": "$cs_hook", "customized": false }
  }
}
EOF

# ── Case (a): clean mirror → "Nothing to do" ──────────────────────────────

out=$(cd "$META" && bash "$META/bin/tricycle" dogfood 2>&1)
printf '%s' "$out" | grep -q "Nothing to do" \
    || { echo "FAIL [a]: expected 'Nothing to do' on clean mirror; got:"; echo "$out"; exit 1; }

# ── Case (b): drift a file → dry-run reports WRITE, no file changes ───────

printf 'modified command\n' > "$META/core/commands/cmd1.md"
out=$(cd "$META" && bash "$META/bin/tricycle" dogfood 2>&1)
printf '%s' "$out" | grep -q "WRITE  .claude/commands/cmd1.md" \
    || { echo "FAIL [b]: missing WRITE line for drifted path; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "Dry run. Re-run with --yes to apply." \
    || { echo "FAIL [b]: missing dry-run message"; echo "$out"; exit 1; }
grep -q "original command" "$META/.claude/commands/cmd1.md" \
    || { echo "FAIL [b]: dest file mutated during dry-run"; exit 1; }

# ── Case (c): --yes applies writes and adopts into lock ───────────────────

out=$(cd "$META" && bash "$META/bin/tricycle" dogfood --yes 2>&1)
diff "$META/core/commands/cmd1.md" "$META/.claude/commands/cmd1.md" >/dev/null \
    || { echo "FAIL [c]: file not overwritten"; exit 1; }
new_cs=$(seed_cs "$META/core/commands/cmd1.md")
grep -q "\"checksum\": \"$new_cs\"" "$META/.tricycle.lock" \
    || { echo "FAIL [c]: lock not updated with new checksum"; cat "$META/.tricycle.lock"; exit 1; }
printf '%s' "$out" | grep -q "0 added, 1 adopted" \
    || { echo "FAIL [c]: expected summary '0 added, 1 adopted'; got:"; echo "$out"; exit 1; }

# ── Case (d): ADD a new core/ file → --yes creates mapped dst ────────────

printf 'new hook v1\n' > "$META/core/hooks/brand-new.sh"
chmod +x "$META/core/hooks/brand-new.sh"
out=$(cd "$META" && bash "$META/bin/tricycle" dogfood 2>&1)
printf '%s' "$out" | grep -q "ADD    .claude/hooks/brand-new.sh" \
    || { echo "FAIL [d]: missing ADD line for new core file; got:"; echo "$out"; exit 1; }
(cd "$META" && bash "$META/bin/tricycle" dogfood --yes >/dev/null 2>&1)
[ -f "$META/.claude/hooks/brand-new.sh" ] \
    || { echo "FAIL [d]: new file not created at dst"; exit 1; }
[ -x "$META/.claude/hooks/brand-new.sh" ] \
    || { echo "FAIL [d]: new file not executable"; exit 1; }

# ── Case (e): unmapped-core file surfaces as warning ──────────────────────

mkdir -p "$META/core/uncharted"
printf 'new\n' > "$META/core/uncharted/wild.md"
out=$(cd "$META" && bash "$META/bin/tricycle" dogfood 2>&1)
printf '%s' "$out" | grep -q "unmapped paths under core/" \
    || { echo "FAIL [e]: missing unmapped warning; got:"; echo "$out"; exit 1; }
printf '%s' "$out" | grep -q "core/uncharted" \
    || { echo "FAIL [e]: unmapped entry not listed; got:"; echo "$out"; exit 1; }
# The unmapped file must NOT be mirrored.
[ -f "$META/.trc/uncharted/wild.md" ] \
    && { echo "FAIL [e]: unmapped file was silently mirrored"; exit 1; } || true
[ -f "$META/.claude/uncharted/wild.md" ] \
    && { echo "FAIL [e]: unmapped file was silently mirrored"; exit 1; } || true
rm -rf "$META/core/uncharted"

# ── Case (e2): .DS_Store noise is silently skipped ────────────────────────

# Plant OS-noise files at top-level and nested. Neither should appear in
# the dry-run output, the unmapped warning, or the mirror after --yes.
dd if=/dev/zero of="$META/core/.DS_Store" bs=1 count=8 2>/dev/null
dd if=/dev/zero of="$META/core/scripts/bash/.DS_Store" bs=1 count=8 2>/dev/null
out=$(cd "$META" && bash "$META/bin/tricycle" dogfood 2>&1)
if printf '%s' "$out" | grep -q "DS_Store"; then
    echo "FAIL [e2]: dry-run mentions .DS_Store; got:"; echo "$out"; exit 1
fi
(cd "$META" && bash "$META/bin/tricycle" dogfood --yes >/dev/null 2>&1)
[ -f "$META/.trc/scripts/bash/.DS_Store" ] \
    && { echo "FAIL [e2]: .DS_Store was mirrored into .trc/"; exit 1; } || true
rm -f "$META/core/.DS_Store" "$META/core/scripts/bash/.DS_Store"

# ── Case (f): exec bit restored by --yes (FR-005) ─────────────────────────

chmod -x "$META/.trc/scripts/bash/helper.sh"
# Need to drift the content too, otherwise nothing triggers a WRITE. Drift
# the source file by one byte so the helper gets re-written.
printf '#!/bin/sh\necho v2\n' > "$META/core/scripts/bash/helper.sh"
chmod +x "$META/core/scripts/bash/helper.sh"
(cd "$META" && bash "$META/bin/tricycle" dogfood --yes >/dev/null 2>&1)
[ -x "$META/.trc/scripts/bash/helper.sh" ] \
    || { echo "FAIL [f]: +x not restored by --yes on overwrite"; exit 1; }

# ── Case (g): ordinary consumer repo (no core/) is no-op ──────────────────

CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/bin/lib" "$CONSUMER/.claude/commands" "$CONSUMER/.trc"
cp "$CLI_SRC" "$CONSUMER/bin/tricycle"
cp "$LIB_SRC"/*.sh "$CONSUMER/bin/lib/"
chmod +x "$CONSUMER/bin/tricycle"
cat > "$CONSUMER/tricycle.config.yml" <<'YAML'
project:
  name: consumer-fixture
  type: single-app
  package_manager: npm
  base_branch: main
YAML
printf 'existing command\n' > "$CONSUMER/.claude/commands/cmd.md"
# Snapshot timestamps before running.
pre=$(find "$CONSUMER" -type f -not -path '*/bin/*' | sort | xargs shasum -a 256 | shasum -a 256)

out=$(cd "$CONSUMER" && bash "$CONSUMER/bin/tricycle" dogfood 2>&1)
printf '%s' "$out" | grep -q "Not a tricycle-pro meta-repo" \
    || { echo "FAIL [g]: expected no-op skip message; got:"; echo "$out"; exit 1; }

post=$(find "$CONSUMER" -type f -not -path '*/bin/*' | sort | xargs shasum -a 256 | shasum -a 256)
[ "$pre" = "$post" ] \
    || { echo "FAIL [g]: consumer repo mutated during no-op"; exit 1; }

echo "dogfood-cmd: OK"
