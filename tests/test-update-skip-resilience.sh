#!/usr/bin/env bash
# Regression guards for the v0.23.1 consumer-update crash (fixed in v0.23.2):
#
# 1. install_file signals "skipped (locally modified)" with return 1, and
#    install_dir ran it unprotected — when the skipped file sorted LAST in
#    its directory, the 1 became install_dir's exit status and `set -e`
#    aborted the whole update BEFORE save_lock, freezing every file written
#    in that run as "locally modified" forever.
# 2. The trigger was self-inflicted: install_skills installed each skill's
#    SOURCE from core (locking its checksum), then regenerated SOURCE with
#    different content without updating the lock — so every skill SOURCE
#    was permanently "locally modified" and re-tripped bug 1 on every run.
#
# This test asserts: an update with a locally-modified last-sorting skill
# file exits 0, saves the lock, and surfaces the SKIP; and two consecutive
# updates converge with no SOURCE ever reported as skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Scaffold a fake toolkit root with one vendored skill whose SOURCE ships
# from core (the real repo does this for every skill).
TOOLKIT="$TMP/toolkit"
mkdir -p "$TOOLKIT/bin/lib" "$TOOLKIT/core/commands" "$TOOLKIT/core/templates" \
         "$TOOLKIT/core/scripts/bash" "$TOOLKIT/core/hooks" "$TOOLKIT/core/blocks" \
         "$TOOLKIT/core/skills/zz-skill"

cp "$REPO_ROOT/bin/tricycle" "$TOOLKIT/bin/tricycle"
cp "$REPO_ROOT/bin/lib/"*.sh "$TOOLKIT/bin/lib/"
printf '0.1.0\n' > "$TOOLKIT/VERSION"

printf 'command body\n' > "$TOOLKIT/core/commands/trc.fixture.md"
# zz-userfile.md sorts LAST in the installed skill dir (SOURCE is excluded
# from installation) — the layout that turned a skip into a fatal exit in
# v0.23.1 when that last file was locally modified.
printf 'skill body\n' > "$TOOLKIT/core/skills/zz-skill/SKILL.md"
printf 'upstream\n' > "$TOOLKIT/core/skills/zz-skill/zz-userfile.md"
printf 'origin: vendored:core/skills/zz-skill\nchecksum: stale\n' > "$TOOLKIT/core/skills/zz-skill/SOURCE"

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

cd "$CONSUMER"

# ── Run 1: fresh install converges and saves the lock. ─────────────────────
OUT1=$("$TOOLKIT/bin/tricycle" update 2>&1) \
  || { echo "FAIL: first update exited non-zero"; echo "$OUT1"; exit 1; }
[ -f "$CONSUMER/.tricycle.lock" ] || { echo "FAIL: lock not saved on run 1"; exit 1; }

# ── Run 2: must be a clean no-op for skills — in particular, SOURCE must
# never be reported as locally modified (bug 2's permanent SKIP/WRITE pair).
OUT2=$("$TOOLKIT/bin/tricycle" update 2>&1) \
  || { echo "FAIL: second update exited non-zero"; echo "$OUT2"; exit 1; }
if echo "$OUT2" | grep -q 'SKIP .*SOURCE'; then
  echo "FAIL: skill SOURCE still reads as locally modified on a converged repo"
  echo "$OUT2"
  exit 1
fi

# ── Run 3: a locally modified, lock-tracked skill file that sorts LAST in
# its directory must be SKIPped without killing the update or the lock save.
printf 'user fork\n' > "$CONSUMER/.claude/skills/zz-skill/zz-userfile.md"

# Sanity: also ship a NEW core command so we can prove post-skill work and
# the lock save still happen after the skill SKIP.
printf 'late arrival\n' > "$TOOLKIT/core/commands/zz-late.md"
LOCK_BEFORE=$(cat "$CONSUMER/.tricycle.lock")
OUT3=$("$TOOLKIT/bin/tricycle" update 2>&1) \
  || { echo "FAIL: update with last-sorting skipped skill file exited non-zero"; echo "$OUT3"; exit 1; }

echo "$OUT3" | grep -q 'SKIP .claude/skills/zz-skill/zz-userfile.md' \
  || { echo "FAIL: modified skill file not surfaced as SKIP"; echo "$OUT3"; exit 1; }
grep -q '^user fork$' "$CONSUMER/.claude/skills/zz-skill/zz-userfile.md" \
  || { echo "FAIL: user's skill file was overwritten"; exit 1; }
[ -f "$CONSUMER/.claude/commands/zz-late.md" ] \
  || { echo "FAIL: files after the skipped skill were never installed (update aborted early)"; exit 1; }
grep -q '"\.claude/commands/zz-late\.md"' "$CONSUMER/.tricycle.lock" \
  || { echo "FAIL: lock was not saved after the skill SKIP"; diff <(echo "$LOCK_BEFORE") "$CONSUMER/.tricycle.lock" || true; exit 1; }

echo "update-skip-resilience: OK"
